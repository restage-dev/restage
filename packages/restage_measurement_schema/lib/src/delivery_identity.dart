import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/identifiers.dart';
import 'package:restage_measurement_schema/src/publication_binding.dart';
import 'package:restage_measurement_schema/src/published_identity.dart';
import 'package:restage_measurement_schema/src/target.dart';

/// Lowercase SHA-256 key identity over its exact canonical namespace and name.
String placementKeyDigest(PlacementKeyV1 key) => crypto.sha256.convert([
      ...utf8.encode('restage.placement-key.v1\u0000'),
      ...key.canonicalBytes,
    ]).toString();

/// A placement name separated by explicit or generated surface-type namespace.
final class PlacementKeyV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  PlacementKeyV1._({required this.slug, this.surfaceType}) {
    if (_placementSlugPattern.stringMatch(slug) != slug) {
      throw ArgumentError.value(
        slug,
        'slug',
        'Expected 1..64 lowercase letters, digits, hyphens, or underscores '
            'starting with a letter or digit',
      );
    }
  }

  /// Names the default placement generated for one surface type and slug.
  factory PlacementKeyV1.generatedDefault({
    required DeliverySurfaceTypeId surfaceType,
    required String slug,
  }) =>
      PlacementKeyV1._(slug: slug, surfaceType: surfaceType);

  /// Names an explicit placement independently of any surface type.
  factory PlacementKeyV1.named({required String slug}) =>
      PlacementKeyV1._(slug: slug);

  /// Parses the retained scalar through the same validated constructors.
  factory PlacementKeyV1.parse(String value) => _constructIdentity(
        'placementKey',
        () {
          if (value.startsWith('named:')) {
            return PlacementKeyV1.named(slug: value.substring('named:'.length));
          }
          if (value.startsWith('default:')) {
            final separator = value.lastIndexOf(':');
            if (separator > 'default:'.length) {
              return PlacementKeyV1.generatedDefault(
                surfaceType: DeliverySurfaceTypeId(
                  value.substring('default:'.length, separator),
                ),
                slug: value.substring(separator + 1),
              );
            }
          }
          throw const CanonicalFormatException(
            'Invalid retained placement key',
          );
        },
      );

  /// Decodes byte-exact canonical placement-key bytes.
  factory PlacementKeyV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        PlacementKeyV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'placementKey',
      );

  /// Decodes one closed placement-key choice.
  factory PlacementKeyV1.fromJson(Map<String, Object?> json) {
    final kind = requireCanonicalString(json['kind'], 'placementKey.kind');
    final generated = switch (kind) {
      'generatedDefault' => true,
      'named' => false,
      _ => throw CanonicalFormatException('Unknown placement key "$kind"'),
    };
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: {'kind', 'slug', if (generated) 'surfaceType'},
      requiredKeys: {'kind', 'slug', if (generated) 'surfaceType'},
      path: 'placementKey',
    );
    return _constructIdentity(
      'placementKey',
      () => generated
          ? PlacementKeyV1.generatedDefault(
              surfaceType: DeliverySurfaceTypeId(reader.string('surfaceType')),
              slug: reader.string('slug'),
            )
          : PlacementKeyV1.named(slug: reader.string('slug')),
    );
  }

  /// Visible name within the selected namespace.
  final String slug;

  /// Generated-default namespace, absent for an explicit name.
  final DeliverySurfaceTypeId? surfaceType;

  /// Whether the name was generated for a particular surface type.
  bool get isGeneratedDefault => surfaceType != null;

  /// Collision-free retained scalar for storage and transport.
  String get value => surfaceType == null
      ? 'named:$slug'
      : 'default:${surfaceType!.value}:$slug';

  @override
  Map<String, Object?> toJson() => {
        'kind': isGeneratedDefault ? 'generatedDefault' : 'named',
        'slug': slug,
        if (surfaceType != null) 'surfaceType': surfaceType!.value,
      };

  @override
  String toString() => value;
}

