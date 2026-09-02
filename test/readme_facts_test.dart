import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The facts README.md states about itself.
///
/// A README is the one file nobody re-reads, and the numbers in it — version,
/// test count — go stale silently. `tool/check_readme.dart` derives them and
/// runs as part of every release; this asserts the same thing from inside the
/// suite, so drift fails here too rather than waiting for a release.
void main() {
  final String readme = File('README.md').readAsStringSync();

  String? capture(RegExp pattern) =>
      pattern.firstMatch(readme)?.group(1);

  group('README facts', () {
    test('states the version in pubspec.yaml', () {
      final String? declared = RegExp(
        r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
        multiLine: true,
      ).firstMatch(File('pubspec.yaml').readAsStringSync())?.group(1);

      expect(declared, isNotNull);
      expect(
        capture(RegExp(r'\*\*Current version: v([0-9]+\.[0-9]+\.[0-9]+)\*\*')),
        declared,
        reason: 'run: dart tool/check_readme.dart --write',
      );
    });

    test('the changelog documents that version', () {
      // A version bump without a changelog entry produces a release whose notes
      // read "No changelog entry for vX.Y.Z."
      final String? latest = RegExp(
        r'^## v([0-9]+\.[0-9]+\.[0-9]+)',
        multiLine: true,
      ).firstMatch(File('CHANGELOG.md').readAsStringSync())?.group(1);

      expect(
        capture(RegExp(r'\*\*Current version: v([0-9]+\.[0-9]+\.[0-9]+)\*\*')),
        latest,
      );
    });

    test('every stated test count agrees with the suite', () {
      final RegExp declaration = RegExp(
        r'^\s*test(Widgets)?\s*\(',
        multiLine: true,
      );
      int counted = 0;
      for (final FileSystemEntity entity
          in Directory('test').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('_test.dart')) continue;
        counted += declaration.allMatches(entity.readAsStringSync()).length;
      }

      // Three places say it, and they have disagreed with each other before.
      final List<String?> stated = <String?>[
        capture(RegExp(r'`minSdk 24`\) · ([0-9]+) tests')),
        capture(RegExp(r'flutter test\s+# ([0-9]+) unit tests')),
        capture(RegExp(r'^([0-9]+) unit tests, no device', multiLine: true)),
      ];

      for (final String? value in stated) {
        expect(value, isNotNull, reason: 'a test-count line went missing');
        expect(
          int.parse(value!),
          counted,
          reason: 'run: dart tool/check_readme.dart --write',
        );
      }
    });

    test('the checker it points at exists', () {
      // The README tells a reader to run this; a broken instruction is worse
      // than no instruction.
      expect(File('tool/check_readme.dart').existsSync(), isTrue);
      expect(readme, contains('tool/check_readme.dart'));
    });
  });
}
