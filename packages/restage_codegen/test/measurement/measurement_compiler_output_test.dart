import 'package:build/build.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  test('default collection stamps the executable finite policy revision', () {
    expect(
      MeasurementCompilerPolicyInput.fromBuilderOptions(BuilderOptions.empty)
          .collectionBudgetRevisionId
          .value,
      'restage.collection-budget.v3',
    );
    expect(
      kMeasurementDefaultPrivacyPolicyRevisionId,
      'restage.manifest-privacy.v2',
    );
  });
  test('unset builder options stamp the shipped policy', () {
    expect(
      MeasurementCompilerPolicyInput.fromBuilderOptions(
        BuilderOptions.empty,
      ).toJson(),
      <String, Object?>{
        'collectionBudgetRevisionId':
            kMeasurementDefaultCollectionBudgetRevisionId,
        'minimumMeasurementClient': kMeasurementDefaultMinimumClient,
        'privacyPolicyRevisionId': kMeasurementDefaultPrivacyPolicyRevisionId,
      },
    );
  });

  test('explicit builder options win over the shipped policy', () {
    final policy = MeasurementCompilerPolicyInput.fromBuilderOptions(
      const BuilderOptions({
        kMeasurementMinimumClientOption: 2,
        kMeasurementPrivacyPolicyRevisionOption: 'privacy.accepted-v1',
        kMeasurementCollectionBudgetRevisionOption: 'budget.accepted-v1',
      }),
    );
    expect(policy.minimumMeasurementClient, 2);
    expect(policy.privacyPolicyRevisionId.value, 'privacy.accepted-v1');
    expect(policy.collectionBudgetRevisionId.value, 'budget.accepted-v1');
  });

  test('a partial override is refused rather than half-stamped', () {
    expect(
      () => MeasurementCompilerPolicyInput.fromBuilderOptions(
        const BuilderOptions({
          kMeasurementMinimumClientOption: 1,
        }),
      ),
      throwsFormatException,
    );
  });

  test('compiler state is strict, canonical, and rejects invalid authority',
      () {
    final output = RestageMeasurementCompilerOutputV1(
      valid: true,
      errors: const [],
      policy: null,
      nextIdentitySequence: 4,
      ledgerNodes: [
        _node('2'),
        _node('1'),
      ],
      acceptedRelocations: const [],
      acceptedIntroductions: const [],
      proposals: const [],
      publications: const [],
    );

    expect(
      output.ledgerNodes.map((node) => node.codeIdentityId.value),
      ['code.auto.1', 'code.auto.2'],
    );
    expect(
      RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        output.canonicalBytes,
      ).canonicalBytes,
      orderedEquals(output.canonicalBytes),
    );
    final json = decodeCanonicalObject(output.canonicalBytes);
    expect(
      () => RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        CanonicalJsonCodec.encode({...json, 'unknown': true}),
      ),
      throwsFormatException,
    );
    expect(
      () => RestageMeasurementCompilerOutputV1(
        valid: false,
        errors: const [],
        policy: null,
        nextIdentitySequence: 1,
        ledgerNodes: const [],
        acceptedRelocations: const [],
        acceptedIntroductions: const [],
        proposals: const [],
        publications: const [],
      ),
      throwsArgumentError,
    );
  });
}

MeasurementCompilerLedgerNode _node(String suffix) =>
    MeasurementCompilerLedgerNode(
      structuralOccurrenceKey: 'locator.$suffix',
      parentStructuralOccurrenceKey: null,
      reconciliationFingerprint: 'fingerprint.$suffix',
      codeIdentityId: CodeIdentityId('code.auto.$suffix'),
      canonicalNodeTokenId: NodeTokenId('node.auto.$suffix'),
      active: true,
      events: [
        MeasurementCompilerLedgerEvent(
          resolvedEventLocator: 'event.$suffix',
          sourceEventIdentity: SourceEventIdentity('onPressed$suffix'),
          generatedReferenceId: GeneratedReferenceId('reference.auto.$suffix'),
          lineageId: PointLineageId('lineage.auto.$suffix'),
          dartSymbol: GeneratedDartSymbol('measurementPoint$suffix'),
          displayMetadataRef: DisplayMetadataRef('display.auto.$suffix'),
          active: true,
        ),
      ],
    );