/// One placement key qualified by its exact target.
final class PlacementIdentityV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Creates an exact placement identity.
  const PlacementIdentityV1({required this.target, required this.key});

  /// Decodes byte-exact canonical placement-identity bytes.
  factory PlacementIdentityV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        PlacementIdentityV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'placementIdentity',
      );

  /// Decodes one closed exact placement identity.
  factory PlacementIdentityV1.fromJson(Map<String, Object?> json) {
    final reader =
        _identityReader(json, 'placementIdentity', const {'key', 'target'});
    return PlacementIdentityV1(
      target: TargetCoordinate.fromJson(reader.object('target')),
      key: PlacementKeyV1.fromJson(reader.object('key')),
    );
  }

  /// Exact target authority.
  final TargetCoordinate target;

  /// Namespace-qualified placement name.
  final PlacementKeyV1 key;

  @override
  Map<String, Object?> toJson() => {
        'key': key.toJson(),
        'kind': 'placementIdentity',
        'target': target.toJson(),
      };
}

/// Exactly one surface or placement that owns a delivery policy.
final class DeliveryRootIdentityV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Selects an existing published surface identity.
  const DeliveryRootIdentityV1.surface(PublishedSurfaceIdentityV1 this.surface)
      : placement = null;

  /// Selects one exact placement identity.
  const DeliveryRootIdentityV1.placement(PlacementIdentityV1 this.placement)
      : surface = null;

  /// Decodes byte-exact canonical delivery-root bytes.
  factory DeliveryRootIdentityV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        DeliveryRootIdentityV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'deliveryRootIdentity',
      );

  /// Decodes a closed delivery-root choice.
  factory DeliveryRootIdentityV1.fromJson(Map<String, Object?> json) {
    final kind =
        requireCanonicalString(json['kind'], 'deliveryRootIdentity.kind');
    return switch (kind) {
      'surface' => DeliveryRootIdentityV1.surface(
          PublishedSurfaceIdentityV1.fromJson(
            _identityReader(json, 'surface', const {'surface'})
                .object('surface'),
          ),
        ),
      'placement' => DeliveryRootIdentityV1.placement(
          PlacementIdentityV1.fromJson(
            _identityReader(json, 'placement', const {'placement'})
                .object('placement'),
          ),
        ),
      _ => throw CanonicalFormatException('Unknown delivery root "$kind"'),
    };
  }

  /// Surface branch, absent for a placement root.
  final PublishedSurfaceIdentityV1? surface;

  /// Placement branch, absent for a surface root.
  final PlacementIdentityV1? placement;

  /// Whether this policy is owned by a placement.
  bool get isPlacement => placement != null;

  /// Exact target of the selected root.
  TargetCoordinate get target => surface?.target ?? placement!.target;

  @override
  Map<String, Object?> toJson() => {
        'kind': isPlacement ? 'placement' : 'surface',
        if (surface != null) 'surface': surface!.toJson(),
        if (placement != null) 'placement': placement!.toJson(),
      };
}

/// Placement scope, a general surface, or an exact screen-contract family.
final class DeliveryFamilySelectorV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Selects the family-free placement scope.
  const DeliveryFamilySelectorV1.none()
      : _kind = 'none',
        contractVersion = null;

  /// Selects the general surface family.
  const DeliveryFamilySelectorV1.general()
      : _kind = 'general',
        contractVersion = null;

  /// Selects a positive screen-contract family.
  DeliveryFamilySelectorV1.screenContract({required int contractVersion})
      : _kind = 'screenContract',
        contractVersion = contractVersion {
    _requirePositivePortable(contractVersion, 'contractVersion');
  }

  /// Decodes byte-exact canonical delivery-family bytes.
  factory DeliveryFamilySelectorV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        DeliveryFamilySelectorV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'deliveryFamilySelector',
      );

  /// Decodes one closed family choice.
  factory DeliveryFamilySelectorV1.fromJson(Map<String, Object?> json) {
    final kind =
        requireCanonicalString(json['kind'], 'deliveryFamilySelector.kind');
    return _constructIdentity(
      'deliveryFamilySelector',
      () => switch (kind) {
        'none' => _readEmptyFamily(json, kind),
        'general' => _readEmptyFamily(json, kind),
        'screenContract' => DeliveryFamilySelectorV1.screenContract(
            contractVersion:
                _identityReader(json, kind, const {'contractVersion'})
                    .integer('contractVersion'),
          ),
        _ => throw CanonicalFormatException(
            'Unknown delivery family "$kind"',
          ),
      },
    );
  }

  final String _kind;

  /// Exact contract version, present only for the screen-contract branch.
  final int? contractVersion;

  /// Whether this is the family-free placement branch.
  bool get isNone => _kind == 'none';

  /// Whether this is the general surface branch.
  bool get isGeneral => _kind == 'general';

  /// Whether this is a screen-contract branch.
  bool get isScreenContract => contractVersion != null;

  @override
  Map<String, Object?> toJson() => {
        'kind': _kind,
        if (contractVersion != null) 'contractVersion': contractVersion,
      };
}

