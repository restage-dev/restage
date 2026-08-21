import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  test('exports canonical measurement schema contracts', () {
    final point = GeneratedPointReferenceV1(
      referenceId: GeneratedReferenceId('reference.checkout-button'),
      target: _target,
      surfaceRevisionId: SurfaceRevisionId('surface.checkout.v1'),
      artifactGraphHash: CanonicalDigest('a' * 64),
      occurrenceId: CanonicalDigest('b' * 64),
      lineageId: PointLineageId('lineage.checkout-button'),
      sourceEventIdentity: SourceEventIdentity('onPressed'),
      dartSymbol: GeneratedDartSymbol('checkoutButtonPressed'),
    );
    expect(
      GeneratedPointReferenceV1.fromCanonicalBytes(point.canonicalBytes),
      point,
    );
    expect(_publicationApiSymbols, hasLength(3));
  });

  // The inference, evidence and result vocabulary is platform-internal: the
  // control plane evaluates it, and it is deliberately outside this package's
  // namespace. Naming those types here is exactly what must stay impossible,
  // so the fence is asserted over the barrels' source rather than by
  // referencing the symbols.
  test('does not re-export the platform inference vocabulary', () {
    expect(
      _measurementDependencies(File('pubspec.yaml').readAsStringSync()),
      ['restage_measurement_schema'],
      reason: 'the SDK takes the public measurement schema and nothing else',
    );

    final schemaBarrel = File(
      '../restage_measurement_schema/lib/restage_measurement_schema.dart',
    ).readAsStringSync();
    for (final source in _fencedSources) {
      expect(
        schemaBarrel,
        isNot(contains("export 'src/$source';")),
        reason: '$source is platform-internal and must not be SDK-visible',
      );
    }
  });
}

/// Every measurement package this one depends on, in declaration order.
///
/// The list is asserted exactly rather than by name-matching a forbidden
/// package, so a future dependency on any other measurement package fails here
/// without this file having to name one.
List<String> _measurementDependencies(String pubspec) =>
    RegExp(r'^  ([a-z0-9_]+):', multiLine: true)
        .allMatches(pubspec)
        .map((match) => match.group(1)!)
        .where((name) => name.contains('measurement'))
        .toList();

/// Every source the public barrel must not export.
///
/// The list is the contract package's own fence, restated here so this
/// package fails if the barrel ever widens back over it: the inference
/// kernel and its validation, the result definitions, and the governed
/// policy, metric, layer and control-plane vocabulary the service owns.
const _fencedSources = <String>[
  'assignment_policy.dart',
  'bindings.dart',
  'compatibility_proof.dart',
  'dart_authoring.dart',
  'experiment_activation.dart',
  'inference.dart',
  'inference_validation.dart',
  'intent.dart',
  'layers.dart',
  'metrics.dart',
  'programmatic_mutation.dart',
  'projections.dart',
  'publication_finalizer.dart',
  'results.dart',
  'scopes.dart',
  'semantics.dart',
  'slots.dart',
  'sources.dart',
  'summary_policy.dart',
];

final _target = TargetCoordinate(
  organizationId: OrganizationId(11),
  appId: ApplicationId(23),
  environmentTargetId: EnvironmentTargetId(31),
  namedEnvironmentId: NamedEnvironmentId(37),
  runtimePlane: RuntimePlane.sandbox,
);

final List<Object> _publicationApiSymbols = [
  RegisteredPublicationAuthorityReferenceV1.new,
  MeasurementPublicationBindingReferenceV1.new,
  MeasurementPublicationBindingV1.new,
];
