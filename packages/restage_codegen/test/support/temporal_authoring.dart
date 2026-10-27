import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart' as i;

import '../shared_resolvers.dart';
import 'intl_format_authoring.dart';

/// Native Dart oracles paired with their original ordinary authoring syntax.
List<(String, Object? Function())> temporalCases() => [
      (
        "'\${DateTime.utc(2024, 2, 29, 17, 23, 41, 123, 456).microsecond}'",
        () => '${DateTime.utc(2024, 2, 29, 17, 23, 41, 123, 456).microsecond}'
      ),
      (
        "'\${DateTime.utc(2024).toLocal().toUtc().isUtc}'",
        () => '${DateTime.utc(2024).toLocal().toUtc().isUtc}'
      ),
      (
        "'\${DateTime.utc(2024).difference(DateTime.utc(2024, 1, 1, 0, 0, 0, 0, 1)).inMicroseconds}'",
        () =>
            '${DateTime.utc(2024).difference(DateTime.utc(2024, 1, 1, 0, 0, 0, 0, 1)).inMicroseconds}'
      ),
      (
        "'\${Duration(microseconds: -1001).inMilliseconds}'",
        () => '${const Duration(microseconds: -1001).inMilliseconds}'
      ),
      (
        "'\${DateTime.utc(2024).add(Duration(microseconds: 1001)).microsecond}'",
        () =>
            '${DateTime.utc(2024).add(const Duration(microseconds: 1001)).microsecond}'
      ),
      (
        "'\${DateTime.utc(2024).subtract(Duration(microseconds: 1)).year}'",
        () =>
            '${DateTime.utc(2024).subtract(const Duration(microseconds: 1)).year}'
      ),
      (
        "'\${DateTime.utc(2024).compareTo(DateTime.utc(2025))}'",
        () => '${DateTime.utc(2024).compareTo(DateTime.utc(2025))}'
      ),
      (
        "'\${DateTime.utc(2024).isBefore(DateTime.utc(2025))}'",
        () => '${DateTime.utc(2024).isBefore(DateTime.utc(2025))}'
      ),
      (
        "'\${DateTime.utc(2024).isAfter(DateTime.utc(2025))}'",
        () => '${DateTime.utc(2024).isAfter(DateTime.utc(2025))}'
      ),
      (
        "'\${DateTime.utc(2024).isAtSameMomentAs(DateTime.utc(2024).toLocal())}'",
        () =>
            '${DateTime.utc(2024).isAtSameMomentAs(DateTime.utc(2024).toLocal())}'
      ),
      (
        "'\${DateTime.utc(2024) == DateTime.utc(2024)}'",
        () => '${DateTime.utc(2024) == DateTime.utc(2024)}'
      ),
      (
        "'\${DateTime.utc(2024) != DateTime.utc(2024).toLocal()}'",
        () => '${DateTime.utc(2024) != DateTime.utc(2024).toLocal()}'
      ),
      (
        "'\${DateTime.utc(2024).timeZoneOffset.inSeconds}'",
        () => '${DateTime.utc(2024).timeZoneOffset.inSeconds}'
      ),
      (
        "'\${DateTime(2024, 2, 29).timeZoneName}'",
        () => '${DateTime(2024, 2, 29).timeZoneName}'
      ),
    ];

/// A native formatting oracle for an injected declared read.
String formattedClock(DateTime now) => i.DateFormat.Hms('en_US').format(now);

const clockFormatSource = "i.DateFormat.Hms('en_US').format(DateTime.now())";
const countdownSource =
    "'\${DateTime.utc(2030).difference(DateTime.now()).inSeconds}'";
const reusedClockBuilderSource =
    "LayoutBuilder(builder: (context, constraints) { final now = DateTime.now(); return Text('\${now.microsecondsSinceEpoch}|\${now.microsecondsSinceEpoch}'); })";

const itemClockBuilderSource =
    "GridView.builder(itemCount: 3, gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 1), itemBuilder: (context, index) { final now = DateTime.now(); return Text('\${index}:\${now.microsecondsSinceEpoch}|\${now.microsecondsSinceEpoch}'); })";

Future<String> compileTemporalFixture() async {
  final sources = [
    ...temporalCases().map((c) => c.$1),
    clockFormatSource,
    countdownSource
  ];
  final programs = await authoredFormattingPrograms(sources);
  final builder = await translateFormatting(reusedClockBuilderSource);
  final issues = builder.issues.where((i) => !i.code.isBuildNotice);
  if (issues.isNotEmpty || builder.hoisted.isNotEmpty)
    throw StateError('Clock builder did not lower directly: $issues');
  final grid = await translateFormatting(itemClockBuilderSource);
  final gridIssues = grid.issues.where((i) => !i.code.isBuildNotice);
  if (gridIssues.isNotEmpty || grid.hoisted.isNotEmpty)
    throw StateError('Item clock builder did not lower directly: $gridIssues');
  return '${const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'cases': [
          for (var index = 0; index < sources.length; index++)
            {'source': sources[index], 'program': programs[index].toJson()}
        ],
        'builder': builder.dsl,
        'grid': grid.dsl,
      })}\n';
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1)
    throw ArgumentError('Expected temporal fixture output path');
  try {
    File(arguments.single).writeAsStringSync(await compileTemporalFixture());
    stdout.writeln(
        'Wrote temporal authored-program fixture: ${arguments.single}');
  } finally {
    sharedResolvers.reset();
  }
}
