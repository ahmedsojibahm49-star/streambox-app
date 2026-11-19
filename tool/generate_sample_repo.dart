import 'dart:io';

import 'package:streambox/data/sample_provider.dart';

/// Regenerates the sample repo JSON files from lib/data/sample_provider.dart
/// (the single source of truth — never edit the JSON files by hand).
///
///   dart tool/generate_sample_repo.dart
///
/// Writes:
///   - assets/sample-repo.json  (bundled; "Load example" in AddRepoScreen)
///   - sample-repo.json         (project root; for hosting / sharing)
void main() {
  final json = '$sampleRepoJsonString\n';
  for (final path in ['assets/sample-repo.json', 'sample-repo.json']) {
    File(path).writeAsStringSync(json);
    stdout.writeln('wrote $path (${json.length} bytes)');
  }
}
