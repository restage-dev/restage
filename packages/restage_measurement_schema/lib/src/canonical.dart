import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The only schema version emitted by the initial measurement contract.
const int kMeasurementSchemaVersion = 1;

/// Largest bare JSON integer represented exactly by Dart VM, Wasm, and JS.
const int kMaximumPortableJsonInteger = 9007199254740991;

/// Smallest bare JSON integer represented exactly by Dart VM, Wasm, and JS.
const int kMinimumPortableJsonInteger = -9007199254740991;

/// A malformed or noncanonical measurement representation.
final class CanonicalFormatException implements Exception {
  /// Creates an exception with a public-safe explanation.
  const CanonicalFormatException(this.message);

  /// Why the representation is invalid.
  final String message;

  @override
  String toString() => 'CanonicalFormatException: $message';
}

/// Byte-exact canonical JSON used by all measurement hashes and fixtures.
abstract final class CanonicalJsonCodec {
  /// Encodes [value] using the frozen canonical profile.
  static Uint8List encode(Object? value) =>
      Uint8List.fromList(utf8.encode(_encodeText(value)));

  static String _encodeText(Object? value) {
    final output = StringBuffer();
    _writeValue(output, value);
    return output.toString();
  }

  /// Decodes only representations already in the frozen canonical form.
  ///
  /// Exact re-encoding rejects duplicate keys, alternate escapes, whitespace,
  /// noncanonical ordering, negative zero, and every other equivalent spelling.
  static Object? decode(List<int> bytes) {
    late final String source;
    try {
      source = utf8.decode(bytes, allowMalformed: false);
    } on FormatException catch (error) {
      throw CanonicalFormatException('Invalid UTF-8: ${error.message}');
    }

    late final Object? value;
    try {
      value = jsonDecode(source);
    } on FormatException catch (error) {
      throw CanonicalFormatException('Invalid JSON: ${error.message}');
    }

    final canonicalSource = _encodeText(value);
    if (canonicalSource != source || _hasLeadingUtf8Bom(bytes)) {
      throw const CanonicalFormatException(
        'Input is valid JSON but not the canonical byte representation',
      );
    }
    return value;
  }

  static void _writeValue(StringBuffer output, Object? value) {
    switch (value) {
      case null:
        output.write('null');
      case bool():
        output.write(value ? 'true' : 'false');
      case int():
        if (value < kMinimumPortableJsonInteger ||
            value > kMaximumPortableJsonInteger) {
          throw CanonicalFormatException(
            'Bare JSON integer $value exceeds the portable exact range',
          );
        }
        output.write(value);
      case String():
        _writeString(output, value);
      case List<Object?>():
        output.write('[');
        for (var index = 0; index < value.length; index++) {
          if (index > 0) output.write(',');
          _writeValue(output, value[index]);
        }
        output.write(']');
      case Map<String, Object?>():
        final keys = value.keys.toList()..sort(_compareUtf8);
        output.write('{');
        for (var index = 0; index < keys.length; index++) {
          if (index > 0) output.write(',');
          final key = keys[index];
          _writeString(output, key);
          output.write(':');
          _writeValue(output, value[key]);
        }
        output.write('}');
      default:
        throw CanonicalFormatException(
          'Unsupported canonical JSON value type ${value.runtimeType}',
        );
    }
  }

  static void _writeString(StringBuffer output, String value) {
    _validateWellFormedUtf16(value);
    output.write('"');

    var spanStart = 0;
    for (var index = 0; index < value.length; index++) {
      final unit = value.codeUnitAt(index);
      if (unit >= 0x20 && unit != 0x22 && unit != 0x5C) continue;

      if (spanStart < index) {
        output.write(value.substring(spanStart, index));
      }
      switch (unit) {
        case 0x08:
          output.write(r'\b');
        case 0x09:
          output.write(r'\t');
        case 0x0A:
          output.write(r'\n');
        case 0x0C:
          output.write(r'\f');
        case 0x0D:
          output.write(r'\r');
        case 0x22:
          output.write(r'\"');
        case 0x5C:
          output.write(r'\\');
        default:
          if (unit < 0x20) {
            output
              ..write(r'\u00')
              ..write(unit.toRadixString(16).padLeft(2, '0'));
          }
      }
      spanStart = index + 1;
    }
    if (spanStart == 0) {
      output.write(value);
    } else if (spanStart < value.length) {
      output.write(value.substring(spanStart));
    }
    output.write('"');
  }

