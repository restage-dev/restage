import 'page_view_support.dart';

/// Writes one experiment's results.
void renderExperimentResultsPage(
  StringSink out,
  Map<String, Object?> document,
  int floor,
) {
  final sessions = figureAt(document, ['sessions', 'value']);
  out
    ..writeln(
      'Status: ${lifecycleLabel(figureAt(document, ['detail', 'lifecycle']))}',
    )
    ..writeln(
      'Views: ${countFigure(sessions, ['counts', 'rootPresentations'], floor)}',
    )
    ..writeln(
      'App sessions: ${countFigure(sessions, ['counts', 'distinctSessions'], floor)}',
    );
  for (final sentence in [
    figureAt(document, ['summary', 'headline']),
    ...figureList(document, ['summary', 'detail']),
  ]) {
    if (sentenceText(sentence) case final text?) out.writeln(text);
  }
  for (final variant in figureList(document, ['changes'])) {
    out.writeln(plainFigure(variant, ['label']));
    final changes = figureList(variant, ['changes']);
    switch (figureAt(variant, ['status'])) {
      case 'sameVersion':
        out.writeln(
          '  Same version as ${plainFigure(variant, ['referenceLabel'])}.',
        );
      case 'notComparable':
        out.writeln('  Changes not available for this version.');
      default:
        if (changes.isEmpty) out.writeln('  No differences found.');
    }
    for (final change in changes) {
      if (sentenceText(figureAt(change, ['line'])) case final text?) {
        out.writeln('  $text');
      }
      if (sentenceText(figureAt(change, ['measurement', 'line']))
          case final text?) {
        out.writeln('    $text');
      }
    }
    final more = figureAt(variant, ['moreCount']);
    if (more is int && more > 0) out.writeln('  $more more changes.');
  }
  final refusals = figureAt(document, ['libraryRefusals']);
  for (final arm in figureList(refusals, ['arms'])) {
    for (final build in figureList(arm, ['refusedBuilds'])) {
      out
        ..writeln(
          "${plainFigure(arm, ['label'])} can't show on "
          '${_buildName(build)}.',
        )
        ..writeln('  ${_times(build, floor)} since ${_day(build)}.');
    }
  }
  for (final build in figureList(refusals, ['declinedEnrollments'])) {
    final name = _buildName(build);
    out
      ..writeln(
        "${name[0].toUpperCase()}${name.substring(1)} can't show every "
        'variant.',
      )
      ..writeln('  ${_times(build, floor, suffix: 'not enrolled')}.');
  }
}

String _buildName(Object? build) => figureAt(build, ['appBuild']) == 0
    ? 'an unreported build'
    : 'build ${plainFigure(build, ['appBuild'])}';

String _times(Object? build, int floor, {String? suffix}) {
  final count = figureAt(build, ['count']);
  final noun = count == 1 ? 'time' : 'times';
  return '${countFigure(build, ['count'], floor)} $noun${suffix == null ? '' : ' $suffix'}';
}

String _day(Object? build) => switch (figureAt(build, ['firstSeenMicros'])) {
  final int micros => DateTime.fromMicrosecondsSinceEpoch(
    micros,
    isUtc: true,
  ).toIso8601String().substring(0, 10),
  _ => kFigureUnavailable,
};