/// A published surface together with the exact family it serves.
final class DeliverySurfaceReferenceV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Creates a surface reference that has a real surface family.
  DeliverySurfaceReferenceV1({
    required this.surfaceIdentity,
    required this.family,
  }) {
    if (family.isNone) {
      throw ArgumentError(
        'A delivery surface reference requires a surface family',
      );
    }
  }

  /// Decodes byte-exact canonical surface-reference bytes.
  factory DeliverySurfaceReferenceV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        DeliverySurfaceReferenceV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'deliverySurfaceReference',
      );

  /// Decodes one closed surface reference.
  factory DeliverySurfaceReferenceV1.fromJson(Map<String, Object?> json) {
    final reader = _identityReader(
      json,
      'deliverySurfaceReference',
      const {'family', 'surfaceIdentity'},
    );
    return _constructIdentity(
      'deliverySurfaceReference',
      () => DeliverySurfaceReferenceV1(
        surfaceIdentity: PublishedSurfaceIdentityV1.fromJson(
          reader.object('surfaceIdentity'),
        ),
        family: DeliveryFamilySelectorV1.fromJson(reader.object('family')),
      ),
    );
  }

  /// Stable exact published-surface identity.
  final PublishedSurfaceIdentityV1 surfaceIdentity;

  /// General or screen-contract family.
  final DeliveryFamilySelectorV1 family;

  /// Exact target of this surface.
  TargetCoordinate get target => surfaceIdentity.target;

  @override
  Map<String, Object?> toJson() => {
        'family': family.toJson(),
        'kind': 'deliverySurfaceReference',
        'surfaceIdentity': surfaceIdentity.toJson(),
      };
}

/// An exact policy owner with its permitted family branch.
final class DeliveryPolicyScopeV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Requires `none` for placements and a real family for surfaces.
  DeliveryPolicyScopeV1({required this.root, required this.family}) {
    if (root.isPlacement != family.isNone) {
      throw ArgumentError(
        'Placement scopes require none; '
        'surface scopes require a surface family',
      );
    }
  }

  /// Decodes byte-exact canonical delivery-scope bytes.
  factory DeliveryPolicyScopeV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        DeliveryPolicyScopeV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'deliveryPolicyScope',
      );

  /// Decodes one closed delivery policy scope.
  factory DeliveryPolicyScopeV1.fromJson(Map<String, Object?> json) {
    final reader =
        _identityReader(json, 'deliveryPolicyScope', const {'family', 'root'});
    return _constructIdentity(
      'deliveryPolicyScope',
      () => DeliveryPolicyScopeV1(
        root: DeliveryRootIdentityV1.fromJson(reader.object('root')),
        family: DeliveryFamilySelectorV1.fromJson(reader.object('family')),
      ),
    );
  }

  /// Exactly one surface or placement owner.
  final DeliveryRootIdentityV1 root;

  /// The owner's placement, general, or screen-contract family branch.
  final DeliveryFamilySelectorV1 family;

  /// Exact target of the policy owner.
  TargetCoordinate get target => root.target;

  @override
  Map<String, Object?> toJson() => {
        'family': family.toJson(),
        'kind': 'deliveryPolicyScope',
        'root': root.toJson(),
      };
}

