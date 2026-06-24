/// Reusable native decomposition metadata for `restage.material` widgets.
///
/// Material's seven curated buttons all flatten a `ButtonStyle` surface,
/// but they hoist different subsets of fields onto their flat property
/// surface depending on the variant:
///
/// * Filled buttons with a shadow (`ElevatedButton`, `FilledButton`) take
///   `backgroundColor`, `foregroundColor`, `padding`, `elevation`, and the
///   supported `ShapeBorder` surface.
/// * The flat M3 tonal variant (`FilledButton.tonal`) has no shadow, so
///   it takes `backgroundColor`, `foregroundColor`, `padding`, and `shape`.
/// * Transparent-surface buttons (`OutlinedButton`(`.icon`),
///   `TextButton`(`.icon`)) have no fill, so they take `foregroundColor`,
///   `padding`, and `shape`.
///
/// All variants build their `style` via `<Button>.styleFrom(...)` instead of
/// a raw `ButtonStyle(...)` constructor, which would need
/// `WidgetStateProperty<T>` wrappers around the same plain values.
///
/// Wire identity on the structured ref uses the per-kind sentinel
/// `WireId.unallocatedStructured`. The build-time allocator replaces
/// sentinels with stable wire IDs from the per-library event log; once
/// the build completes no sentinel survives in emitted artifacts.
library;

import 'package:restage_shared/restage_shared.dart';

/// `ButtonStyle` metadata for filled buttons that take a shadow
/// (`ElevatedButton`, `FilledButton`). Hoists `backgroundColor`,
/// `foregroundColor`, `padding`, `elevation`, `shape`, the size
/// constraints (`minimumSize`, `fixedSize`), and the border `side`.
const NativeDecompositionCuration kFilledButtonStyleNativeDecompose =
    NativeDecompositionCuration(
  structuredType: 'ButtonStyle',
  targetArg: 'style',
  construction: NativeFactoryCuration.owningWidgetStatic('styleFrom'),
  fieldMappings: [
    NativeFieldMappingCuration(
      field: 'backgroundColor',
      property: 'backgroundColor',
    ),
    NativeFieldMappingCuration(
      field: 'foregroundColor',
      property: 'foregroundColor',
    ),
    NativeFieldMappingCuration(field: 'padding', property: 'padding'),
    NativeFieldMappingCuration(field: 'elevation', property: 'elevation'),
    NativeFieldMappingCuration(
      field: 'shape',
      property: 'shape',
    ),
    NativeFieldMappingCuration(field: 'minimumSize', property: 'minimumSize'),
    NativeFieldMappingCuration(field: 'fixedSize', property: 'fixedSize'),
    NativeFieldMappingCuration(field: 'side', property: 'side'),
    NativeFieldMappingCuration(field: 'textStyle', property: 'textStyle'),
  ],
);

/// `ButtonStyle` metadata for the flat M3 tonal variant
/// (`FilledButton.tonal`). Hoists `backgroundColor`, `foregroundColor`,
/// `padding`, `shape`, the size constraints, and the border `side` — no
/// `elevation` since the surface is shadowless.
const NativeDecompositionCuration kTonalButtonStyleNativeDecompose =
    NativeDecompositionCuration(
  structuredType: 'ButtonStyle',
  targetArg: 'style',
  construction: NativeFactoryCuration.owningWidgetStatic('styleFrom'),
  fieldMappings: [
    NativeFieldMappingCuration(
      field: 'backgroundColor',
      property: 'backgroundColor',
    ),
    NativeFieldMappingCuration(
      field: 'foregroundColor',
      property: 'foregroundColor',
    ),
    NativeFieldMappingCuration(field: 'padding', property: 'padding'),
    NativeFieldMappingCuration(field: 'shape', property: 'shape'),
    NativeFieldMappingCuration(field: 'minimumSize', property: 'minimumSize'),
    NativeFieldMappingCuration(field: 'fixedSize', property: 'fixedSize'),
    NativeFieldMappingCuration(field: 'side', property: 'side'),
    NativeFieldMappingCuration(field: 'textStyle', property: 'textStyle'),
  ],
);

/// `ButtonStyle` metadata for transparent-surface buttons
/// (`OutlinedButton`(`.icon`), `TextButton`(`.icon`)). Hoists
/// `foregroundColor`, `padding`, `shape`, the size constraints, and the
/// border `side` — no fill, no shadow.
const NativeDecompositionCuration kTransparentButtonStyleNativeDecompose =
    NativeDecompositionCuration(
  structuredType: 'ButtonStyle',
  targetArg: 'style',
  construction: NativeFactoryCuration.owningWidgetStatic('styleFrom'),
  fieldMappings: [
    NativeFieldMappingCuration(
      field: 'foregroundColor',
      property: 'foregroundColor',
    ),
    NativeFieldMappingCuration(field: 'padding', property: 'padding'),
    NativeFieldMappingCuration(field: 'shape', property: 'shape'),
    NativeFieldMappingCuration(field: 'minimumSize', property: 'minimumSize'),
    NativeFieldMappingCuration(field: 'fixedSize', property: 'fixedSize'),
    NativeFieldMappingCuration(field: 'side', property: 'side'),
    NativeFieldMappingCuration(field: 'textStyle', property: 'textStyle'),
  ],
);
