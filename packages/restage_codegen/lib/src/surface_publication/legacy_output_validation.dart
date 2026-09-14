import 'dart:convert';

import 'package:restage_codegen/src/analytics_id_control.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/restage_source_roster.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

/// Recognizes the exact generated document family at a former metadata path.
bool isRecognizedLegacyMetadata(String path, Object? value, String package) {
  if (value is! Map<String, Object?> || value['package'] != package) {
    return false;
  }
  switch (path) {
    case 'lib/generated/restage.analytics-id.metadata.json':
    case kRestageAnalyticsIdControlOutputPath:
      AnalyticsIdControlOutputV1.fromJson(value);
      return true;
    case 'lib/generated/restage.measurement.index.json':
      return _measurementIndex(value);
    case 'assets/restage/source-index.json':
      return _roster(value, 'sources', _source);
    case 'assets/restage/output-roster.json':
      return _roster(value, 'outputs', _ownedOutput);
    default:
      return false;
  }
}

/// Checks the complete locator envelope before obsolete outputs are removed.
bool isRecognizedLegacyOutputIndex(Object? value, String package) =>
    _shape(value, {
      'schemaVersion',
      'package',
      'physicalRoot',
      'publicationManifestPath',
      'generationFingerprint',
      'entries',
    }) &&
    value is Map<String, Object?> &&
    value['schemaVersion'] == 1 &&
    value['package'] == package &&
    _strings(value, [
      'physicalRoot',
      'publicationManifestPath',
      'generationFingerprint',
    ]) &&
    (value['physicalRoot'] == '.' || _packagePath(value['physicalRoot'])) &&
    _packagePath(value['publicationManifestPath']) &&
    _digest(value['generationFingerprint']) &&
    _list(
      value['entries'],
      (entry) =>
          entry is Map<String, Object?> &&
          _shape(entry, {'path', 'entry', 'bundle', 'sha256'}) &&
          _packagePath(entry['path']) &&
          _packagePath(entry['entry']) &&
          _packagePath(entry['bundle']) &&
          (entry['bundle']! as String).endsWith('.rsbundle') &&
          _digest(entry['sha256']),
    );