  static int _compareUtf8(String left, String right) {
    _validateWellFormedUtf16(left);
    _validateWellFormedUtf16(right);
    final sharedLength =
        left.length < right.length ? left.length : right.length;
    for (var index = 0; index < sharedLength; index++) {
      final leftUnit = left.codeUnitAt(index);
      final rightUnit = right.codeUnitAt(index);
      if (leftUnit == rightUnit) continue;
      return _unicodeScalarAt(left, index, leftUnit) -
          _unicodeScalarAt(right, index, rightUnit);
    }
    return left.length - right.length;
  }

  static int _unicodeScalarAt(String value, int index, int unit) {
    if (!_isHighSurrogate(unit)) return unit;
    return 0x10000 +
        ((unit - 0xD800) << 10) +
        (value.codeUnitAt(index + 1) - 0xDC00);
  }

  static void _validateWellFormedUtf16(String value) {
    for (var index = 0; index < value.length; index++) {
      final unit = value.codeUnitAt(index);
      if (_isHighSurrogate(unit)) {
        if (index + 1 >= value.length ||
            !_isLowSurrogate(value.codeUnitAt(index + 1))) {
          throw const CanonicalFormatException(
            'Strings must not contain unpaired UTF-16 surrogates',
          );
        }
        index++;
      } else if (_isLowSurrogate(unit)) {
        throw const CanonicalFormatException(
          'Strings must not contain unpaired UTF-16 surrogates',
        );
      }
    }
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  static bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  static bool _hasLeadingUtf8Bom(List<int> bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;
}

/// Independently interpreted authorities with distinct hash namespaces.
enum CanonicalHashDomain {
  /// Exact organization/application/environment/runtime target.
  targetCoordinate('target-coordinate'),

  /// One platform admission of a registered inference adapter for a target.
  registeredInferenceAdapterAdmission('registered-inference-adapter-admission'),

  /// Stable surface identity.
  surfaceIdentity('surface-identity'),

  /// One immutable artifact identity.
  artifactIdentity('artifact-identity'),

  /// Exact artifact closure graph.
  artifactGraph('artifact-graph'),

  /// Compiler-emitted node identity token.
  nodeToken('node-token'),

  /// Compiler-maintained source code identity.
  codeIdentity('code-identity'),

  /// One exact point occurrence.
  pointOccurrence('point-occurrence'),

  /// Stable reviewed point lineage.
  pointLineage('point-lineage'),

  /// One lineage transition revision.
  lineageTransition('lineage-transition'),

  /// Manifest emitted for one local artifact.
  localManifest('local-manifest'),

  /// Complete resolved manifest closure.
  completeManifest('complete-manifest'),

  /// Generated typed source reference.
  generatedReference('generated-reference'),

  /// Generated typed presentation reference.
  generatedPresentationReference('generated-presentation-reference'),

  /// Attempted semantic intent binding.
  intentBinding('intent-binding'),

  /// Authoritative realized outcome definition.
  outcomeDefinition('outcome-definition'),

  /// Immutable metric definition revision.
  metricDefinition('metric-definition'),

  /// Immutable metric-to-context binding.
  metricBinding('metric-binding'),

  /// One semantic slot projection.
  slotProjection('slot-projection'),

  /// Complete projection set.
  projectionSet('projection-set'),

  /// Canonical semantic observation.
  observation('observation'),

  /// Descriptive metric result.
  metricResult('metric-result'),

  /// Immutable metric summary-estimator policy revision.
  summaryPolicy('summary-policy'),

  /// Registered inference design description.
  inferenceDesign('inference-design'),

  /// Final inferential result and decision authority.
  experimentInference('experiment-inference'),

  /// Randomized-unit policy revision.
  randomizedUnitPolicy('randomized-unit-policy'),

  /// Governed subject policy revision.
  subjectPolicy('subject-policy'),

  /// Immutable assignment request-context schema revision.
  assignmentContextSchema('assignment-context-schema'),

  /// Immutable assignment audience-policy revision.
  assignmentAudiencePolicy('assignment-audience-policy'),

  /// Immutable assignment eligibility-policy revision.
  assignmentEligibilityPolicy('assignment-eligibility-policy'),

  /// One installed-build assignment-context capability descriptor.
  assignmentContextCapability('assignment-context-capability'),

  /// One exact admitted-build assignment-context capability closure.
  assignmentContextCapabilityClosure('assignment-context-capability-closure'),

  /// One governed-subject link challenge.
  measurementLinkChallenge('measurement-link-challenge'),

  /// One request to issue a direct governed-subject link challenge.
  measurementLinkChallengeRequest('measurement-link-challenge-request'),

  /// One direct governed-subject link request.
  measurementLinkRequest('measurement-link-request'),

  /// One explicit governed-subject operation request.
  measurementSubjectOperationRequest('measurement-subject-operation-request'),

  /// One domain-independent governed privacy coordinator request.
  restagePrivacyRequest('restage-privacy-request'),

  /// Immutable experiment publication revision.
  experimentPublication('experiment-publication'),

  /// Experiment layer revision.
  experimentLayer('experiment-layer'),

  /// Joint allocation revision.
  jointAllocation('joint-allocation'),

  /// Proof-independent authority subject for one compatibility proof.
  compatibilityProofAuthoritySubject('compatibility-proof-authority-subject'),

  /// One generated compatibility proof revision.
  compatibilityProof('compatibility-proof'),

  /// One complete route-neutral experiment activation command.
  experimentActivationCommand('experiment-activation-command'),

  /// One immutable experiment-authoring draft revision.
  experimentAuthoringDraft('experiment-authoring-draft'),

  /// Exact dependency closure retained by an experiment-authoring draft.
  experimentAuthoringDraftDependencyClosure(
    'experiment-authoring-draft-dependency-closure',
  ),

  /// Exact fixed-horizon inputs retained before design registration.
  nArmRatePlanningIntent('n-arm-rate-planning-intent'),

  /// Exact allocation weights retained before design registration.
  nArmRatePlanningAllocationAuthority(
    'n-arm-rate-planning-allocation-authority',
  ),

  /// One complete experiment activation head-state CAS preimage.
  experimentActivationHeadState('experiment-activation-head-state'),

  /// Exact allocation partition-shape authority.
  allocationPartitionShape('allocation-partition-shape'),

  /// One versioned Measurement-to-publication binding.
  measurementPublicationBinding('measurement-publication-binding'),

  /// Fingerprint of an opaque runtime event-route carrier.
  ///
  /// This is deliberately distinct from point occurrence identity. The raw
  /// carrier is never canonicalized into a Measurement publication binding.
  measurementPublicationRouteCarrier('measurement-publication-route-carrier'),

  /// Target-neutral compiler publication draft.
  measurementPublicationDraft('measurement-publication-draft'),

  /// Target-neutral route-draft closure used to derive local route tokens.
  measurementPublicationRouteDraftClosure(
    'measurement-publication-route-draft-closure',
  ),

  /// Compiler-derived local portion of one full route carrier.
  measurementPublicationRouteLocalToken(
    'measurement-publication-route-local-token',
  ),

  /// Candidate digest over one opaque publication closure and one draft.
  measurementPublicationCandidate('measurement-publication-candidate'),

  /// Exact selected opaque manifest bytes within a publication candidate.
  measurementPublicationCandidateManifest(
    'measurement-publication-candidate-manifest',
  ),

  /// Exact assembled opaque upload bytes within a publication candidate.
  measurementPublicationCandidateUpload(
    'measurement-publication-candidate-upload',
  ),

  /// Canonical candidate proof envelope.
  measurementPublicationCandidateProof(
    'measurement-publication-candidate-proof',
  ),

  /// Authority-supplied prior-active lineage endpoint ledger.
  measurementPublicationPriorActiveLedger(
    'measurement-publication-prior-active-ledger',
  ),

  /// Exact immutable bundled binding registry for one resolved target.
  measurementPublicationBundledRegistry(
    'measurement-publication-bundled-registry',
  ),

  /// Complete typed exact-publication-context closure for one canonical
  /// authoring revision and its sealed dependencies.
  canonicalPublicationContextClosure('canonical-publication-context-closure'),

  /// One durable projection of a proven experiment delivery claim.
  experimentServingRecord('experiment-serving-record');

  const CanonicalHashDomain(this.wireName);

  /// Stable domain name in the hash preimage prefix.
  final String wireName;

  /// `restage.measurement/v1/<domain>\x00` encoded as UTF-8.
  Uint8List get prefixBytes =>
      Uint8List.fromList(utf8.encode('restage.measurement/v1/$wireName\u0000'));
}

/// A lowercase SHA-256 digest.
final class CanonicalDigest {
  /// Creates a validated digest from lowercase hexadecimal [hex].
  CanonicalDigest(this.hex) {
    if (!_digestPattern.hasMatch(hex)) {
      throw ArgumentError.value(hex, 'hex', 'Expected 64 lowercase hex digits');
    }
  }

  static final RegExp _digestPattern = RegExp(r'^[0-9a-f]{64}$');

  /// Lowercase hexadecimal SHA-256 bytes.
  final String hex;

  @override
  bool operator ==(Object other) =>
      other is CanonicalDigest && other.hex == hex;

  @override
  int get hashCode => hex.hashCode;

  @override
  String toString() => hex;
}

/// Hashes already-canonical [bytes] under a frozen [domain].
CanonicalDigest canonicalSha256(CanonicalHashDomain domain, List<int> bytes) {
  if (bytes is! Uint8List) {
    final digest = sha256.convert(<int>[...domain.prefixBytes, ...bytes]);
    return CanonicalDigest(digest.toString());
  }
  final output = _CanonicalDigestSink();
  final sink = sha256.startChunkedConversion(output);
  sink
    ..add(domain.prefixBytes)
    ..add(bytes)
    ..close();
  return CanonicalDigest(output.value.toString());
}

/// Receives the one digest emitted by a chunked [Hash] conversion.
final class _CanonicalDigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get value {
    final digest = _digest;
    if (digest == null) {
      throw StateError('Hash conversion closed without a digest');
    }
    return digest;
  }

  @override
  void add(Digest value) {
    if (_digest != null) {
      throw StateError('Hash conversion emitted more than one digest');
    }
    _digest = value;
  }

  @override
  void close() {
    if (_digest == null) {
      throw StateError('Hash conversion closed without a digest');
    }
  }
}

/// An immutable value with deterministic canonical bytes and deep equality.
abstract base class CanonicalValue {
  /// Creates an immutable canonical value.
  const CanonicalValue();

  /// Closed JSON representation consumed by [CanonicalJsonCodec].
  Map<String, Object?> toJson();

  /// Frozen canonical bytes for this value.
  Uint8List get canonicalBytes => CanonicalJsonCodec.encode(toJson());

  @override
  bool operator ==(Object other) =>
      runtimeType == other.runtimeType &&
      other is CanonicalValue &&
      _bytesEqual(canonicalBytes, other.canonicalBytes);

  @override
  int get hashCode => Object.hash(runtimeType, utf8.decode(canonicalBytes));
}

/// Declares a document that owns its whole content and hands out nothing a
/// caller can change, so what it encodes to is fixed at construction.
///
/// Only such a document may hold its digest. A document that keeps or exposes
/// a nested map or list must not declare this: its bytes can change under a
/// held digest.
abstract interface class ImmutableCanonicalDocument {}

final _canonicalDigests = Expando<CanonicalDigest>('canonicalDigest');

/// A top-level hash authority with one fixed domain.
abstract base class CanonicalDocument extends CanonicalValue {
  /// Creates an immutable canonical document.
  const CanonicalDocument();

  /// The only domain in which this authority may be hashed.
  CanonicalHashDomain get hashDomain;

  /// Domain-separated digest of [canonicalBytes].
  ///
  /// Recomputed on every read unless the document declares
  /// [ImmutableCanonicalDocument], in which case it is computed once and held
  /// for as long as the document lives, at about 64 bytes. The canonical
  /// bytes are never held.
  CanonicalDigest get canonicalDigest {
    if (this is! ImmutableCanonicalDocument) {
      return canonicalSha256(hashDomain, canonicalBytes);
    }
    return _canonicalDigests[this] ??= canonicalSha256(
      hashDomain,
      canonicalBytes,
    );
  }
}

/// Strict reader used by closed contract decoders.
final class CanonicalObjectReader {
  /// Validates object keys before any field is read.
  CanonicalObjectReader(
    this._values, {
    required Set<String> allowedKeys,
    required Set<String> requiredKeys,
    required this.path,
  }) {
    final unknown = _values.keys.toSet().difference(allowedKeys);
    if (unknown.isNotEmpty) {
      throw CanonicalFormatException(
        '$path contains unknown keys: ${_sorted(unknown).join(', ')}',
      );
    }
    final missing = requiredKeys.difference(_values.keys.toSet());
    if (missing.isNotEmpty) {
      throw CanonicalFormatException(
        '$path is missing keys: ${_sorted(missing).join(', ')}',
      );
    }
  }

