/// Reusable curation building blocks for `restage.core` widgets.
///
/// Constants here factor out patterns that recur across multiple
/// curation entries — shared decomposition recipes, common
/// `PropertyOverride` shapes, and overlapping `excludeParams` lists.
/// The intent is to keep the canonical-form decision in one place so
/// adding a sibling widget (e.g. extending `kTextStyleSynthetics` to
/// a new `TextStyle`-consuming entry) is a one-line addition rather
/// than a verbatim copy.
library;

import 'package:restage_shared/restage_shared.dart';

// Wire identity on the catalog entries below uses the per-kind
// sentinel `WireId.unallocatedXxx`. The build-time allocator replaces
// sentinels with stable wire IDs from the per-library event log; once
// the build completes no sentinel survives in emitted artifacts.

// ---------------------------------------------------------------------------
// Decomposition recipes
// ---------------------------------------------------------------------------

/// Flat properties hoisted out of `style: TextStyle?` for widgets that
/// surface typography control (`Text`, `DefaultTextStyle`).
const List<PropertyEntry> kTextStyleSynthetics = [
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'inherit',
    type: PropertyType.boolean,
    description: 'Whether unset text style values inherit from the parent.',
    defaultSource: LiteralDefault(true),
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'color',
    type: PropertyType.color,
    description: 'Text color.',
    defaultBrandToken: 'onBackground',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'backgroundColor',
    type: PropertyType.color,
    description: 'Text background color.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'fontFamily',
    type: PropertyType.string,
    description: 'Primary font family.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'fontSize',
    type: PropertyType.length,
    description: 'Font size in logical pixels.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'fontWeight',
    type: PropertyType.fontWeight,
    description: 'Font weight.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'fontStyle',
    type: PropertyType.enumValue,
    description: 'Font posture.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'letterSpacing',
    type: PropertyType.length,
    description: 'Horizontal spacing between text glyphs.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'wordSpacing',
    type: PropertyType.length,
    description: 'Horizontal spacing between words.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'textBaseline',
    type: PropertyType.enumValue,
    description: 'Baseline used to align text.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'height',
    type: PropertyType.length,
    description: 'Text line height multiplier.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'leadingDistribution',
    type: PropertyType.enumValue,
    description: 'How leading is distributed above and below text.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'locale',
    type: PropertyType.locale,
    description: 'Locale used for font selection.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'foreground',
    type: PropertyType.paint,
    description: 'Paint used to draw text glyphs.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'background',
    type: PropertyType.paint,
    description: 'Paint used behind text glyphs.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'shadows',
    type: PropertyType.shadowList,
    description: 'Shadows painted beneath text glyphs.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'fontFeatures',
    type: PropertyType.fontFeatureList,
    description: 'OpenType font features.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'fontVariations',
    type: PropertyType.fontVariationList,
    description: 'OpenType font variation axis values.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'decoration',
    type: PropertyType.textDecoration,
    description: 'Text decoration lines.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'decorationColor',
    type: PropertyType.color,
    description: 'Text decoration color.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'decorationStyle',
    type: PropertyType.enumValue,
    description: 'Text decoration stroke style.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'decorationThickness',
    type: PropertyType.length,
    description: 'Text decoration stroke thickness.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'debugLabel',
    type: PropertyType.string,
    description: 'Debug label for this text style.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'fontFamilyFallback',
    type: PropertyType.stringList,
    description: 'Fallback font families.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'fontPackage',
    type: PropertyType.string,
    description: 'Package that contains the custom font family.',
    valueShape: ScalarShape(
      propertyType: PropertyType.string,
      dartTypeRef: DartTypeRef(libraryUri: 'dart:core', symbolName: 'String'),
    ),
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'overflow',
    type: PropertyType.enumValue,
    description: 'Text overflow behavior.',
    valueShape: EnumShape(
      propertyType: PropertyType.enumValue,
      enumRef: DartTypeRef(
        libraryUri: 'package:flutter/src/painting/text_painter.dart',
        symbolName: 'TextOverflow',
      ),
    ),
  ),
];

