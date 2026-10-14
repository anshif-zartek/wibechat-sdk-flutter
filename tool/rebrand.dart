// Rebrands this fork of the LiveKit Flutter SDK as WibeChat.
//
// Run from the repository root on an unbranded tree (upstream code plus our own
// commits):
//
//   dart tool/rebrand.dart
//
// sync.sh runs this after every upstream sync, so never hand-edit the renamed
// names: change the rules below instead. The script is idempotent; running it on
// an already-branded tree changes nothing.
//
// What it does, in order:
//   1. Renames tracked files/folders whose path contains a LiveKit name.
//   2. Rewrites LiveKit names in file contents, keeping protected text intact.
//   3. Copies branding/overlay/** over the tree (WibeChat README, CHANGELOG, ...).
//   4. Fails if any LiveKit name is left that is not deliberately protected.

import 'dart:io';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const brand = 'WibeChat'; // replaces LiveKit, Livekit
const brandCamel = 'wibeChat'; // replaces liveKit
const brandLower = 'wibechat'; // replaces livekit (package name, io.livekit.* ids, logger name)
const brandUpper = 'WIBECHAT'; // replaces LIVEKIT
// Flutter derives the Linux/Windows plugin header and C symbols from pluginClass
// in snake case (LiveKitPlugin -> live_kit_plugin), so this must stay in sync
// with `brand`.
const brandSnake = 'wibe_chat'; // replaces live_kit

const repoUrl = 'https://github.com/anshif-zartek/wibechat-sdk-flutter';
const upstreamRepoUrl = 'https://github.com/livekit/client-sdk-flutter';

/// Paths (prefixes) that are left completely untouched, both contents and name.
const excluded = <String>[
  // Generated from the LiveKit protocol; names must match the wire protocol.
  'lib/src/proto/',
  // Maintained by hand (or through branding/overlay) to avoid upstream conflicts.
  '.github/',
  '.changes/',
  'branding/',
  'tool/rebrand.dart',
  'sync.sh',
  'README.md',
  'CHANGELOG.md',
  'AGENTS.md',
  'CLAUDE.md',
  // Apache-2.0: the original license and notices must be kept as they are.
  'LICENSE',
  'NOTICE',
  // Example app native projects (bundle ids, Xcode targets, icons) are not part
  // of the published SDK and are fragile to rename automatically.
  'example/android/',
  'example/ios/',
  'example/macos/',
  'example/linux/',
  'example/windows/',
];

/// Text that must keep the LiveKit name, because it refers to something that
/// really is LiveKit (attribution, hosted services, wire protocol, artifacts we
/// depend on). Matches are masked before renaming and restored afterwards.
final protected = <RegExp>[
  // Apache-2.0 attribution in license headers.
  RegExp(r'^.*Copyright.*$', multiLine: true),
  // LiveKit-hosted services and email addresses (livekit.io / .cloud / .run).
  // Hostnames are case-insensitive, and tests use mixed-case ones on purpose.
  RegExp(r'[\w.@/:-]*livekit\.(?:io|cloud|run)\b[\w./:?=&%#-]*', caseSensitive: false),
  // Other LiveKit repositories (protocol, agents, server SDKs).
  RegExp(r'github\.com/livekit/[\w./#-]*', caseSensitive: false),
  // Maven artifacts published by LiveKit (io.livekit:noise).
  RegExp(r'io\.livekit:[\w.:-]+'),
  // Protobuf files generated from the LiveKit protocol.
  RegExp(r'livekit_(?:models|rtc|metrics)'),
  // LiveKit products the SDK talks to.
  RegExp(r'LiveKit (?:Cloud|Agents)|livekit-agents'),
  // Example-app channel whose native side lives in excluded example/android.
  RegExp(r'livekit_incall'),
];

/// Applied before masking, so they also rewrite text inside protected matches.
final preRules = <(RegExp, String)>[
  (RegExp(RegExp.escape(upstreamRepoUrl)), repoUrl),
];

/// Applied only to files whose path ends with the given suffix.
final fileRules = <String, List<(RegExp, String)>>{
  '.podspec': [
    (RegExp(r'^(\s*s\.homepage\s*=\s*).*$', multiLine: true), "\$1'$repoUrl'"),
    (RegExp(r'^(\s*s\.author\s*=\s*).*$', multiLine: true), "\$1'$brand'"),
  ],
};

/// Name rules, applied in order to both paths and contents.
const rules = <(String, String)>[
  ('LiveKit', brand),
  ('Livekit', brand),
  ('liveKit', brandCamel),
  ('LIVE_KIT', 'WIBE_CHAT'),
  ('live_kit', brandSnake),
  ('LIVEKIT', brandUpper),
  ('livekit', brandLower),
];

/// Anything matching this after rebranding is reported as a leftover.
final leftover = RegExp(r'live[\s_-]?kit', caseSensitive: false);

// ---------------------------------------------------------------------------