  final Map<String, Object?> _values;

  /// Human-readable object path for errors.
  final String path;

  /// Reads a required string.
  String string(String key) {
    final value = _values[key];
    if (value is! String) {
      throw CanonicalFormatException('$path.$key must be a string');
    }
    return value;
  }

  /// Reads an optional string.
  String? optionalString(String key) {
    if (!_values.containsKey(key)) return null;
    final value = _values[key];
    if (value is! String) {
      throw CanonicalFormatException(
        '$path.$key must be a string when present',
      );
    }
    return value;
  }

  /// Reads a required portable integer.
  int integer(String key) {
    final value = _values[key];
    if (value is! int) {
      throw CanonicalFormatException('$path.$key must be an integer');
    }
    return value;
  }

  /// Reads a required Boolean.
  bool boolean(String key) {
    final value = _values[key];
    if (value is! bool) {
      throw CanonicalFormatException('$path.$key must be a Boolean');
    }
    return value;
  }

  /// Reads an optional portable integer.
  int? optionalInteger(String key) {
    if (!_values.containsKey(key)) return null;
    final value = _values[key];
    if (value is! int) {
      throw CanonicalFormatException(
        '$path.$key must be an integer when present',
      );
    }
    return value;
  }

  /// Reads an optional Boolean.
  bool? optionalBoolean(String key) {
    if (!_values.containsKey(key)) return null;
    final value = _values[key];
    if (value is! bool) {
      throw CanonicalFormatException(
        '$path.$key must be a Boolean when present',
      );
    }
    return value;
  }