/// Native v4 curation for `style: TextStyle?` hoisting.
const NativeDecompositionCuration kTextStyleNativeDecompose =
    NativeDecompositionCuration(
  structuredType: 'TextStyle',
  targetArg: 'style',
  construction: NativeFactoryCuration.constructor(),
  fieldMappings: [
    NativeFieldMappingCuration(field: 'inherit', property: 'inherit'),
    NativeFieldMappingCuration(field: 'color', property: 'color'),
    NativeFieldMappingCuration(
      field: 'backgroundColor',
      property: 'backgroundColor',
    ),
    NativeFieldMappingCuration(field: 'fontFamily', property: 'fontFamily'),
    NativeFieldMappingCuration(field: 'fontSize', property: 'fontSize'),
    NativeFieldMappingCuration(field: 'fontWeight', property: 'fontWeight'),
    NativeFieldMappingCuration(field: 'fontStyle', property: 'fontStyle'),
    NativeFieldMappingCuration(
      field: 'letterSpacing',
      property: 'letterSpacing',
    ),
    NativeFieldMappingCuration(field: 'wordSpacing', property: 'wordSpacing'),
    NativeFieldMappingCuration(
      field: 'textBaseline',
      property: 'textBaseline',
    ),
    NativeFieldMappingCuration(field: 'height', property: 'height'),
    NativeFieldMappingCuration(
      field: 'leadingDistribution',
      property: 'leadingDistribution',
    ),
    NativeFieldMappingCuration(field: 'locale', property: 'locale'),
    NativeFieldMappingCuration(field: 'foreground', property: 'foreground'),
    NativeFieldMappingCuration(field: 'background', property: 'background'),
    NativeFieldMappingCuration(
      field: 'shadows',
      property: 'shadows',
      transform: NativeValueTransformCuration.projectList(
        itemTransform: NativeValueTransformCuration.identity(),
      ),
    ),
    NativeFieldMappingCuration(
      field: 'fontFeatures',
      property: 'fontFeatures',
      transform: NativeValueTransformCuration.projectList(
        itemTransform: NativeValueTransformCuration.identity(),
      ),
    ),
    NativeFieldMappingCuration(
      field: 'fontVariations',
      property: 'fontVariations',
      transform: NativeValueTransformCuration.projectList(
        itemTransform: NativeValueTransformCuration.identity(),
      ),
    ),
    NativeFieldMappingCuration(field: 'decoration', property: 'decoration'),
    NativeFieldMappingCuration(
      field: 'decorationColor',
      property: 'decorationColor',
    ),
    NativeFieldMappingCuration(
      field: 'decorationStyle',
      property: 'decorationStyle',
    ),
    NativeFieldMappingCuration(
      field: 'decorationThickness',
      property: 'decorationThickness',
    ),
    NativeFieldMappingCuration(field: 'debugLabel', property: 'debugLabel'),
    NativeFieldMappingCuration(
      field: 'fontFamilyFallback',
      property: 'fontFamilyFallback',
      transform: NativeValueTransformCuration.projectList(
        itemTransform: NativeValueTransformCuration.identity(),
      ),
    ),
    NativeFieldMappingCuration(field: 'overflow', property: 'overflow'),
  ],
  parameterMappings: [
    NativeParameterMappingCuration(
      parameter: 'package',
      property: 'fontPackage',
    ),
  ],
);

/// Single-real catalog property surfacing a uniform-corner radius. The
/// codegen wraps the scalar back as `BorderRadius.circular(<value>)` at
/// emission time via the `borderRadiusCircular` synthetic strategy, so
/// the same flat slot drives both direct ctor args
/// (`ClipRRect.borderRadius`) and recipe-hoisted inner args
/// (`BoxDecoration.borderRadius`).
///
/// When paired with the [kBorderRadiusPerCornerSynthetics] corner reals
/// (see below), the codegen instead emits a per-corner conditional:
/// any corner present on the wire reconstructs `BorderRadius.only(...)`
/// (each omitted corner defaulting to `Radius.zero`), falling through to
/// this uniform `BorderRadius.circular(...)` path when no corner is set —
/// never both. The corner-source recognition (lowering `BorderRadius.only`
/// authoring to these wire slots) is a separate, later concern; the
/// reconstruction half is unconditional.
const PropertyEntry kBorderRadiusCircularSynthetic = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'borderRadius',
  type: PropertyType.real,
  description: 'Uniform corner radius applied to all four corners.',
  synthetic: 'borderRadiusCircular',
);

