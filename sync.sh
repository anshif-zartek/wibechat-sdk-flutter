#!/usr/bin/env bash
#
# Pulls the latest LiveKit upstream into `main`, then rebuilds the WibeChat
# branded branch on top of it.
#
#   ./sync.sh               sync, rebrand, run checks, push both branches
#   ./sync.sh --no-push     same, but leave everything local
#   ./sync.sh --skip-checks skip flutter analyze / flutter test
#   ./sync.sh --abort       give up on a sync that stopped halfway and restore
#                           the branch to how it was before
#
# Branch layout this script maintains:
#
#   main                exact copy of upstream (fast-forward only, never commit here)
#   wibechat-branding   main
#                       + tooling commits (sync.sh, tool/, branding/)
#                       + one generated "rebrand: apply" commit
#                       + your WibeChat commits, written against the branded code
#
# Just commit on top of wibechat-branding as usual. On every sync the generated
# commit is thrown away and rebuilt by tool/rebrand.dart, so renamed names never
# cause merge conflicts. Commits that only touch tooling files are moved before
# it (so a changed rebrand rule takes effect); all other commits are replayed
# after it.

set -euo pipefail

UPSTREAM_URL="https://github.com/livekit/client-sdk-flutter.git"
UPSTREAM_BRANCH="main"
MAIN_BRANCH="main"
BRAND_BRANCH="wibechat-branding"
BACKUP_BRANCH="wibechat-branding-backup"
REBRAND_SUBJECT="rebrand: apply"

# Everything runs inside main() so bash has read the whole file before git
# rewrites the working tree underneath it.
main() {
  local push=1 checks=1
  for arg in "$@"; do
    case "$arg" in
      --no-push) push=0 ;;
      --skip-checks) checks=0 ;;
      --abort) abort_sync; exit 0 ;;
      -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
      *) die "unknown option: $arg" ;;
    esac
  done

  cd "$(git rev-parse --show-toplevel)"
  local state
  state="$(git rev-parse --git-path wibechat-sync-state)"

  [[ "$(git branch --show-current)" == "$BRAND_BRANCH" ]] \
    || die "check out $BRAND_BRANCH first (git switch $BRAND_BRANCH)"
  in_progress && die "a rebase or cherry-pick is in progress. Finish it (git add <files>, then
       git rebase --continue / git cherry-pick --continue) and run ./sync.sh again,
       or undo the whole sync with ./sync.sh --abort"
  [[ -z "$(git status --porcelain)" ]] \
    || die "working tree has uncommitted changes; commit or stash them first"

  step "Fetching upstream and origin"
  if git remote get-url upstream >/dev/null 2>&1; then
    git remote set-url upstream "$UPSTREAM_URL"
  else
    git remote add upstream "$UPSTREAM_URL"
  fi
  # --no-tags: LiveKit's vX.Y.Z tags would collide with our own release tags.
  git fetch upstream --prune --no-tags
  git fetch origin --prune

  # The branded branch is force-pushed on every sync. If someone else synced or
  # pushed since we last pulled, stop instead of overwriting their work.
  local remote_brand_sha=""
  if remote_brand_sha="$(git rev-parse --verify --quiet "origin/$BRAND_BRANCH")" && [[ ! -f "$state" ]] \
    && ! git merge-base --is-ancestor "$remote_brand_sha" HEAD; then
    die "origin/$BRAND_BRANCH has changed since you last pulled (someone else synced or pushed).
       If you have no local commits of your own:  git reset --hard origin/$BRAND_BRANCH
       Otherwise cherry-pick your commits onto origin/$BRAND_BRANCH first. Then run ./sync.sh again."
  fi

  local upstream_ref="upstream/$UPSTREAM_BRANCH"
  local upstream_sha
  upstream_sha="$(git rev-parse --short "$upstream_ref")"

  step "Updating $MAIN_BRANCH to $upstream_ref ($upstream_sha)"
  for ref in "$MAIN_BRANCH" "origin/$MAIN_BRANCH"; do
    if git rev-parse --verify --quiet "$ref" >/dev/null && ! git merge-base --is-ancestor "$ref" "$upstream_ref"; then
      die "$ref has commits that are not in upstream. $MAIN_BRANCH must stay an exact copy of upstream;
       move those commits to $BRAND_BRANCH and reset $MAIN_BRANCH before syncing."
    fi
  done
  # Fast-forward without checking main out (this script is not on main).
  git update-ref "refs/heads/$MAIN_BRANCH" "$upstream_ref"

  step "Rebuilding $BRAND_BRANCH on top of $MAIN_BRANCH"
  # rebrand_commit: the previous generated commit; old_head: the branch tip
  # before this sync. Commits in rebrand_commit..old_head were made on top of
  # the branded code.
  local rebrand_commit old_head
  if [[ -f "$state" ]]; then
    # Resuming after a stop: HEAD already holds the tooling commits without
    # the generated commit.
    read -r rebrand_commit old_head < "$state"
    echo "Resuming the previous sync."
  else
    old_head="$(git rev-parse HEAD)"
    rebrand_commit="$(git log -n1 --format=%H --grep="^$REBRAND_SUBJECT" "$MAIN_BRANCH..HEAD")"
    git branch -f "$BACKUP_BRANCH" "$old_head"
    echo "${rebrand_commit:--} $old_head" > "$state"
    if [[ -n "$rebrand_commit" ]]; then
      git reset --hard --quiet "$rebrand_commit~1"
      # Tooling changes made after the last rebrand must apply before the new one.
      local c
      for c in $(own_commits "$rebrand_commit" "$old_head"); do
        is_tooling "$c" || continue
        git cherry-pick "$c" >/dev/null || die "could not move tooling commit $(git log -1 --format='%h %s' "$c")
       before the rebrand commit. Undo with ./sync.sh --abort and fix it by hand."
      done
    fi
  fi
  [[ "$rebrand_commit" == "-" ]] && rebrand_commit=""

  if ! git rebase "$MAIN_BRANCH"; then
    cat >&2 <<EOF