  /// Reads a required object.
  Map<String, Object?> object(String key) {
    final value = _values[key];
    if (value is! Map<String, Object?>) {
      throw CanonicalFormatException('$path.$key must be an object');
    }
    return value;
  }

  /// Reads an optional object.
  Map<String, Object?>? optionalObject(String key) {
    if (!_values.containsKey(key)) return null;
    final value = _values[key];
    if (value is! Map<String, Object?>) {
      throw CanonicalFormatException(
        '$path.$key must be an object when present',
      );
    }
    return value;
  }

  /// Reads a required list.
  List<Object?> list(String key) {
    final value = _values[key];
    if (value is! List<Object?>) {
      throw CanonicalFormatException('$path.$key must be a list');
    }
    return value;
  }

  /// Reads an optional list.
  List<Object?>? optionalList(String key) {
    if (!_values.containsKey(key)) return null;
    final value = _values[key];
    if (value is! List<Object?>) {
      throw CanonicalFormatException('$path.$key must be a list when present');
    }
    return value;
  }

  /// Reads an untyped value after closed-key validation.
  Object? value(String key) => _values[key];

  /// Reads a required field whose closed contract explicitly permits null.
  Object? requiredNullableValue(String key) {
    if (!_values.containsKey(key)) {
      throw CanonicalFormatException('$path.$key is required');
    }
    return _values[key];
  }
}

/// Rejects typed-schema aliases introduced by constructor normalization.
T verifyCanonicalRoundTrip<T extends CanonicalValue>(
  T value,
  List<int> suppliedBytes, {
  required String path,
}) {
  if (!_bytesEqual(value.canonicalBytes, suppliedBytes)) {
    throw CanonicalFormatException(
      '$path does not reconstruct the supplied canonical bytes',
    );
  }
  return value;
}

/// Requires [value] to be an object at [path].
Map<String, Object?> requireCanonicalObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw CanonicalFormatException('$path must be an object');
  }
  return value;
}