bool _packagePath(Object? value) =>
    value is String &&
    value.isNotEmpty &&
    !value.contains(r'\') &&
    !value.contains(':') &&
    value
        .split('/')
        .every((part) => part.isNotEmpty && part != '.' && part != '..');

bool _digest(Object? value) =>
    value is String && RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(value);

bool _measurementIndex(Map<String, Object?> value) {
  if (!_shape(value, {'entries', 'kind', 'package', 'schemaVersion'}) ||
      value['kind'] != 'restageMeasurementPublicationIndex' ||
      value['schemaVersion'] != 1) {
    return false;
  }
  return _list(value['entries'], (entry) {
    if (entry is! Map<String, Object?> ||
        !_shape(entry, {
          'draftBase64',
          'draftDigest',
          'routePlanDigest',
          'selector',
          'surfaceId',
        }) ||
        !_strings(entry, [
          'draftBase64',
          'draftDigest',
          'routePlanDigest',
          'surfaceId',
        ])) {
      return false;
    }
    MeasurementPublicationSelectorV1.fromJson(entry['selector']);
    final encoded = entry['draftBase64'];
    if (encoded is! String) {
      return false;
    }
    final bytes = base64Url.decode(base64Url.normalize(encoded));
    if (base64UrlEncode(bytes).replaceAll('=', '') != encoded) return false;
    final draft = MeasurementPublicationDraftV1.fromCanonicalBytes(bytes);
    return entry['draftDigest'] == draft.canonicalDigest.hex &&
        entry['routePlanDigest'] == draft.routeDraftClosureDigest.hex &&
        entry['surfaceId'] == draft.surfaceId.value;
  });
}

bool _roster(
  Map<String, Object?> value,
  String field,
  bool Function(Object?) validEntry,
) {
  final valid = value['valid'];
  return valid is bool &&
      value['schemaVersion'] == 1 &&
      _shape(value, {
        'schemaVersion',
        'package',
        'valid',
        field,
        if (!valid) 'issues',
      }) &&
      (valid ||
          _list(
            value['issues'],
            (issue) =>
                issue is Map<String, Object?> &&
                _shape(issue, {'code', 'message', 'location'}) &&
                _strings(issue, ['code', 'message', 'location']) &&
                IssueCode.values.any((code) => code.name == issue['code']),
          )) &&
      _list(value[field], validEntry);
}

bool _source(Object? value) =>
    value is Map<String, Object?> &&
    _shape(value, {
      'kind',
      'id',
      'idMode',
      'identity',
      'identityClaims',
      'library',
      'libraryPath',
      'source',
      'version',
      'minClient',
      'authoring',
      'span',
      'outputs',
    }, {
      'surface',
      'deliveryMode',
    }) &&
    _strings(value, ['id', 'identity', 'library', 'libraryPath', 'source']) &&
    RestageRosterSourceKind.values
        .any((kind) => kind.wireName == value['kind']) &&
    {'implicit', 'explicit'}.contains(value['idMode']) &&
    {'canonical', 'legacy'}.contains(value['authoring']) &&
    _positive(value['version']) &&
    _positive(value['minClient']) &&
    (!value.containsKey('surface') ||
        Surface.values
            .any((surface) => surface.wireName == value['surface'])) &&
    (!value.containsKey('deliveryMode') ||
        FlowDeliveryMode.values
            .any((mode) => mode.wireName == value['deliveryMode'])) &&
    _list(value['identityClaims'], _identity) &&
    _span(value['span']) &&
    _list(value['outputs'], _output);

bool _identity(Object? value) =>
    value is Map<String, Object?> &&
    _shape(value, {'namespace', 'key'}) &&
    _strings(value, ['namespace', 'key']);

bool _span(Object? value) =>
    value is Map<String, Object?> &&
    _shape(value, {'path', 'start', 'end'}) &&
    _strings(value, ['path']) &&
    _position(value['start']) &&
    _position(value['end']);

bool _position(Object? value) =>
    value is Map<String, Object?> &&
    _shape(value, {'line', 'column'}) &&
    _positive(value['line']) &&
    _positive(value['column']);

bool _output(Object? value) =>
    value is Map<String, Object?> &&
    _shape(
      value,
      {'path', 'role', 'builder', 'writtenWhen'},
      {'ownershipKey'},
    ) &&
    _strings(value, ['path', 'role', 'builder']) &&
    (!value.containsKey('ownershipKey') || _strings(value, ['ownershipKey'])) &&
    RestageOutputCondition.values
        .any((condition) => condition.wireName == value['writtenWhen']);

bool _ownedOutput(Object? value) =>
    value is Map<String, Object?> &&
    _shape(value, {
      'path',
      'role',
      'builder',
      'writtenWhen',
      'owner',
      'declaration',
      'identities',
      'span',
    }) &&
    _strings(value, ['path', 'role', 'builder', 'owner', 'declaration']) &&
    RestageOutputCondition.values
        .any((condition) => condition.wireName == value['writtenWhen']) &&
    _list(value['identities'], _identity) &&
    _span(value['span']);

bool _shape(
  Object? value,
  Set<String> required, [
  Set<String> optional = const {},
]) =>
    value is Map<String, Object?> &&
    required.every(value.containsKey) &&
    value.keys.every((key) => required.contains(key) || optional.contains(key));

bool _strings(Map<String, Object?> value, List<String> keys) =>
    keys.every((key) {
      final field = value[key];
      return field is String && field.isNotEmpty;
    });

bool _positive(Object? value) => value is int && value > 0;
bool _list(Object? value, bool Function(Object?) predicate) =>
    value is List<Object?> && value.every(predicate);
