import 'dart:convert';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  test('placement key digest seals the exact key namespace', () {
    final named = PlacementKeyV1.named(slug: 'welcome');
    final general = PlacementKeyV1.generatedDefault(
      surfaceType: DeliverySurfaceTypeId('general'),
      slug: 'welcome',
    );
    final message = PlacementKeyV1.generatedDefault(
      surfaceType: DeliverySurfaceTypeId('message'),
      slug: 'welcome',
    );
    expect(
      placementKeyDigest(named),
      '8ef58b51e843bc9300e10d044d1d9b1e0e52f95f3d27441087664ed4582da5e2',
    );
    expect(
      {
        placementKeyDigest(named),
        placementKeyDigest(general),
        placementKeyDigest(message),
      },
      hasLength(3),
    );
    expect(placementKeyDigest(named), matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  final target = _target();
  final identity = PublishedSurfaceIdentityV1(
    target: target,
    surfaceId: SurfaceId('surface.home'),
  );
  final general = DeliverySurfaceReferenceV1(
    surfaceIdentity: identity,
    family: const DeliveryFamilySelectorV1.general(),
  );
  final screen = DeliverySurfaceReferenceV1(
    surfaceIdentity: identity,
    family: DeliveryFamilySelectorV1.screenContract(contractVersion: 3),
  );
  final placement = PlacementIdentityV1(
    target: target,
    key: PlacementKeyV1.named(slug: 'home'),
  );
  final placementScope = DeliveryPolicyScopeV1(
    root: DeliveryRootIdentityV1.placement(placement),
    family: const DeliveryFamilySelectorV1.none(),
  );
  final generalScope = DeliveryPolicyScopeV1(
    root: DeliveryRootIdentityV1.surface(identity),
    family: general.family,
  );
  final screenScope = DeliveryPolicyScopeV1(
    root: DeliveryRootIdentityV1.surface(identity),
    family: screen.family,
  );

  test('placement keys preserve generated type and explicit namespaces', () {
    final message = PlacementKeyV1.generatedDefault(
      surfaceType: DeliverySurfaceTypeId('message'),
      slug: 'home',
    );
    final paywall = PlacementKeyV1.generatedDefault(
      surfaceType: DeliverySurfaceTypeId('paywall'),
      slug: 'home',
    );
    final named = PlacementKeyV1.named(slug: 'home');
    expect({message, paywall, named}, hasLength(3));
    expect(message.value, 'default:message:home');
    expect(paywall.value, 'default:paywall:home');
    expect(named.value, 'named:home');
    expect(
      utf8.decode(message.canonicalBytes),
      '{"kind":"generatedDefault","slug":"home","surfaceType":"message"}',
    );
    expect(utf8.decode(named.canonicalBytes), '{"kind":"named","slug":"home"}');
    for (final key in [message, paywall, named]) {
      expect(PlacementKeyV1.parse(key.value), key);
      expect(PlacementKeyV1.parse(key.value).hashCode, key.hashCode);
    }
    final registeredType = PlacementKeyV1.generatedDefault(
      surfaceType: DeliverySurfaceTypeId('custom:message.v2'),
      slug: 'home',
    );
    expect(PlacementKeyV1.parse(registeredType.value), registeredType);
    expect(PlacementKeyV1.named(slug: 'a' * 64).slug, hasLength(64));
  });

  test('placement scalar and object codecs reject aliases and invalid slugs',
      () {
    for (final value in [
      '',
      'home',
      'named:',
      'named:Home',
      'named:a:b',
      'default:message:',
      'default::home',
      'default:Message:home',
      'default:message:home ',
      'named:${'a' * 65}',
      'named:home\n',
    ]) {
      expect(
        () => PlacementKeyV1.parse(value),
        throwsA(isA<CanonicalFormatException>()),
        reason: value,
      );
    }
    for (final slug in [
      '',
      'Home',
      '_home',
      'a:b',
      'a.b',
      'é',
      'a' * 65,
      'a\n',
    ]) {
      expect(() => PlacementKeyV1.named(slug: slug), throwsArgumentError);
      expect(
        () => PlacementKeyV1.generatedDefault(
          surfaceType: DeliverySurfaceTypeId('message'),
          slug: slug,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => PlacementKeyV1.fromJson({
        'kind': 'named',
        'slug': 'home',
        'surfaceType': 'message',
      }),
      throwsA(isA<CanonicalFormatException>()),
    );
    expect(
      () => PlacementKeyV1.fromJson({
        'kind': 'generatedDefault',
        'slug': 'home',
      }),
      throwsA(isA<CanonicalFormatException>()),
    );
  });

  test('placement none and general surface are different scopes', () {
    expect(
      () => DeliveryPolicyScopeV1(
        root: DeliveryRootIdentityV1.placement(placement),
        family: const DeliveryFamilySelectorV1.general(),
      ),
      throwsArgumentError,
    );
    expect(
      () => DeliveryPolicyScopeV1(
        root: DeliveryRootIdentityV1.placement(placement),
        family: screen.family,
      ),
      throwsArgumentError,
    );
    expect(
      () => DeliveryPolicyScopeV1(
        root: DeliveryRootIdentityV1.surface(identity),
        family: const DeliveryFamilySelectorV1.none(),
      ),
      throwsArgumentError,
    );
    expect(
      () => DeliverySurfaceReferenceV1(
        surfaceIdentity: identity,
        family: const DeliveryFamilySelectorV1.none(),
      ),
      throwsArgumentError,
    );
    expect(placementScope, isNot(generalScope));
    expect(
      const DeliveryFamilySelectorV1.none(),
      isNot(const DeliveryFamilySelectorV1.general()),
    );
    expect(placementScope.target, target);
    expect(generalScope.target, target);
    expect(screen.target, target);
  });

  test('delivery roots reject missing and multiple union branches', () {
    for (final json in <Map<String, Object?>>[
      {'kind': 'surface'},
      {
        'kind': 'surface',
        'surface': identity.toJson(),
        'placement': placement.toJson(),
      },
      {
        'kind': 'placement',
        'surface': identity.toJson(),
        'placement': placement.toJson(),
      },
      {'kind': 'unknown', 'surface': identity.toJson()},
    ]) {
      expect(
        () => DeliveryRootIdentityV1.fromJson(json),
        throwsA(isA<CanonicalFormatException>()),
      );
    }
  });

  test('screen families require positive portable contract versions', () {
    for (final invalid in [-1, 0, kMaximumPortableJsonInteger + 1]) {
      expect(
        () => DeliveryFamilySelectorV1.screenContract(contractVersion: invalid),
        throwsArgumentError,
      );
    }
    expect(
      DeliveryFamilySelectorV1.screenContract(
        contractVersion: kMaximumPortableJsonInteger,
      ).contractVersion,
      kMaximumPortableJsonInteger,
    );
    expect(
      DeliveryFamilySelectorV1.screenContract(contractVersion: 4),
      isNot(screen.family),
    );
    expect(screen.family, isNot(general.family));
    for (final json in <Map<String, Object?>>[
      {'kind': 'none', 'contractVersion': 1},
      {'kind': 'general', 'contractVersion': 1},
      {'kind': 'screenContract'},
      {'kind': 'screenContract', 'contractVersion': null},
      {'kind': 'screenContract', 'contractVersion': 1.0},
      {'kind': 'screenContract', 'contractVersion': 0},
    ]) {
      expect(
        () => DeliveryFamilySelectorV1.fromJson(json),
        throwsA(isA<CanonicalFormatException>()),
      );
    }
  });

  test('identities and publication references retain every target coordinate',
      () {
    final targetJson = target.toJson();
    final otherTargets = [
      for (final field in [
        'organizationId',
        'appId',
        'environmentTargetId',
        'namedEnvironmentId',
      ])
        TargetCoordinate.fromJson({
          ...targetJson,
          field: (targetJson[field]! as int) + 1,
        }),
      TargetCoordinate.fromJson({...targetJson, 'runtimePlane': 'sandbox'}),
    ];
    for (final otherTarget in otherTargets) {
      final otherPlacement = PlacementIdentityV1(
        target: otherTarget,
        key: placement.key,
      );
      final otherSurface = DeliverySurfaceReferenceV1(
        surfaceIdentity: PublishedSurfaceIdentityV1(
          target: otherTarget,
          surfaceId: identity.surfaceId,
        ),
        family: general.family,
      );
      expect(otherPlacement, isNot(placement));
      expect(otherSurface, isNot(general));
      expect(otherSurface.target, otherTarget);
      expect(
        DeliveryRootIdentityV1.placement(otherPlacement).target,
        otherTarget,
      );
      expect(
        DeliveryRootIdentityV1.surface(otherSurface.surfaceIdentity).target,
        otherTarget,
      );
      expect(
        DeliveryPolicyScopeV1(
          root: DeliveryRootIdentityV1.placement(otherPlacement),
          family: const DeliveryFamilySelectorV1.none(),
        ),
        isNot(placementScope),
      );
      expect(_publication(otherSurface), isNot(_publication(general)));
    }
  });

  test('publication references retain delivered coordinates and binding', () {
    final bound = _publication(screen, binding: _binding());
    final unbound = _publication(general);
    expect(unbound.toJson(), isNot(contains('publicationBindingRef')));
    expect(bound.publicationBindingRef, _binding());
    expect(bound.surface, screen);
    for (final different in [
      _publication(general, binding: _binding()),
      _publication(screen, publishedVersion: 8, binding: _binding()),
      _publication(screen, payloadFormatVersion: 3, binding: _binding()),
      _publication(
        screen,
        contentHash: CanonicalDigest('c' * 64),
        binding: _binding(),
      ),
      _publication(screen),
      _publication(screen, binding: _binding(digest: 'd')),
    ]) {
      expect(bound, isNot(different));
    }
    for (final invalid in [-1, 0, kMaximumPortableJsonInteger + 1]) {
      expect(
        () => _publication(screen, publishedVersion: invalid),
        throwsArgumentError,
      );
      expect(
        () => _publication(screen, payloadFormatVersion: invalid),
        throwsArgumentError,
      );
    }
    expect(
      () => DeliveryPublicationReferenceV1.fromJson({
        ...unbound.toJson(),
        'publicationBindingRef': null,
      }),
      throwsA(isA<CanonicalFormatException>()),
    );
    expect(
      () => DeliveryPublicationReferenceV1.fromJson({
        ...bound.toJson(),
        'contentHash': 'A' * 64,
      }),
      throwsA(isA<CanonicalFormatException>()),
    );
  });

  test(
      'all identity values round-trip with stable equality and immutable bytes',
      () {
    for (final (value, decode) in _values(
      identity,
      placement,
      general,
      screen,
      placementScope,
      generalScope,
      screenScope,
    )) {
      final bytes = value.canonicalBytes;
      final decoded = decode(bytes);
      expect(decoded, value, reason: value.runtimeType.toString());
      expect(decoded.hashCode, value.hashCode);
      expect(decoded.canonicalBytes, bytes);
      bytes[0] = 0;
      final json = value.toJson()..clear();
      expect(json, isEmpty);
      expect(decode(value.canonicalBytes), value);
    }
  });

  test('all identity codecs reject unknown keys duplicate keys and aliases',
      () {
    for (final (value, decode) in _values(
      identity,
      placement,
      general,
      screen,
      placementScope,
      generalScope,
      screenScope,
    )) {
      expect(
        () => decode(
          CanonicalJsonCodec.encode({
            ...value.toJson(),
            'unknown': true,
          }),
        ),
        throwsA(isA<CanonicalFormatException>()),
        reason: value.runtimeType.toString(),
      );
      final text = utf8.decode(value.canonicalBytes);
      final kind = jsonEncode(value.toJson()['kind']);
      expect(
        () => decode(
          utf8.encode(
            text.replaceFirst(
              '"kind":$kind',
              '"kind":$kind,"kind":$kind',
            ),
          ),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => decode(utf8.encode('$text\n')),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => decode(
          CanonicalJsonCodec.encode({
            ...value.toJson(),
            'kind': 'unknown',
          }),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    }
    final nested = generalScope.toJson();
    final root =
        Map<String, Object?>.from(nested['root']! as Map<String, Object?>);
    root['surface'] = {...identity.toJson(), 'unknown': true};
    expect(
      () => DeliveryPolicyScopeV1.fromJson({...nested, 'root': root}),
      throwsA(isA<CanonicalFormatException>()),
    );
    expect(
      () => DeliveryPolicyScopeV1.fromJson({
        ...placementScope.toJson(),
        'family': const DeliveryFamilySelectorV1.general().toJson(),
      }),
      throwsA(isA<CanonicalFormatException>()),
    );
  });
}

TargetCoordinate _target({int environmentTarget = 7}) => TargetCoordinate(
      organizationId: OrganizationId(3),
      appId: ApplicationId(5),
      environmentTargetId: EnvironmentTargetId(environmentTarget),
      namedEnvironmentId: NamedEnvironmentId(6),
      runtimePlane: RuntimePlane.live,
    );

MeasurementPublicationBindingReferenceV1 _binding({String digest = 'b'}) {
  final declaredBytes = CanonicalDigest('a' * 64);
  return MeasurementPublicationBindingReferenceV1(
    publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
      authorityId:
          MeasurementPublicationAuthorityId('restage-surface-publication.v1'),
      externalPublicationAuthorityRef: 'mpa1.${'e' * 32}',
      candidateReference: MeasurementPublicationCandidateReferenceV1(
        candidateDigest: CanonicalDigest('1' * 64),
        selectedPublicationManifestDigest: CanonicalDigest('2' * 64),
        declaredArtifactBytesDigest: declaredBytes,
        assembledPublicationUploadDigest: CanonicalDigest('3' * 64),
        measurementPublicationDraftDigest: CanonicalDigest('4' * 64),
      ),
      immutablePublicationDigest: CanonicalDigest('5' * 64),
      declaredArtifactBytesDigest: declaredBytes,
    ),
    bindingDigest: CanonicalDigest(digest * 64),
  );
}

DeliveryPublicationReferenceV1 _publication(
  DeliverySurfaceReferenceV1 surface, {
  int publishedVersion = 7,
  int payloadFormatVersion = 2,
  CanonicalDigest? contentHash,
  MeasurementPublicationBindingReferenceV1? binding,
}) =>
    DeliveryPublicationReferenceV1(
      surface: surface,
      publishedVersion: publishedVersion,
      payloadFormatVersion: payloadFormatVersion,
      contentHash: contentHash ?? CanonicalDigest('a' * 64),
      publicationBindingRef: binding,
    );

List<(CanonicalValue, CanonicalValue Function(List<int>))> _values(
  PublishedSurfaceIdentityV1 identity,
  PlacementIdentityV1 placement,
  DeliverySurfaceReferenceV1 general,
  DeliverySurfaceReferenceV1 screen,
  DeliveryPolicyScopeV1 placementScope,
  DeliveryPolicyScopeV1 generalScope,
  DeliveryPolicyScopeV1 screenScope,
) =>
    [
      (PlacementKeyV1.named(slug: 'home'), PlacementKeyV1.fromCanonicalBytes),
      (
        PlacementKeyV1.generatedDefault(
          surfaceType: DeliverySurfaceTypeId('message'),
          slug: 'home',
        ),
        PlacementKeyV1.fromCanonicalBytes
      ),
      (placement, PlacementIdentityV1.fromCanonicalBytes),
      (
        DeliveryRootIdentityV1.surface(identity),
        DeliveryRootIdentityV1.fromCanonicalBytes
      ),
      (
        DeliveryRootIdentityV1.placement(placement),
        DeliveryRootIdentityV1.fromCanonicalBytes
      ),
      (
        const DeliveryFamilySelectorV1.none(),
        DeliveryFamilySelectorV1.fromCanonicalBytes
      ),
      (
        const DeliveryFamilySelectorV1.general(),
        DeliveryFamilySelectorV1.fromCanonicalBytes
      ),
      (screen.family, DeliveryFamilySelectorV1.fromCanonicalBytes),
      (general, DeliverySurfaceReferenceV1.fromCanonicalBytes),
      (screen, DeliverySurfaceReferenceV1.fromCanonicalBytes),
      (placementScope, DeliveryPolicyScopeV1.fromCanonicalBytes),
      (generalScope, DeliveryPolicyScopeV1.fromCanonicalBytes),
      (screenScope, DeliveryPolicyScopeV1.fromCanonicalBytes),
      (
        _publication(general),
        DeliveryPublicationReferenceV1.fromCanonicalBytes
      ),
      (
        _publication(screen, binding: _binding()),
        DeliveryPublicationReferenceV1.fromCanonicalBytes
      ),
    ];