/// Requires [value] to be a string at [path].
String requireCanonicalString(Object? value, String path) {
  if (value is! String) {
    throw CanonicalFormatException('$path must be a string');
  }
  return value;
}

/// Decodes canonical bytes and requires an object root.
Map<String, Object?> decodeCanonicalObject(List<int> bytes) {
  final value = CanonicalJsonCodec.decode(bytes);
  if (value is! Map<String, Object?>) {
    throw const CanonicalFormatException('Document root must be an object');
  }
  return value;
}

/// Internal decoder that passes a privately immutable object graph to [callback].
T decodeStrictCanonicalObject<T>(
  List<int> bytes,
  T Function(Map<String, Object?> root) callback,
) =>
    callback(_StrictCanonicalMap.fromCanonical(decodeCanonicalObject(bytes)));

/// Internal structural check for an audited strict parsed object graph.
bool strictCanonicalFidelityCanReturn(
  Map<String, Object?> supplied,
  Map<String, Object?> Function() reconstruct,
) {
  if (supplied is! _StrictCanonicalMap) return false;

  final expected = reconstruct();
  try {
    return _strictCanonicalValuesEqual(expected, supplied);
  } on Object catch (_) {
    return false;
  }
}

bool _strictCanonicalValuesEqual(Object? expected, Object? supplied) =>
    switch (supplied) {
      null => expected == null,
      bool() => expected is bool && expected == supplied,
      int() => expected is int && expected == supplied,
      String() => expected is String && expected == supplied,
      _StrictCanonicalList() => _strictCanonicalListsEqual(expected, supplied),
      _StrictCanonicalMap() => _strictCanonicalMapsEqual(expected, supplied),
      _ => false,
    };

