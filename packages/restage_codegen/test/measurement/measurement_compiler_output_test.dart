import 'package:build/build.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  test('Measurement builder policy is all-or-nothing and build-owned', () {
    expect(
      MeasurementCompilerPolicyInput.fromBuilderOptions(
        BuilderOptions.empty,
      ),
      isNull,
    );
    expect(
      () => MeasurementCompilerPolicyInput.fromBuilderOptions(
        const BuilderOptions({
          kMeasurementMinimumClientOption: 1,
        }),
      ),
      throwsFormatException,
    );

    final policy = MeasurementCompilerPolicyInput.fromBuilderOptions(
      const BuilderOptions({
        kMeasurementMinimumClientOption: 2,
        kMeasurementPrivacyPolicyRevisionOption: 'privacy.accepted-v1',
        kMeasurementCollectionBudgetRevisionOption: 'budget.accepted-v1',
      }),
    );
    expect(policy, isNotNull);
    expect(policy!.minimumMeasurementClient, 2);
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
