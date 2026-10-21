// The Measurement index's unmeasured list is the shape push reads.

import 'dart:convert';
import 'dart:io';

import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

/// The fixture push reads the unmeasured list from.
const _cliFixturePath =
    '../restage_cli/test/_fixtures/unmeasured.measurement.index.json';

void main() {
  test('the index writes the unmeasured list push reads', () {
    final output = RestageMeasurementCompilerOutputV1(
      valid: true,
      errors: const [],
      policy: null,
      nextIdentitySequence: 1,
      ledgerNodes: const [],
      acceptedRelocations: const [],
      acceptedIntroductions: const [],
      proposals: const [],
      publications: const [],
      unmeasured: [
        MeasurementUnmeasuredPublication(
          selector: MeasurementPublicationSelectorV1(
            surface: Surface.paywall,
            slug: 'plus_paywall',
            sourceKind: SurfaceSourceKind.paywall,
          ),
          reason: 'A callback under a conditional combined with && or || is '
              'emitted more than once, so it cannot carry one route',
        ),
      ],
    );
    final bytes = utf8.decode(output.outputIndexBytes('fixture_package'));

    expect(bytes, File(_cliFixturePath).readAsStringSync());
  });
}
