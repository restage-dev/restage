import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

/// The exact contract tuple of a published screen that declares no host data.
const _eventContractHash =
    'sha256:cfc387dfbcb989b75d6a41c878a1710db9da1a1ae4977edce3ea0ced6f9e4a7a';

CapabilityManifest _capabilities() => CapabilityManifest(
      builtInFloor: 1,
      requiredLibraries: const <LibraryRequirement>[
        LibraryRequirement(
          namespace: 'compact_list_demo.widgets',
          minVersion: 1,
        ),
      ],
    );

void main() {
  group('host data contract hash', () {
    test('is absent for a screen that declares no host data', () {
      const schema = SurfaceScreenHostDataSchema.empty();

      expect(schema.isEmpty, isTrue);
      expect(SurfaceScreenHostDataContractHash.hash(schema), isNull);
    });

    test('is stable under authored input and field order', () {
      final byOneOrder = SurfaceScreenHostDataSchema(
        const <String, SurfaceScreenHostDataShape>{
          'title': SurfaceScreenHostDataScalarShapeV1(
            SurfaceScreenHostDataScalarKind.string,
          ),
          'count': SurfaceScreenHostDataScalarShapeV1(
            SurfaceScreenHostDataScalarKind.integer,
          ),
        },
      );
      final byOtherOrder = SurfaceScreenHostDataSchema(
        const <String, SurfaceScreenHostDataShape>{
          'count': SurfaceScreenHostDataScalarShapeV1(
            SurfaceScreenHostDataScalarKind.integer,
          ),
          'title': SurfaceScreenHostDataScalarShapeV1(
            SurfaceScreenHostDataScalarKind.string,
          ),
        },
      );

      expect(
        SurfaceScreenHostDataContractHash.hash(byOneOrder),
        SurfaceScreenHostDataContractHash.hash(byOtherOrder),
      );
    });

    test('round-trips every shape through its strict codec', () {
      final schema = SurfaceScreenHostDataSchema(
        <String, SurfaceScreenHostDataShape>{
          'rows': SurfaceScreenHostDataListShapeV1(
            SurfaceScreenHostDataObjectShapeV1(
              const <String, SurfaceScreenHostDataShape>{
                'id': SurfaceScreenHostDataScalarShapeV1(
                  SurfaceScreenHostDataScalarKind.string,
                ),
                'weight': SurfaceScreenHostDataScalarShapeV1(
                  SurfaceScreenHostDataScalarKind.number,
                ),
                'note': SurfaceScreenHostDataNullableShapeV1(
                  SurfaceScreenHostDataScalarShapeV1(
                    SurfaceScreenHostDataScalarKind.string,
                  ),
                ),
              },
            ),
          ),
          'lookup': const SurfaceScreenHostDataMapShapeV1(
            SurfaceScreenHostDataScalarShapeV1(
              SurfaceScreenHostDataScalarKind.jsonValue,
            ),
          ),
        },
      );

      final encoded =
          SurfaceScreenHostDataSchemaV1Codec.encodeCanonicalJson(schema);
      final decoded = SurfaceScreenHostDataSchemaV1Codec.decodeJson(encoded);

      expect(
        SurfaceScreenHostDataSchemaV1Codec.encodeCanonicalJson(decoded),
        encoded,
      );
      expect(
        SurfaceScreenHostDataContractHash.hash(decoded),
        SurfaceScreenHostDataContractHash.hash(schema),
      );
    });
  });

  group('screen contract fingerprint', () {
    test('omits the host data key entirely for an empty schema', () {
      const empty = SurfaceScreenHostDataSchema.empty();

      expect(
        SurfaceScreenContractFingerprint.encodeCanonicalJson(
          sourceKind: SurfaceSourceKind.screen,
          payloadKind: SurfacePayloadKind.blob,
          capabilities: _capabilities(),
          eventContractHash: _eventContractHash,
          hostDataContractHash: SurfaceScreenHostDataContractHash.hash(empty),
        ),
        isNot(contains('hostDataContractHash')),
      );
      expect(
        SurfaceScreenContractFingerprint.hash(
          sourceKind: SurfaceSourceKind.screen,
          payloadKind: SurfacePayloadKind.blob,
          capabilities: _capabilities(),
          eventContractHash: _eventContractHash,
          hostDataContractHash: SurfaceScreenHostDataContractHash.hash(empty),
        ),
        SurfaceScreenContractFingerprint.hash(
          sourceKind: SurfaceSourceKind.screen,
          payloadKind: SurfacePayloadKind.blob,
          capabilities: _capabilities(),
          eventContractHash: _eventContractHash,
        ),
      );
    });

    test('changes when a screen starts requiring host data', () {
      final declared = SurfaceScreenHostDataSchema(
        <String, SurfaceScreenHostDataShape>{
          'habits': SurfaceScreenHostDataListShapeV1(
            SurfaceScreenHostDataObjectShapeV1(
              const <String, SurfaceScreenHostDataShape>{
                'name': SurfaceScreenHostDataScalarShapeV1(
                  SurfaceScreenHostDataScalarKind.string,
                ),
              },
            ),
          ),
        },
      );

      final withoutHostData = SurfaceScreenContractFingerprint.hash(
        sourceKind: SurfaceSourceKind.screen,
        payloadKind: SurfacePayloadKind.blob,
        capabilities: _capabilities(),
        eventContractHash: _eventContractHash,
      );
      final withHostData = SurfaceScreenContractFingerprint.hash(
        sourceKind: SurfaceSourceKind.screen,
        payloadKind: SurfacePayloadKind.blob,
        capabilities: _capabilities(),
        eventContractHash: _eventContractHash,
        hostDataContractHash: SurfaceScreenHostDataContractHash.hash(declared),
      );

      expect(withHostData, isNot(withoutHostData));
    });

    test('changes when a declared host data shape changes', () {
      SurfaceScreenHostDataSchema schemaFor(
        SurfaceScreenHostDataShape shape,
      ) =>
          SurfaceScreenHostDataSchema(<String, SurfaceScreenHostDataShape>{
            'habits': shape,
          });

      String fingerprintFor(SurfaceScreenHostDataShape shape) =>
          SurfaceScreenContractFingerprint.hash(
            sourceKind: SurfaceSourceKind.screen,
            payloadKind: SurfacePayloadKind.blob,
            capabilities: _capabilities(),
            eventContractHash: _eventContractHash,
            hostDataContractHash: SurfaceScreenHostDataContractHash.hash(
              schemaFor(shape),
            ),
          );

      expect(
        fingerprintFor(
          const SurfaceScreenHostDataScalarShapeV1(
            SurfaceScreenHostDataScalarKind.string,
          ),
        ),
        isNot(
          fingerprintFor(
            const SurfaceScreenHostDataScalarShapeV1(
              SurfaceScreenHostDataScalarKind.integer,
            ),
          ),
        ),
      );
    });
  });
}
