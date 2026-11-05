import 'dart:convert';

import 'package:restage_cli/src/api/typed_error_models.dart' show FitReason;
import 'package:restage_cli/src/api/typed_error_renderer.dart'
    show fitReasonSentence;
import 'package:restage_shared/restage_shared.dart'
    show SurfaceFitFailureCodeV1, SurfaceFitFailureV1;

/// Whether a push reports this placement: the surface fits it, or the
/// placement shows it by default or through its delivery rules.
bool fitConcernsPushedSurface(List<int> verdictBytes) {
  try {
    final decoded = jsonDecode(utf8.decode(verdictBytes));
    return decoded is Map<String, Object?> &&
        (decoded['accepted'] == true || decoded['showsPublication'] == true);
  } on FormatException {
    return true;
  }
}

/// One placement's fit verdict in plain words: the verdict, then each
/// distinct reason it does not fit, worded as the publish confirmation words
/// it.
List<String> describeFitVerdict(List<int> verdictBytes) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(verdictBytes));
  } on FormatException {
    return const ['could not be read'];
  }
  if (decoded is! Map<String, Object?>) return const ['could not be read'];
  if (decoded['accepted'] == true) return const ['fits'];
  final failures = [
    for (final failure in decoded['failures'] as List<Object?>? ?? const [])
      if (failure is Map<String, Object?>) failure,
  ];
  final census = failures.where((f) => f['path'] == r'$.reportingCensus');
  if (census.isNotEmpty) {
    final days = switch (census.first['required']) {
      final String text => RegExp(r'(\d+) days').firstMatch(text)?.group(1),
      _ => null,
    };
    return [
      'not checked yet',
      'No app build has shown this placement '
          '${days == null ? 'recently' : 'in the last $days days'}. Try '
          'opening it in an app build, then pushing again.',
    ];
  }
  return [
    'does not fit',
    ...{
      for (final failure in failures)
        _requirementSentence(failure) ??
            fitReasonSentence(
              fitReasonOfFailure(failure),
              build: 'an installed build',
            ),
    },
  ];
}

/// [failure], a fit failure as JSON, as the reason a publish confirmation
/// words.
FitReason fitReasonOfFailure(Map<String, Object?> failure) {
  final code = SurfaceFitFailureCodeV1.values.asNameMap()[failure['code']];
  final path = failure['path'] is String ? failure['path']! as String : '';
  final required = failure['required'];
  final available = failure['available'];
  SurfaceFitFailureV1? parsed;
  try {
    if (code != null) {
      parsed = SurfaceFitFailureV1(
        code: code,
        path: path,
        required: required,
        available: available,
      );
    }
  } on Object {
    parsed = null;
  }
  final when = switch (available) {
    {'when': [final Map<String, Object?> first, ...]} => first,
    _ => null,
  };
  String? text(Object? from, String key) => switch (from) {
    final Map<String, Object?> map => switch (map[key]) {
      final String value when value.isNotEmpty => value,
      _ => null,
    },
    _ => null,
  };
  return (
    code: '${failure['code']}',
    token: parsed?.token,
    label: parsed?.label,
    build: text(available, 'build'),
    condition: text(when, 'source'),
    plain: text(when, 'plain'),
    location: text(when, 'location'),
  );
}

// What a placement-level requirement [failure] names, or null when the
// publish confirmation's wording fits it.
String? _requirementSentence(Map<String, Object?> failure) {
  if (failure['code'] != SurfaceFitFailureCodeV1.missingRequirement.name) {
    return null;
  }
  return switch (failure['path']) {
    r'$.publication' =>
      "This version can't be shown until it is live with a verified file.",
    r'$.publication.target' =>
      'This version belongs to another app or environment than this '
          'placement.',
    r'$.publication.surface' =>
      'This version belongs to another surface or contract version.',
    r'$.publication.payload' =>
      "Delivery rules can't route to this version because its format "
          "doesn't match the surface's active version.",
    r'$.publication.surfaceType' =>
      'This placement declares another surface type. Try publishing the '
          'version to a placement that shows its type.',
    _ => null,
  };
}

/// A value or, when [island], a widget shown where [build] doesn't make it,
/// and when the build makes it: [condition] at [location].
String outsideLayoutSentence({
  required bool island,
  String? label,
  String? build,
  String? condition,
  String? location,
}) {
  // An island's label is `<widget> in <screen>`.
  final subject = label == null || label.isEmpty
      ? 'something'
      : island
      ? label.split(' in ').first
      : label;
  final (shown, made, makes, show, making) = island
      ? ('is placed', 'create', 'creates', 'placing', 'creating')
      : ('is shown', 'compute', 'computes', 'showing', 'computing');
  return [
    "`$subject` $shown where ${build == null ? 'the build' : '`$build`'} "
        "doesn't $made it.",
    if (condition != null && location != null)
      'The build $makes it only when `$condition` ($location). Try $show it '
          'only in that case, or $making it before that `if`.',
  ].join(' ');
}
