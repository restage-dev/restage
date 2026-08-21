// Internal publication-line identity adapter.

import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

/// Derives the stable Measurement surface from the exact publication line.
SurfaceId measurementSurfaceIdForPublicationV1(
  SurfacePublication publication,
) =>
    measurementSurfaceIdForSelectorV1(
      MeasurementPublicationSelectorV1.fromPublication(publication),
    );

/// Derives the same byte-frozen surface publication line identity from a target-neutral selector.
SurfaceId measurementSurfaceIdForSelectorV1(
  MeasurementPublicationSelectorV1 selector,
) =>
    selector.stableSurfaceId;
