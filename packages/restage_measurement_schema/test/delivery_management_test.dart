import 'dart:convert';
import 'dart:io';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  final identity = PublishedSurfaceIdentityV1.fromCanonicalBytes(
    File('test/fixtures/published_identity/published_surface_identity_v1.json')
        .readAsBytesSync(),
  );
  final scope = DeliveryPolicyScopeV1(
    root: DeliveryRootIdentityV1.surface(identity),
    family: const DeliveryFamilySelectorV1.general(),
  );
  final documentRef = ExactRoutingDocumentRefV1(
    schemaVersion: 2,
    canonicalDigest: CanonicalDigest('a' * 64),
  );
  final revision = _revision(scope);
  final selection = DeliveryPolicyDocumentSelectionV1(
    policyRevision: revision,
    documentRef: documentRef,
  );

  test('exact document reference preserves its original canonical bytes', () {
    final expected = '{"canonicalDigest":"${'a' * 64}",'
        '"kind":"exactRoutingDocumentRef","schemaVersion":2}';
    expect(utf8.decode(documentRef.canonicalBytes), expected);
    expect(
      ExactRoutingDocumentRefV1.fromCanonicalBytes(utf8.encode(expected)),
      documentRef,
    );
    expect(documentRef.toJson(), {
      'kind': 'exactRoutingDocumentRef',
      'schemaVersion': 2,
      'canonicalDigest': 'a' * 64,
    });
    for (final version in [0, 1, 3, kMaximumPortableJsonInteger]) {
      expect(
        () => ExactRoutingDocumentRefV1(
          schemaVersion: version,
          canonicalDigest: CanonicalDigest('a' * 64),
        ),
        throwsArgumentError,
      );
      expect(
        () => ExactRoutingDocumentRefV1.fromJson({
          ...documentRef.toJson(),
          'schemaVersion': version,
        }),
        _formatFailure,
      );
    }
    for (final digest in ['A' * 64, 'a' * 63, 'sha256:${'a' * 64}']) {
      expect(
        () => ExactRoutingDocumentRefV1.fromJson({
          ...documentRef.toJson(),
          'canonicalDigest': digest,
        }),
        _formatFailure,
      );
    }
    expect(
      () => ExactRoutingDocumentRefV1.fromCanonicalBytes([-1]),
      _formatFailure,
    );
    expect(
      () => ExactRoutingDocumentRefV1.fromCanonicalBytes([256]),
      _formatFailure,
    );
  });

  test('policy reference has exact positive ordinal and bounded revision ID',
      () {
    for (final ordinal in [1, kMaximumPortableJsonInteger]) {
      for (final id in ['policy:p:1', 'a' * 128, '0._:-']) {
        final value = _revision(scope, ordinal: ordinal, revisionId: id);
        expect(
          DeliveryPolicyRevisionRefV1.fromCanonicalBytes(
            value.canonicalBytes,
          ),
          value,
        );
        expect(value.ordinal, ordinal);
        expect(value.revisionId, id);
        expect(value.canonicalPolicyDigest, CanonicalDigest('b' * 64));
      }
    }
    for (final ordinal in [0, -1, kMaximumPortableJsonInteger + 1]) {
      expect(() => _revision(scope, ordinal: ordinal), throwsArgumentError);
      expect(
        () => DeliveryPolicyRevisionRefV1.fromJson({
          ...revision.toJson(),
          'ordinal': ordinal,
        }),
        _formatFailure,
      );
    }
    for (final id in ['', 'a' * 129, 'Policy.1', 'policy 1', 'é', 'a\u0000']) {
      expect(() => _revision(scope, revisionId: id), throwsArgumentError);
      expect(
        () => DeliveryPolicyRevisionRefV1.fromJson({
          ...revision.toJson(),
          'revisionId': id,
        }),
        _formatFailure,
      );
    }
    for (final (field, value) in <(String, Object?)>[
      ('ordinal', 1.0),
      ('revisionId', null),
      ('canonicalPolicyDigest', 'B' * 64),
      ('scope', null),
    ]) {
      expect(
        () => DeliveryPolicyRevisionRefV1.fromJson({
          ...revision.toJson(),
          field: value,
        }),
        _formatFailure,
      );
    }
  });

  test('document selection seals scope through the exact policy reference', () {
    expect(selection.policyRevision, revision);
    expect(selection.policyRevision.scope, scope);
    expect(selection.documentRef, documentRef);
    expect(
      selection.toJson().keys,
      unorderedEquals(['kind', 'policyRevision', 'documentRef']),
    );
    expect(
      DeliveryPolicyDocumentSelectionV1.fromCanonicalBytes(
        selection.canonicalBytes,
      ),
      selection,
    );
    final otherScope = DeliveryPolicyScopeV1(
      root: DeliveryRootIdentityV1.placement(
        PlacementIdentityV1(
          target: identity.target,
          key: PlacementKeyV1.named(slug: 'home'),
        ),
      ),
      family: const DeliveryFamilySelectorV1.none(),
    );
    final other = DeliveryPolicyDocumentSelectionV1(
      policyRevision: _revision(otherScope),
      documentRef: documentRef,
    );
    expect(other, isNot(selection));
    expect(
      () => DeliveryPolicyDocumentSelectionV1.fromJson({
        ...selection.toJson(),
        'scope': otherScope.toJson(),
      }),
      _formatFailure,
    );
    final nested = _json(selection);
    (nested['policyRevision']! as Map<String, Object?>)['documents'] = [];
    expect(
      () => DeliveryPolicyDocumentSelectionV1.fromJson(nested),
      _formatFailure,
    );
    final nestedRef = _json(selection);
    (nestedRef['documentRef']! as Map<String, Object?>)['schemaVersion'] = 1;
    expect(
      () => DeliveryPolicyDocumentSelectionV1.fromJson(nestedRef),
      _formatFailure,
    );
  });

  test('safe reference codecs are strict closed canonical values', () {
    for (final (value, decode, fromJson) in <(
      CanonicalValue,
      CanonicalValue Function(List<int>),
      CanonicalValue Function(Map<String, Object?>),
    )>[
      (
        documentRef,
        ExactRoutingDocumentRefV1.fromCanonicalBytes,
        ExactRoutingDocumentRefV1.fromJson
      ),
      (
        revision,
        DeliveryPolicyRevisionRefV1.fromCanonicalBytes,
        DeliveryPolicyRevisionRefV1.fromJson
      ),
      (
        selection,
        DeliveryPolicyDocumentSelectionV1.fromCanonicalBytes,
        DeliveryPolicyDocumentSelectionV1.fromJson
      ),
    ]) {
      final decoded = decode(value.canonicalBytes);
      expect(decoded, value);
      expect(decoded.hashCode, value.hashCode);
      expect(decoded.canonicalBytes, value.canonicalBytes);
      for (final field in value.toJson().keys) {
        expect(
          () => fromJson(value.toJson()..remove(field)),
          _formatFailure,
          reason: field,
        );
      }
      for (final field in [
        'unknown',
        'documents',
        'rules',
        'canonicalDigest2',
      ]) {
        expect(() => fromJson({...value.toJson(), field: []}), _formatFailure);
      }
      expect(
        () => fromJson({...value.toJson(), 'kind': 'unknown'}),
        _formatFailure,
      );
      final text = utf8.decode(value.canonicalBytes);
      final kind = jsonEncode(value.toJson()['kind']);
      for (final invalid in [
        '$text\n',
        text.replaceFirst('"kind":$kind', '"kind":$kind,"kind":$kind'),
        text.replaceFirst('"kind"', r'"k\u0069nd"'),
      ]) {
        expect(invalid, isNot(text));
        expect(() => decode(utf8.encode(invalid)), _formatFailure);
      }
    }
  });

  test('nested JSON and returned bytes cannot mutate safe references', () {
    final bytes = selection.canonicalBytes;
    final decoded = DeliveryPolicyDocumentSelectionV1.fromCanonicalBytes(bytes);
    final hash = decoded.hashCode;
    bytes[0] = 0;
    decoded.canonicalBytes[0] = 0;
    final json = decoded.toJson();
    final policyJson = json['policyRevision']! as Map<String, Object?>;
    policyJson['revisionId'] = 'changed';
    final scopeJson = policyJson['scope']! as Map<String, Object?>;
    (scopeJson['family']! as Map<String, Object?>)['kind'] = 'none';
    (json['documentRef']! as Map<String, Object?>)['canonicalDigest'] =
        'c' * 64;
    json.clear();
    expect(decoded, selection);
    expect(decoded.hashCode, hash);
    expect(decoded.policyRevision.scope, scope);
    expect(decoded.policyRevision.revisionId, 'policy:p:1');
    expect(decoded.documentRef, documentRef);
  });
}

DeliveryPolicyRevisionRefV1 _revision(
  DeliveryPolicyScopeV1 scope, {
  int ordinal = 1,
  String revisionId = 'policy:p:1',
}) =>
    DeliveryPolicyRevisionRefV1(
      scope: scope,
      ordinal: ordinal,
      canonicalPolicyDigest: CanonicalDigest('b' * 64),
      revisionId: revisionId,
    );

Map<String, Object?> _json(CanonicalValue value) =>
    jsonDecode(jsonEncode(value.toJson())) as Map<String, Object?>;

final Matcher _formatFailure = throwsA(isA<CanonicalFormatException>());