void main(List<String> args) {
  if (!File('pubspec.yaml').existsSync() || !Directory('tool').existsSync()) {
    stderr.writeln('Run this from the repository root.');
    exit(64);
  }

  final tracked = _git(['ls-files', '-z']).split('\x00').where((p) => p.isNotEmpty).toList();

  final renamed = _renamePaths(tracked);
  final paths = tracked.map((p) => renamed[p] ?? p).toList();

  var changed = 0;
  for (final path in paths) {
    if (_isExcluded(path) || _isSymlink(path)) continue;
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    if (bytes.contains(0)) continue; // binary
    final String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException {
      continue; // not valid UTF-8, treat as binary
    }
    final updated = rebrandText(text, path);
    if (updated != text) {
      file.writeAsStringSync(updated);
      changed++;
    }
  }

  final overlaid = _applyOverlay();

  stdout.writeln(
    'rebrand: renamed ${renamed.length} paths, rewrote $changed files, '
    'overlaid $overlaid files.',
  );

  final leftovers = _findLeftovers(paths);
  if (leftovers.isNotEmpty) {
    stderr.writeln('\nrebrand: LiveKit names left that no rule handles:');
    for (final l in leftovers.take(50)) {
      stderr.writeln('  $l');
    }
    if (leftovers.length > 50) stderr.writeln('  ... and ${leftovers.length - 50} more');
    stderr.writeln('\nAdd a rule or a protected pattern in tool/rebrand.dart.');
    exit(1);
  }
}

String rebrandText(String text, String path) {
  for (final (from, to) in preRules) {
    text = text.replaceAll(from, to);
  }
  for (final entry in fileRules.entries) {
    if (!path.endsWith(entry.key)) continue;
    for (final (from, to) in entry.value) {
      text = text.replaceAllMapped(from, (m) => to.replaceAll(r'$1', m[1]!));
    }
  }

  final masked = <String>[];
  for (final pattern in protected) {
    text = text.replaceAllMapped(pattern, (m) {
      masked.add(m[0]!);
      return '\u0000${masked.length - 1}\u0000';
    });
  }

  text = rebrandName(text);

  return text.replaceAllMapped(RegExp('\u0000(\\d+)\u0000'), (m) => masked[int.parse(m[1]!)]);
}

String rebrandName(String s) {
  for (final (from, to) in rules) {
    s = s.replaceAll(from, to);
  }
  return s;
}

bool _isExcluded(String path) => excluded.any((e) => e.endsWith('/') ? path.startsWith(e) : path == e);

bool _isSymlink(String path) => FileSystemEntity.isLinkSync(path);

/// Renames tracked paths, recreating symlinks with rebranded targets.
/// Returns old path -> new path for everything that moved.
Map<String, String> _renamePaths(List<String> tracked) {
  final renamed = <String, String>{};
  final oldDirs = <String>{};
  for (final path in tracked) {
    if (_isExcluded(path)) continue;
    final isLink = _isSymlink(path);
    if (!isLink && !File(path).existsSync()) continue;
    final target = isLink ? Link(path).targetSync() : null;
    final newPath = rebrandName(path);
    final newTarget = target == null ? null : rebrandName(target);
    if (newPath == path && newTarget == target) continue;

    Directory(File(newPath).parent.path).createSync(recursive: true);
    if (isLink) {
      Link(path).deleteSync();
      Link(newPath).createSync(newTarget!);
    } else {
      File(path).renameSync(newPath);
    }
    if (newPath != path) {
      renamed[path] = newPath;
      oldDirs.add(File(path).parent.path);
    }
  }
  // Remove directories left empty by the moves, deepest first.
  final dirs = oldDirs.expand(_ancestors).toSet().toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final dir in dirs) {
    final d = Directory(dir);
    if (d.existsSync() && d.listSync().isEmpty) d.deleteSync();
  }
  return renamed;
}

Iterable<String> _ancestors(String dir) sync* {
  var d = dir;
  while (d != '.' && d.isNotEmpty) {
    yield d;
    final parent = File(d).parent.path;
    if (parent == d) break;
    d = parent;
  }
}

int _applyOverlay() {
  final root = Directory('branding/overlay');
  if (!root.existsSync()) return 0;
  var count = 0;
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = entity.path.substring(root.path.length + 1);
    if (relative == '.gitkeep') continue;
    final dest = File(relative);
    dest.parent.createSync(recursive: true);
    entity.copySync(dest.path);
    count++;
  }
  return count;
}

List<String> _findLeftovers(List<String> paths) {
  final found = <String>[];
  for (final path in paths) {
    if (_isExcluded(path)) continue;
    if (leftover.hasMatch(_maskProtected(path))) found.add('$path (file name)');
    if (_isSymlink(path)) continue;
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    if (bytes.contains(0)) continue;
    final String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException {
      continue;
    }
    final lines = _maskProtected(text).split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (leftover.hasMatch(lines[i])) found.add('$path:${i + 1}: ${lines[i].trim()}');
    }
  }
  return found;
}

String _maskProtected(String text) {
  for (final pattern in protected) {
    text = text.replaceAll(pattern, '');
  }
  return text;
}

String _git(List<String> args) {
  final result = Process.runSync('git', args);
  if (result.exitCode != 0) {
    stderr.writeln('git ${args.join(' ')} failed:\n${result.stderr}');
    exit(1);
  }
  return result.stdout as String;
}
