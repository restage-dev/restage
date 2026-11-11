import 'dart:io';

import 'package:build_runner/src/build/resolver/sdk_summary.dart';

/// Writes the analyzer's SDK summary cache under `.dart_tool/build_resolvers`.
///
/// Run from the package root before a concurrent `dart test`: the cache's
/// version file is not written atomically, so test isolates that build it at
/// the same time can read it empty.
Future<void> main() async {
  stdout.writeln(await defaultSdkSummaryGenerator());
}