Conflict while replaying the tooling commits onto the new upstream.
  1. Fix the conflicted files, then: git add <files> && git rebase --continue
  2. Run ./sync.sh again to finish.
(Or undo the whole sync with: ./sync.sh --abort)
EOF
    exit 1
  fi

  step "Rebranding"
  dart tool/rebrand.dart || die "rebrand failed. Discard its partial changes with
       git reset --hard && git clean -fd
       then fix tool/rebrand.dart, commit the fix and run ./sync.sh again.
       (Or undo the whole sync with: ./sync.sh --abort)"

  step "Formatting"
  flutter pub get >/dev/null
  (cd example && flutter pub get >/dev/null)
  dart run import_sorter:main --no-comments >/dev/null
  # Leave tool/ alone so tooling commits never conflict with the generated one.
  git ls-files -z '*.dart' ':!tool/' | xargs -0 dart format >/dev/null

  git add -A
  git commit --quiet -m "$REBRAND_SUBJECT (upstream $upstream_sha)" \
    -m "Generated by tool/rebrand.dart from $UPSTREAM_URL@$upstream_sha. Do not edit; rerun ./sync.sh."
  rm -f "$state"

  if [[ -n "$rebrand_commit" ]]; then
    local replay=() c
    for c in $(own_commits "$rebrand_commit" "$old_head"); do
      is_tooling "$c" || replay+=("$c")
    done
    if [[ ${#replay[@]} -gt 0 ]]; then
      step "Replaying ${#replay[@]} WibeChat commit(s)"
      if ! git cherry-pick "${replay[@]}"; then
        cat >&2 <<EOF

Conflict while replaying your WibeChat commits onto the new upstream.
  1. Fix the conflicted files, then: git add <files> && git cherry-pick --continue
  2. Run ./sync.sh again to check and push.
(Or undo the whole sync with: ./sync.sh --abort)
EOF
        exit 1
      fi
    fi
  fi

  if [[ $checks -eq 1 ]]; then
    step "Checking"
    if ! { flutter analyze && flutter test; }; then
      echo >&2
      echo "Checks failed. Nothing was pushed. Fix the problem in a new commit and run ./sync.sh again." >&2
      echo "(Or undo the whole sync with: ./sync.sh --abort)" >&2
      exit 1
    fi
  fi

  if [[ $push -eq 1 ]]; then
    step "Pushing"
    git push origin "$MAIN_BRANCH"
    # The branded branch is rebuilt each sync, so its history is rewritten. The
    # lease makes the push fail if someone pushed after our fetch above.
    git push --force-with-lease="$BRAND_BRANCH:$remote_brand_sha" origin "$BRAND_BRANCH"
    git branch -D --quiet "$BACKUP_BRANCH"
  fi

  step "Done: $MAIN_BRANCH = upstream $upstream_sha, $BRAND_BRANCH rebranded on top"
  [[ $push -eq 1 ]] || echo "Not pushed (--no-push). Undo with ./sync.sh --abort if the result looks wrong."
}

abort_sync() {
  cd "$(git rev-parse --show-toplevel)"
  git rev-parse --verify --quiet "$BACKUP_BRANCH" >/dev/null || die "no unfinished sync to abort"
  [[ "$(git branch --show-current)" == "$BRAND_BRANCH" || -d "$(git rev-parse --git-path rebase-merge)" ]] \
    || die "check out $BRAND_BRANCH first"
  git rebase --abort 2>/dev/null || true
  git cherry-pick --abort 2>/dev/null || true
  git reset --hard --quiet "$BACKUP_BRANCH"
  git clean -fdq
  git branch -D --quiet "$BACKUP_BRANCH"
  rm -f "$(git rev-parse --git-path wibechat-sync-state)"
  echo "Restored $BRAND_BRANCH to $(git rev-parse --short HEAD), as it was before the sync."
}

# Your own commits between two points, oldest first.
own_commits() { git rev-list --reverse --no-merges "$1..$2"; }

# True if a commit only touches the sync tooling.
is_tooling() {
  local f
  while read -r f; do
    [[ "$f" == sync.sh || "$f" == tool/* || "$f" == branding/* ]] || return 1
  done < <(git diff-tree --no-commit-id --name-only -r "$1")
}

in_progress() {
  [[ -d "$(git rev-parse --git-path rebase-merge)" || -d "$(git rev-parse --git-path rebase-apply)" \
    || -f "$(git rev-parse --git-path CHERRY_PICK_HEAD)" ]]
}

step() { printf '\n==> %s\n' "$*"; }
die() { printf 'sync.sh: %s\n' "$*" >&2; exit 1; }

main "$@"