bool _strictCanonicalListsEqual(
  Object? expected,
  _StrictCanonicalList supplied,
) {
  if (expected is! List<Object?> || expected.length != supplied.length) {
    return false;
  }
  for (var index = 0; index < supplied.length; index++) {
    if (!_strictCanonicalValuesEqual(expected[index], supplied[index])) {
      return false;
    }
  }
  return true;
}

bool _strictCanonicalMapsEqual(
  Object? expected,
  _StrictCanonicalMap supplied,
) {
  if (expected is! Map<String, Object?> || expected.length != supplied.length) {
    return false;
  }
  for (final entry in supplied.entries) {
    if (!expected.containsKey(entry.key) ||
        !_strictCanonicalValuesEqual(expected[entry.key], entry.value)) {
      return false;
    }
  }
  return true;
}

Object? _strictCanonicalValue(Object? value) => switch (value) {
      Map<String, Object?>() => _StrictCanonicalMap.fromCanonical(value),
      List<Object?>() => _StrictCanonicalList.fromCanonical(value),
      _ => value,
    };

final class _StrictCanonicalMap extends MapBase<String, Object?> {
  _StrictCanonicalMap._(List<String> keys, List<Object?> values)
      : _keys = List<String>.unmodifiable(keys),
        _values = List<Object?>.unmodifiable(values),
        _indices = Map<String, int>.unmodifiable({
          for (var index = 0; index < keys.length; index++) keys[index]: index,
        });

  factory _StrictCanonicalMap.fromCanonical(Map<String, Object?> values) {
    final keys = <String>[];
    final closedValues = <Object?>[];
    for (final entry in values.entries) {
      keys.add(entry.key);
      closedValues.add(_strictCanonicalValue(entry.value));
    }
    return _StrictCanonicalMap._(keys, closedValues);
  }

  final List<String> _keys;
  final List<Object?> _values;
  final Map<String, int> _indices;

  @override
  Iterable<String> get keys => _keys;

  @override
  Iterable<Object?> get values => _values;

  @override
  Iterable<MapEntry<String, Object?>> get entries => Iterable.generate(
        _keys.length,
        (index) => MapEntry(_keys[index], _values[index]),
      );

  @override
  Object? operator [](Object? key) {
    if (key is! String) return null;
    final index = _indices[key];
    return index == null ? null : _values[index];
  }

  @override
  bool containsKey(Object? key) => key is String && _indices.containsKey(key);

  @override
  void operator []=(String key, Object? value) {
    throw UnsupportedError('Strict canonical maps are immutable');
  }

  @override
  Object? remove(Object? key) {
    throw UnsupportedError('Strict canonical maps are immutable');
  }

  @override
  void clear() {
    throw UnsupportedError('Strict canonical maps are immutable');
  }
}

final class _StrictCanonicalList extends ListBase<Object?> {
  _StrictCanonicalList._(List<Object?> values)
      : _values = List<Object?>.unmodifiable(values);

  factory _StrictCanonicalList.fromCanonical(List<Object?> values) =>
      _StrictCanonicalList._([
        for (final value in values) _strictCanonicalValue(value),
      ]);

  final List<Object?> _values;

  @override
  int get length => _values.length;

  @override
  set length(int value) {
    throw UnsupportedError('Strict canonical lists are immutable');
  }

  @override
  Object? operator [](int index) => _values[index];

  @override
  void operator []=(int index, Object? value) {
    throw UnsupportedError('Strict canonical lists are immutable');
  }
}

/// Validates the common version and kind fields of a document reader.
void validateCanonicalDocument(
  CanonicalObjectReader reader, {
  required String expectedKind,
}) {
  final version = reader.integer('schemaVersion');
  if (version != kMeasurementSchemaVersion) {
    throw CanonicalFormatException(
      '${reader.path}.schemaVersion $version is unsupported',
    );
  }
  final kind = reader.string('kind');
  if (kind != expectedKind) {
    throw CanonicalFormatException(
      '${reader.path}.kind "$kind" is not "$expectedKind"',
    );
  }
}

List<String> _sorted(Iterable<String> values) => values.toList()..sort();

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
