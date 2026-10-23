import 'dart:convert';

import 'package:restage_shared/restage_shared.dart'
    show SurfaceFitFailureCodeV1;

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
/// distinct reason it does not fit.
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
    return ['not checked yet; ${_needs(census.first['required'])}'];
  }
  final missingFields = <String>[];
  final reasons = <String>{};
  for (final failure in failures) {
    final code = SurfaceFitFailureCodeV1.values.asNameMap()[failure['code']];
    final path = failure['path'] is String ? failure['path']! as String : '';
    final appValue = code == SurfaceFitFailureCodeV1.missingHostField
        ? _appValueKey.firstMatch(path)?.group(1)
        : null;
    if (appValue != null) {
      final required = failure['required'];
      final label =
          required is Map<String, Object?> && required['label'] is String
          ? required['label']! as String
          : appValue;
      reasons.add(
        "This version reads '$label', which installed builds don't compute. "
        'It needs an app release',
      );
      continue;
    }
    if (code == SurfaceFitFailureCodeV1.missingHostField) {
      final field = _after(path, r'$.requiredContext.');
      if (field != null && !missingFields.contains(field)) {
        missingFields.add(field);
      }
      continue;
    }
    reasons.add(_reason(code, path, failure['required'], failure['available']));
  }
  return [
    'does not fit',
    if (missingFields.isNotEmpty)
      'the app does not pass ${missingFields.map((f) => '`$f`').join(', ')} '
          'to this placement',
    ...reasons,
  ];
}

/// A value the app's generated widget computes, at the end of a path.
final _appValueKey = RegExp(r'\.(_h[0-9a-f]{10})$');

String _needs(Object? required) => required is String && required.isNotEmpty
    ? 'needs ${required[0].toLowerCase()}${required.substring(1)}'
    : 'something it needs is missing';

String? _after(String path, String prefix) =>
    path.startsWith(prefix) && path.length > prefix.length
    ? path.substring(prefix.length)
    : null;

String _kind(Object? kind) => switch (kind) {
  'flow' => 'a flow',
  'single' => 'one screen',
  _ => 'another kind of content',
};

String _reason(
  SurfaceFitFailureCodeV1? code,
  String path,
  Object? required,
  Object? available,
) {
  // "an event", or "the event `name`" when the path names it.
  String named(String prefix, String noun) {
    final subject = _after(path, prefix);
    if (subject == null) return noun;
    return '${noun.replaceFirst(RegExp('^an? '), 'the ')} `$subject`';
  }

  return switch (code) {
    null => 'an unknown requirement is not met',
    SurfaceFitFailureCodeV1.hostingMismatch => switch ((required, available)) {
      ({'contentKind': final Object? needs}, {'contentKind': final Object? has})
          when needs != has =>
        'the surface is ${_kind(needs)}; this placement shows ${_kind(has)}',
      (_, {'presentation': final String presentation}) =>
        'the surface cannot be shown $presentation',
      _ => 'this placement shows content another way',
    },
    SurfaceFitFailureCodeV1.missingHostField =>
      'the app does not pass ${named(r'$.requiredContext.', 'a value')}',
    SurfaceFitFailureCodeV1.incompatibleHostField =>
      'the app passes ${named(r'$.requiredContext.', 'a value')} '
          'in a different shape',
    SurfaceFitFailureCodeV1.unhandledEvent =>
      'the app does not handle ${named(r'$.emittedEvents.', 'an event')} here',
    SurfaceFitFailureCodeV1.incompatibleEventShape =>
      'the app handles ${named(r'$.emittedEvents.', 'an event')} '
          'with different values',
    SurfaceFitFailureCodeV1.missingInstalledVocabulary =>
      'the app build does not report its widgets',
    SurfaceFitFailureCodeV1.missingWidget =>
      required is String && required.isNotEmpty
          ? 'the app build does not include the widget `$required`'
          : 'the app build lacks a widget the surface uses',
    SurfaceFitFailureCodeV1.missingIcon =>
      'the app build lacks an icon the surface uses',
    SurfaceFitFailureCodeV1.builtInFloor =>
      required is int && available is int
          ? 'the surface needs built-in widgets version $required; '
                'the app build has $available'
          : 'the app build has older built-in widgets',
    SurfaceFitFailureCodeV1.missingLibrary =>
      'the app build does not include the '
          '${named(r'$.capabilities.requiredLibraries.', 'widget library')}',
    SurfaceFitFailureCodeV1.oldLibrary =>
      'the app build has an older '
          '${named(r'$.capabilities.requiredLibraries.', 'widget library')}',
    SurfaceFitFailureCodeV1.brokenLibrary =>
      'the ${named(r'$.capabilities.requiredLibraries.', 'widget library')} '
          'changed in a way the surface cannot use',
    SurfaceFitFailureCodeV1.deliveryModeMismatch =>
      'the app hosts a different kind of flow here',
    SurfaceFitFailureCodeV1.actionMismatch =>
      'the app does not provide '
          '${named(r'$.flowBoundary.actions.', 'an action')} here',
    SurfaceFitFailureCodeV1.seedMismatch =>
      'the app can start the flow with '
          '${named(r'$.flowBoundary.hostSeedableState.', 'a value')} '
          'the surface does not accept',
    SurfaceFitFailureCodeV1.signalMismatch =>
      required is String && required.isNotEmpty
          ? 'the app does not send the signal `$required` here'
          : 'the app does not send a signal the surface waits for',
    SurfaceFitFailureCodeV1.resultMismatch =>
      'the app expects a different result from the flow',
    SurfaceFitFailureCodeV1.outboundMismatch =>
      'the app does not accept '
          '${named(r'$.flowBoundary.outbound.', 'a value')} from the surface',
    SurfaceFitFailureCodeV1.missingRequirement => _needs(required),
    SurfaceFitFailureCodeV1.malformedRequirement =>
      'what this version needs could not be read',
  };
}