/// The four per-corner radius reals consumed by the sibling
/// [kBorderRadiusCircularSynthetic] property's per-corner reconstruction.
/// Each is a single `real` carrying the `borderRadiusCorner` synthetic
/// strategy and is NEVER emitted as an independent ctor arg — the codegen
/// reads all four together to build `BorderRadius.only(...)`. Only the
/// corners actually set by an author emit onto the wire; an omitted corner
/// is absent and reconstructs to `Radius.zero`.
///
/// Names are prefixed (`borderRadius<Corner>`) to group with the uniform
/// `borderRadius` slot and avoid collision with any widget's own
/// flat properties.
const List<PropertyEntry> kBorderRadiusPerCornerSynthetics = [
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'borderRadiusTopLeft',
    type: PropertyType.real,
    description: 'Top-left corner radius (Radius.circular).',
    synthetic: 'borderRadiusCorner',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'borderRadiusTopRight',
    type: PropertyType.real,
    description: 'Top-right corner radius (Radius.circular).',
    synthetic: 'borderRadiusCorner',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'borderRadiusBottomLeft',
    type: PropertyType.real,
    description: 'Bottom-left corner radius (Radius.circular).',
    synthetic: 'borderRadiusCorner',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'borderRadiusBottomRight',
    type: PropertyType.real,
    description: 'Bottom-right corner radius (Radius.circular).',
    synthetic: 'borderRadiusCorner',
  ),
];

const NativeValueTransformCuration _kBorderRadiusCircularTransform =
    NativeValueTransformCuration.constructVariant(
  resultStructuredType: 'BorderRadius',
  invocation: NativeFactoryCuration.constructor(namedConstructor: 'circular'),
  argumentBindings: [
    NativeTransformArgumentBindingCuration(
      parameter: '0',
      source: TransformArgumentSource.propertyValue,
      nullPolicy: TransformNullPolicy.nullResult,
      missingPolicy: TransformMissingPolicy.nullResult,
    ),
  ],
);

/// Native v4 curation for `decoration: BoxDecoration?` hoisting.
const NativeDecompositionCuration kBoxDecorationNativeDecompose =
    NativeDecompositionCuration(
  structuredType: 'BoxDecoration',
  targetArg: 'decoration',
  construction: NativeFactoryCuration.constructor(),
  fieldMappings: [
    NativeFieldMappingCuration(field: 'color', property: 'color'),
    NativeFieldMappingCuration(field: 'gradient', property: 'gradient'),
    NativeFieldMappingCuration(field: 'image', property: 'decorationImage'),
    NativeFieldMappingCuration(field: 'border', property: 'border'),
    NativeFieldMappingCuration(
      field: 'borderRadius',
      property: 'borderRadius',
      transform: _kBorderRadiusCircularTransform,
    ),
    NativeFieldMappingCuration(
      field: 'boxShadow',
      property: 'boxShadow',
      transform: NativeValueTransformCuration.projectList(
        itemTransform: NativeValueTransformCuration.identity(),
      ),
    ),
    NativeFieldMappingCuration(field: 'shape', property: 'shape'),
  ],
);

/// Native v4 curation for the narrow `DecoratedBox` color-only surface.
const NativeDecompositionCuration kBoxDecorationColorNativeDecompose =
    NativeDecompositionCuration(
  structuredType: 'BoxDecoration',
  targetArg: 'decoration',
  construction: NativeFactoryCuration.constructor(),
  fieldMappings: [
    NativeFieldMappingCuration(field: 'color', property: 'color'),
  ],
);

/// Flat `gradient` slot consumed by BoxDecoration native decomposition. The wire
/// format is the rfw gradient map (`{type: 'linear', begin: {x, y},
/// end: {x, y}, colors: [...], stops: [...]?}`); the SDK reconstructs
/// via `ArgumentDecoders.gradient(source, path)` at runtime.
const PropertyEntry kGradientSynthetic = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'gradient',
  type: PropertyType.gradient,
  description: 'Gradient painted behind the child '
      '(LinearGradient supported; other shapes deferred).',
);