/// Exact remote delivered-output coordinate and optional measurement binding.
final class DeliveryPublicationReferenceV1 extends CanonicalValue
    implements ImmutableCanonicalDocument {
  /// Creates an exact publication coordinate with positive portable versions.
  DeliveryPublicationReferenceV1({
    required this.surface,
    required this.publishedVersion,
    required this.payloadFormatVersion,
    required this.contentHash,
    this.publicationBindingRef,
  }) {
    _requirePositivePortable(publishedVersion, 'publishedVersion');
    _requirePositivePortable(payloadFormatVersion, 'payloadFormatVersion');
  }

  /// Decodes byte-exact canonical delivery-publication bytes.
  factory DeliveryPublicationReferenceV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        DeliveryPublicationReferenceV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'deliveryPublicationReference',
      );

  /// Decodes one closed exact publication coordinate.
  factory DeliveryPublicationReferenceV1.fromJson(Map<String, Object?> json) {
    final reader = _identityReader(
      json,
      'deliveryPublicationReference',
      const {
        'contentHash',
        'payloadFormatVersion',
        'publishedVersion',
        'surface',
      },
      optional: const {
        'publicationBindingRef',
      },
    );
    final binding = reader.optionalObject('publicationBindingRef');
    return _constructIdentity(
      'deliveryPublicationReference',
      () => DeliveryPublicationReferenceV1(
        surface: DeliverySurfaceReferenceV1.fromJson(reader.object('surface')),
        publishedVersion: reader.integer('publishedVersion'),
        payloadFormatVersion: reader.integer('payloadFormatVersion'),
        contentHash: CanonicalDigest(reader.string('contentHash')),
        publicationBindingRef: binding == null
            ? null
            : MeasurementPublicationBindingReferenceV1.fromJson(binding),
      ),
    );
  }

  /// Exact surface and general or screen-contract family.
  final DeliverySurfaceReferenceV1 surface;

  /// General version or screen revision within [surface]'s exact family.
  final int publishedVersion;

  /// Exact payload encoding version.
  final int payloadFormatVersion;

  /// Exact delivered content digest.
  final CanonicalDigest contentHash;

  /// Opaque binding whose coordinate is proved by its resolving authority.
  final MeasurementPublicationBindingReferenceV1? publicationBindingRef;

  @override
  Map<String, Object?> toJson() => {
        'contentHash': contentHash.hex,
        'kind': 'deliveryPublicationReference',
        'payloadFormatVersion': payloadFormatVersion,
        if (publicationBindingRef != null)
          'publicationBindingRef': publicationBindingRef!.toJson(),
        'publishedVersion': publishedVersion,
        'surface': surface.toJson(),
      };
}

final _placementSlugPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');

CanonicalObjectReader _identityReader(
  Map<String, Object?> json,
  String kind,
  Set<String> required, {
  Set<String> optional = const {},
}) {
  final reader = CanonicalObjectReader(
    json,
    allowedKeys: {'kind', ...required, ...optional},
    requiredKeys: {'kind', ...required},
    path: kind,
  );
  if (reader.string('kind') != kind) {
    throw CanonicalFormatException('Expected $kind');
  }
  return reader;
}

DeliveryFamilySelectorV1 _readEmptyFamily(
  Map<String, Object?> json,
  String kind,
) {
  _identityReader(json, kind, const {});
  return kind == 'none'
      ? const DeliveryFamilySelectorV1.none()
      : const DeliveryFamilySelectorV1.general();
}

T _constructIdentity<T>(String path, T Function() build) {
  try {
    return build();
    // Constructor refusals become canonical-format refusals when decoding.
    // ignore: avoid_catching_errors
  } on ArgumentError catch (error) {
    throw CanonicalFormatException('$path is invalid: ${error.message}');
  }
}

void _requirePositivePortable(int value, String field) {
  if (value <= 0 || value > kMaximumPortableJsonInteger) {
    throw ArgumentError.value(
      value,
      field,
      'Expected a positive portable JSON integer',
    );
  }
}
