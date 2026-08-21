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
  static Uint8List encode(Object? value) {
    final output = StringBuffer();
    _writeValue(output, value);
    return Uint8List.fromList(utf8.encode(output.toString()));
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

    final encoded = encode(value);
    if (!_bytesEqual(encoded, bytes)) {
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
    for (var index = 0; index < value.length; index++) {
      final unit = value.codeUnitAt(index);
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
          } else {
            output.writeCharCode(unit);
            if (_isHighSurrogate(unit)) {
              index++;
              output.writeCharCode(value.codeUnitAt(index));
            }
          }
      }
    }
    output.write('"');
  }

  static int _compareUtf8(String left, String right) {
    _validateWellFormedUtf16(left);
    _validateWellFormedUtf16(right);
    final leftBytes = utf8.encode(left);
    final rightBytes = utf8.encode(right);
    final sharedLength = leftBytes.length < rightBytes.length
        ? leftBytes.length
        : rightBytes.length;
    for (var index = 0; index < sharedLength; index++) {
      final difference = leftBytes[index] - rightBytes[index];
      if (difference != 0) return difference;
    }
    return leftBytes.length - rightBytes.length;
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
}

/// Independently interpreted authorities with distinct hash namespaces.
enum CanonicalHashDomain {
  /// Exact organization/application/environment/runtime target.
  targetCoordinate('target-coordinate'),

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
  canonicalPublicationContextClosure('canonical-publication-context-closure');

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
  final digest = sha256.convert(<int>[...domain.prefixBytes, ...bytes]);
  return CanonicalDigest(digest.toString());
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

/// A top-level hash authority with one fixed domain.
abstract base class CanonicalDocument extends CanonicalValue {
  /// Creates an immutable canonical document.
  const CanonicalDocument();

  /// The only domain in which this authority may be hashed.
  CanonicalHashDomain get hashDomain;

  /// Domain-separated digest of [canonicalBytes].
  CanonicalDigest get canonicalDigest =>
      canonicalSha256(hashDomain, canonicalBytes);
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