/// Flat `decorationImage` slot consumed by BoxDecoration native decomposition.
/// The wire format is the self-describing image map (`{image: {kind, src},
/// fit?, alignment?, repeat?, opacity?, scale?}`); the SDK reconstructs a real
/// `DecorationImage` via `RestageDecoders.decorationImage(source, path)` at
/// runtime. The translator handles `DecorationImage(image: NetworkImage(...) |
/// AssetImage(...), ...)`; other providers / unsupported fields defer loud.
const PropertyEntry kDecorationImageSynthetic = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'decorationImage',
  type: PropertyType.decorationImage,
  description: 'Background image painted behind the child '
      '(NetworkImage / AssetImage supported).',
  // A bespoke complex-map value (like the inline-span slot): the structure
  // lives in the runtime decoder, not a walked structured type, so the shape
  // is a `ScalarShape` carrying the `decorationImage` discriminator. Authored
  // explicitly because `DecorationImage` is not a structurally-walkable
  // catalog type — both the `image` decompose field and this synthetic resolve
  // to this same shape, satisfying the identity-transform cross-ref gate.
  valueShape: ScalarShape(
    propertyType: PropertyType.decorationImage,
    dartTypeRef: DartTypeRef(
      libraryUri: 'package:flutter/src/painting/decoration_image.dart',
      symbolName: 'DecorationImage',
    ),
  ),
);

/// Flat `border` slot consumed by BoxDecoration native decomposition. The wire
/// format is the rfw border list (`[<sideMap>, ...]` — up to four
/// entries in start/top/end/bottom order); the SDK reconstructs via
/// `ArgumentDecoders.border(source, path)` at runtime. The translator
/// handles `Border.all(color, width)` and the per-side default ctor.
const PropertyEntry kBorderSynthetic = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'border',
  type: PropertyType.border,
  description: 'Box border, uniform via Border.all or per-side via '
      'the default Border ctor.',
);

/// Flat `boxShadow` slot consumed by BoxDecoration native decomposition. The wire
/// format is a list of rfw shadow maps (`[{color, offset: {x, y},
/// blurRadius, spreadRadius}, ...]`); the SDK reconstructs via
/// `ArgumentDecoders.list<BoxShadow>` paired with the per-element
/// `boxShadow` decoder at runtime.
const PropertyEntry kBoxShadowSynthetic = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'boxShadow',
  type: PropertyType.boxShadowList,
  description: 'List of shadows painted behind the box.',
);

/// Flat `shape` slot consumed by BoxDecoration native decomposition. Surfaces the
/// `BoxShape` enum (`rectangle` / `circle`) so authors can write
/// `Container(decoration: BoxDecoration(shape: BoxShape.circle, ...))`.
/// Defaults to `rectangle` (Flutter's own default) when the blob omits
/// the key — the factory emitter renders the fallback as
/// `BoxShape.rectangle` so the non-nullable Flutter ctor parameter is
/// always satisfied.
const PropertyEntry kBoxDecorationShapeSynthetic = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'shape',
  type: PropertyType.enumValue,
  enumType: 'BoxShape',
  defaultSource: LiteralDefault('rectangle'),
  description: 'BoxDecoration shape (rectangle or circle).',
);

/// Full set of flat synthetics hoisted out of `BoxDecoration` onto consuming
/// widgets. Keep this list in sync with [kBoxDecorationNativeDecompose].
const List<PropertyEntry> kBoxDecorationSynthetics = [
  kBorderRadiusCircularSynthetic,
  ...kBorderRadiusPerCornerSynthetics,
  kGradientSynthetic,
  kBorderSynthetic,
  kBoxShadowSynthetic,
  kBoxDecorationShapeSynthetic,
  // Appended last so it draws the next free wire ID without shifting the
  // existing per-widget allocations (append-only, zero rebinds).
  kDecorationImageSynthetic,
];

/// Flat scalars hoisted out of `constraints: BoxConstraints?` onto consuming
/// widgets (`Container`, `AnimatedContainer`). Each maps one BoxConstraints
/// ctor field to a flat `real` slot. Only the fields the author explicitly
/// sets emit onto the wire — an absent slot lets the Flutter ctor default
/// (`0.0` for the minimums, `double.infinity` for the maximums) apply at
/// reconstruction, so an unbounded maximum is never written as a literal.
/// Named to avoid colliding with the widget's own flat `width` / `height`.
const List<PropertyEntry> kBoxConstraintsSynthetics = [
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'minWidth',
    type: PropertyType.real,
    description: 'Minimum width the box may have.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'maxWidth',
    type: PropertyType.real,
    description: 'Maximum width the box may have.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'minHeight',
    type: PropertyType.real,
    description: 'Minimum height the box may have.',
  ),
  PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: 'maxHeight',
    type: PropertyType.real,
    description: 'Maximum height the box may have.',
  ),
];

