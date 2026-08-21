import 'dart:io';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  test('imports canonical measurement schema contracts', () {
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

  // The build-time toolchain compiles measurement points; it never evaluates
  // them. The inference, evidence and result vocabulary therefore stays out of
  // this package's reach, asserted over the barrel's source because naming
  // those types here is exactly what must remain impossible.
  test('does not reach the platform inference vocabulary', () {
    expect(
      _measurementDependencies(File('pubspec.yaml').readAsStringSync()),
      ['restage_measurement_schema'],
      reason: 'the toolchain takes the public measurement schema, nothing else',
    );

    final schemaBarrel = File(
      '../restage_measurement_schema/lib/restage_measurement_schema.dart',
    ).readAsStringSync();
    for (final source in _fencedSources) {
      expect(
        schemaBarrel,
        isNot(contains("export 'src/$source';")),
        reason: '$source is platform-internal and must stay out of reach',
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
