import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  test('artifact metadata is nameable through the public barrel', () {
    expect(_metadataFor, isA<Function>());
  });
}

FlowExperimentArtifactMetadata _metadataFor(
  ServerFlowResolver resolver,
  ResolvedFlow flow,
) =>
    resolver.metadataFor(flow);