/// Native v4 curation for `constraints: BoxConstraints?` hoisting. Keep the
/// field set in sync with [kBoxConstraintsSynthetics]. Only the default
/// `BoxConstraints(...)` constructor decomposes; the named factory ctors
/// (`.expand` / `.tight` / `.tightFor` / `.loose`) are out of scope.
const NativeDecompositionCuration kBoxConstraintsNativeDecompose =
    NativeDecompositionCuration(
  structuredType: 'BoxConstraints',
  targetArg: 'constraints',
  construction: NativeFactoryCuration.constructor(),
  fieldMappings: [
    NativeFieldMappingCuration(field: 'minWidth', property: 'minWidth'),
    NativeFieldMappingCuration(field: 'maxWidth', property: 'maxWidth'),
    NativeFieldMappingCuration(field: 'minHeight', property: 'minHeight'),
    NativeFieldMappingCuration(field: 'maxHeight', property: 'maxHeight'),
  ],
);

// ---------------------------------------------------------------------------
// Property overrides
// ---------------------------------------------------------------------------

/// `AlignmentGeometry alignment = Alignment.center` defaults to a
/// const identifier the reflector can't decode as a primitive literal.
/// This override pins the catalog default to the member name; the
/// codegen renders the fallback as `AlignmentDirectional.center`.
///
/// Shared by `Align`, `FittedBox`, and `Transform.rotate` — every
/// curated widget whose Flutter ctor default is `Alignment.center`.
const PropertyOverride kAlignmentCenterOverride = PropertyOverride(
  defaultValue: 'center',
);

/// Flutter's implicit-animation widgets default `curve` to `Curves.linear`.
/// The reflector cannot recover that member mechanically because `Curves` is
/// a static holder class, not the value's declaring type.
const PropertyOverride kCurveLinearOverride = PropertyOverride(
  type: PropertyType.curve,
  defaultValue: 'linear',
);

/// As [kCurveLinearOverride], but for a `curve` parameter whose ctor default is
/// `Curves.easeOut` — likewise unrecoverable mechanically from the `Curves`
/// holder class.
const PropertyOverride kCurveEaseOutOverride = PropertyOverride(
  type: PropertyType.curve,
  defaultValue: 'easeOut',
);

/// As [kCurveLinearOverride], but for a `curve` parameter whose ctor default is
/// `Curves.easeInOut`.
const PropertyOverride kCurveEaseInOutOverride = PropertyOverride(
  type: PropertyType.curve,
  defaultValue: 'easeInOut',
);

/// `AnimatedSlide.offset` is a `required Offset` with no Flutter ctor default.
/// The catalog records a defensive `Offset.zero` default — codegen renders the
/// fallback as `Offset.zero`, applied only when the slot is absent on the wire.
/// The parameter stays required, so Dart's own required-parameter check
/// enforces authored intent on the source; an absent offset is never a silent
/// zero slide.
const PropertyOverride kOffsetZeroOverride = PropertyOverride(
  type: PropertyType.offset,
  defaultValue: 'zero',
);

// ---------------------------------------------------------------------------
// Excludes
// ---------------------------------------------------------------------------

/// `Row` / `Column` strip directional knobs the catalog surface doesn't
/// need. Authors set semantic alignment via `mainAxisAlignment` /
/// `crossAxisAlignment` instead.
///
/// `textBaseline` is excluded via the centralized type denylist
/// (`TextBaseline`). `textDirection` and `verticalDirection` are excluded
/// here explicitly — their types are enum-valued and are legitimately
/// surfaced by `Wrap`, so they cannot be added to the global denylist.
///
/// `spacing` is surfaced — the modern Flex gap idiom, a `length`/`real`
/// slot reusing the existing decoder (`Wrap` already surfaces it).
const List<String> kFlexExcludes = [
  'textDirection',
  'verticalDirection',
];

/// Structural / imperative knobs that `Container` and
/// `AnimatedContainer` both strip from reflector inference.
///
/// `constraints` (`BoxConstraints`) is surfaced via the flat-scalar
/// decompose recipe (its min/max fields hoist onto flat real slots), not
/// excluded. `transform` (`Matrix4`) is excluded via the centralized type
/// denylist. `transformAlignment` is `AlignmentGeometry` (a geometry-base
/// type the catalog flat-walks) and is the only remaining widget-specific
/// design exclusion here.
///
/// `clipBehavior` (the `Clip` enum) is surfaced — a serializable enum
/// reusing the existing enum decoder, consistent with the other clip
/// widgets (`ClipRect` / `ClipRRect` / `Stack`).
///
/// `decoration` and `foregroundDecoration` (both `Decoration?`) flow
/// through the structured walker as abstract-base placeholders; the
/// recipe + synthetics still hoist the BoxDecoration inner args onto
/// flat properties at translation time.
const List<String> kContainerCoreExcludes = [
  'transformAlignment',
];

