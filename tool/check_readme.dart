// Keeps the facts stated in README.md matching the repository.
//
// Prose goes stale quietly; numbers go stale loudly and embarrassingly. A
// README claiming "268 tests" next to a suite of 275, or a version two releases
// behind, is the kind of thing nobody notices until a stranger reads it. So the
// handful of facts that *can* be derived are derived, and the rest is left to
// whoever writes the words.
//
//   dart tool/check_readme.dart          verify, exit 1 on drift
//   dart tool/check_readme.dart --write  fix in place
//
// Runs as part of every release, before the tag is cut.

import 'dart:io';

void main(List<String> args) {
  final bool write = args.contains('--write');

  final File readme = File('README.md');
  if (!readme.existsSync()) {
    stderr.writeln('README.md not found — run this from the repository root.');
    exit(2);
  }

  final _Facts facts = _Facts.fromRepository();
  String text = readme.readAsStringSync();
  final List<String> drifted = <String>[];

  for (final _Rule rule in _rules(facts)) {
    final Match? match = rule.pattern.firstMatch(text);
    if (match == null) {
      // A rule whose anchor has been edited away is itself a failure: silently
      // checking nothing is worse than checking the wrong thing.
      drifted.add('${rule.name}: nothing in README.md matches ${rule.pattern.pattern}');
      continue;
    }

    final String found = match.group(1)!;
    if (found == rule.expected) continue;

    drifted.add('${rule.name}: README says "$found", repository says "${rule.expected}"');
    if (write) {
      text = text.replaceAllMapped(
        rule.pattern,
        (Match m) => m.group(0)!.replaceFirst(m.group(1)!, rule.expected),
      );
    }
  }

  if (drifted.isEmpty) {
    stdout.writeln('README.md is current (v${facts.version}, ${facts.tests} tests).');
    return;
  }

  if (write) {
    readme.writeAsStringSync(text);
    stdout.writeln('Updated README.md:');
    for (final String line in drifted) {
      stdout.writeln('  $line');
    }
    return;
  }

  stderr.writeln('README.md has drifted from the repository:');
  for (final String line in drifted) {
    stderr.writeln('  $line');
  }
  stderr.writeln('\nRun: dart tool/check_readme.dart --write');
  exit(1);
}

/// What the repository actually says about itself.
class _Facts {
  const _Facts({required this.version, required this.tests});

  final String version;
  final int tests;

  static _Facts fromRepository() => _Facts(
    version: _versionFromPubspec(),
    tests: _countTests(),
  );

  static String _versionFromPubspec() {
    final RegExp line = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)', multiLine: true);
    final Match? match = line.firstMatch(File('pubspec.yaml').readAsStringSync());
    if (match == null) {
      stderr.writeln('No version: line in pubspec.yaml.');
      exit(2);
    }
    return match.group(1)!;
  }

  /// Counts `test(...)` declarations across the suite.
  ///
  /// Counted by reading the files rather than by running them: this has to work
  /// in a check that takes a second, and a number that only appears after a full
  /// `flutter test` run would simply never be checked. It is exact as long as
  /// nobody generates tests in a loop — and if anyone does, the count drifts
  /// visibly rather than silently.
  static int _countTests() {
    final RegExp declaration = RegExp(r"^\s*test(Widgets)?\s*\(", multiLine: true);
    int total = 0;

    final Directory dir = Directory('test');
    if (!dir.existsSync()) return 0;

    for (final FileSystemEntity entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('_test.dart')) continue;
      total += declaration.allMatches(entity.readAsStringSync()).length;
    }
    return total;
  }
}

class _Rule {
  const _Rule({
    required this.name,
    required this.pattern,
    required this.expected,
  });

  final String name;

  /// Must capture exactly the value to compare, in group 1.
  final RegExp pattern;
  final String expected;
}

List<_Rule> _rules(_Facts facts) => <_Rule>[
  _Rule(
    name: 'Current version',
    pattern: RegExp(r'\*\*Current version: v([0-9]+\.[0-9]+\.[0-9]+)\*\*'),
    expected: facts.version,
  ),
  _Rule(
    name: 'Test count (header)',
    pattern: RegExp(r'Android 7\.0\+ \(`minSdk 24`\) · ([0-9]+) tests'),
    expected: '${facts.tests}',
  ),
  _Rule(
    name: 'Test count (getting started)',
    pattern: RegExp(r'flutter test\s+# ([0-9]+) unit tests'),
    expected: '${facts.tests}',
  ),
  _Rule(
    name: 'Test count (testing section)',
    pattern: RegExp(r'^([0-9]+) unit tests, no device', multiLine: true),
    expected: '${facts.tests}',
  ),
  _Rule(
    name: 'Latest changelog entry',
    pattern: RegExp(r'\*\*Current version: v([0-9]+\.[0-9]+\.[0-9]+)\*\*'),
    expected: _latestChangelogVersion(),
  ),
];

/// The newest version the changelog documents.
///
/// Compared against the same README line as the pubspec version, so a release
/// that bumps `pubspec.yaml` without writing a changelog entry is caught here
/// rather than by whoever opens the release page.
String _latestChangelogVersion() {
  final File changelog = File('CHANGELOG.md');
  if (!changelog.existsSync()) return '';
  final RegExp heading = RegExp(r'^## v([0-9]+\.[0-9]+\.[0-9]+)', multiLine: true);
  return heading.firstMatch(changelog.readAsStringSync())?.group(1) ?? '';
}
