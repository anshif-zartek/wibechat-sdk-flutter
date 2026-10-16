// Copyright 2024 LiveKit, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

@Timeout(Duration(seconds: 5))
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:wibechat_client/src/utils.dart' show splitUtf8;

void main() {
  group('splitUtf8 tests', () {
    test('handles a string with mixed single and multi-byte utf8 characters', () {
      expect(splitUtf8('a😊b', 4), [
        utf8.encode('a'),
        utf8.encode('😊'),
        utf8.encode('b'),
      ]);
    });
    test('splits a string into chunks of the given sizer', () {
      expect(splitUtf8('hello world', 5), [
        utf8.encode('hello'),
        utf8.encode(' worl'),
        utf8.encode('d'),
      ]);
    });

    test('splits a string with special characters into chunks of the given size', () {
      expect(splitUtf8('héllo wörld', 5), [
        utf8.encode('héll'),
        utf8.encode('o wö'),
        utf8.encode('rld'),
      ]);
    });

    test('splits a string with multi-byte utf8 characters correctly', () {
      expect(splitUtf8('こんにちは世界', 5), [
        utf8.encode('こ'),
        utf8.encode('ん'),
        utf8.encode('に'),
        utf8.encode('ち'),
        utf8.encode('は'),
        utf8.encode('世'),
        utf8.encode('界'),
      ]);
    });

    test('handles a string with a single multi-byte utf8 character', () {
      expect(splitUtf8('😊', 5), [utf8.encode('😊')]);
    });

    test('handles an empty string', () {
      expect(splitUtf8('', 5), []);
    });
  });
}