/// Imperative / restoration knobs shared by `ListView` and
/// `SingleChildScrollView`. Keep only the declarative subset
/// (`scrollDirection` / `reverse` / `padding` / `shrinkWrap` /
/// `keyboardDismissBehavior` on `ListView` / `child` or `children`).
///
/// `cacheExtent` lives only on `ListView` (viewport-based) — added
/// per-entry there rather than here.
///
/// `controller` (`ScrollController`), `dragStartBehavior`
/// (`DragStartBehavior`), `hitTestBehavior` (`HitTestBehavior`), and
/// `physics` (`ScrollPhysics`) are excluded via the centralized type
/// denylist. `keyboardDismissBehavior`
/// (`ScrollViewKeyboardDismissBehavior`) is a clean 2-member enum, so it
/// is surfaced, not excluded. `clipBehavior` (the `Clip` enum) is likewise
/// surfaced, consistent with the other clip-capable widgets. The two
/// remaining entries are widget-specific design exclusions.
const List<String> kScrollableImperativeExcludes = [
  'primary',
  'restorationId',
];

/// Visual-modifier and async-loader knobs stripped from every
/// `Image` named-constructor variant the catalog surfaces
/// (`Image.network`, `Image.asset`). Variant-specific extras
/// (`headers` / `webHtmlElementStrategy` on network; `bundle` /
/// `package` on asset) are added per-entry.
///
/// `color` / `colorBlendMode` / `alignment` / `repeat` / `filterQuality`
/// are surfaced — serializable visual modifiers reusing the existing
/// color / enum / alignment decoders. The remaining entries stay
/// excluded: `opacity` (`Animation<double>`), the frame/error builders,
/// `scale`, `cacheWidth`/`cacheHeight`, `centerSlice`, and the niche
/// semantics / playback toggles (non-serializable or out of scope).
const List<String> kImageVisualExcludes = [
  'frameBuilder',
  'errorBuilder',
  'excludeFromSemantics',
  'scale',
  'opacity',
  'centerSlice',
  'matchTextDirection',
  'gaplessPlayback',
  'isAntiAlias',
  'cacheWidth',
  'cacheHeight',
];

/// Opt-outs shared by `AnimatedScale` and `AnimatedRotation` — the two
/// implicit transform animations whose surface is a single scalar
/// (`scale` / `turns`) plus the shared implicit-animation controls over a
/// child.
///
/// - `filterQuality` is a render-quality knob the catalog treats as noise
///   (matching the `Image` variants).
const List<String> kScaleRotationExcludes = [
  'filterQuality',
];

/// `AnimatedScale.alignment` / `AnimatedRotation.alignment` are typed as the
/// concrete `Alignment` subtype. Route them through the `alignmentXY` decoder
/// while preserving Flutter's documented `Alignment.center` default.
const Map<String, PropertyOverride> kScaleRotationAlignmentOverride = {
  'alignment': PropertyOverride(
    type: PropertyType.alignmentXY,
    defaultValue: 'center',
  ),
};

/// `Image.alignment` (both `Image.network` and `Image.asset`) is typed
/// `AlignmentGeometry` with an `Alignment.center` default. Route it through
/// the `alignmentXY` decoder so a concrete `Alignment.<member>` source lowers
/// to the `{x, y}` map — the plain `alignment` slot only carries the
/// const-default member name, not a source value. Mirrors
/// [kScaleRotationAlignmentOverride].
const Map<String, PropertyOverride> kImageAlignmentOverride = {
  'alignment': PropertyOverride(
    type: PropertyType.alignmentXY,
    defaultValue: 'center',
  ),
};

/// `width` / `height` length-type overrides. Reused everywhere these
/// two appear together — `Container`, `AnimatedContainer`, `SizedBox`,
/// `FadeInImage`, the two `Image` variants. The codegen treats
/// `length` and `real` identically; the override is editor-side
/// cosmetic (logical-pixel scrubber + units suffix).
const Map<String, PropertyOverride> kWidthHeightLengthOverrides = {
  'width': PropertyOverride(type: PropertyType.length),
  'height': PropertyOverride(type: PropertyType.length),
};
