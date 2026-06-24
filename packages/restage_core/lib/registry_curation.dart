/// Curation file for the `restage.core` widget library — cross-platform
/// Flutter widgets curated for paywall composition.
///
/// Authors specify only what cannot be derived from a Flutter widget's
/// constructor signature: the catalog [WidgetCategory], parameter
/// exclusions for params the catalog does not surface, brand-token
/// defaults, structured-type decomposition recipes, and per-property
/// overrides for renames or non-mechanical defaults. The reflector
/// fills in the rest by walking each constructor parameter (name, type,
/// dartdoc, required-flag, literal default).
///
/// **Decomposition recipe naming.** When a structured Flutter
/// constructor type (e.g. `TextStyle`, `ButtonStyle`, `BoxDecoration`)
/// is flattened to flat catalog properties:
///
/// - **Default: unprefixed.** The structured type's constructor argument
///   name is hoisted directly onto the widget's flat property surface —
///   `TextStyle(fontSize: ...)` becomes flat property `fontSize`.
/// - **Prefix when disambiguating.** If two structured types share an
///   argument name, or a structured-type argument collides with a flat
///   widget argument, prefix with the structured type's parameter name
///   plus `_`.
library;

import 'package:flutter/widgets.dart';
import 'package:restage_core/src/decomposition_recipes.dart';
import 'package:restage_core/src/widgets/restage_fade_in.dart';
import 'package:restage_core/src/widgets/restage_formatted_number.dart';
import 'package:restage_core/src/widgets/restage_motion.dart';
import 'package:restage_core/src/widgets/restage_pulse.dart';
import 'package:restage_core/src/widgets/restage_stagger.dart';
import 'package:restage_shared/restage_shared.dart';

/// Curation list consumed by `BuiltinCurationBuilder` to emit
/// `lib/registry.dart` and `lib/src/widget_catalog/catalog.json`.
@RestageBuiltinLibrary(library: WidgetLibrary.core, version: '0.1.0')
const List<BuiltinWidgetCuration> kCuration = [
  BuiltinWidgetCuration<Align>(
    category: WidgetCategory.layout,
    propertyOverrides: {
      'alignment': kAlignmentCenterOverride,
      'widthFactor': PropertyOverride(type: PropertyType.length),
      'heightFactor': PropertyOverride(type: PropertyType.length),
    },
  ),
  // The implicit-animation family below mirrors each widget's static
  // sibling — RFW renders these declaratively (the catalog surfaces the
  // target value plus shared animation controls; the framework tweens
  // between blob updates).
  BuiltinWidgetCuration<AnimatedAlign>(
    category: WidgetCategory.layout,
    fires: [WidgetEventName.onEnd],
    // Mirror `Align` — center default + length width/height factors.
    propertyOverrides: {
      'alignment': kAlignmentCenterOverride,
      'widthFactor': PropertyOverride(type: PropertyType.length),
      'heightFactor': PropertyOverride(type: PropertyType.length),
      'curve': kCurveLinearOverride,
    },
  ),
  BuiltinWidgetCuration<AnimatedContainer>(
    category: WidgetCategory.layout,
    fires: [WidgetEventName.onEnd],
    // Mirror `Container`'s structural exclusions.
    excludeParams: kContainerCoreExcludes,
    brandTokens: {'color': 'background'},
    propertyOverrides: {
      ...kWidthHeightLengthOverrides,
      'curve': kCurveLinearOverride,
    },
    synthetics: [...kBoxDecorationSynthetics, ...kBoxConstraintsSynthetics],
    nativeDecomposes: [
      kBoxDecorationNativeDecompose,
      kBoxConstraintsNativeDecompose,
    ],
  ),
  BuiltinWidgetCuration<AnimatedDefaultTextStyle>(
    category: WidgetCategory.decoration,
    fires: [WidgetEventName.onEnd],
    // Mirror `DefaultTextStyle` — the `style` slot is reassembled from the
    // shared TextStyle synthetics + recipe. `textHeightBehavior` is a
    // structured type the catalog doesn't surface today.
    excludeParams: ['textHeightBehavior'],
    propertyOverrides: {'curve': kCurveLinearOverride},
    synthetics: kTextStyleSynthetics,
    nativeDecomposes: [kTextStyleNativeDecompose],
  ),
  BuiltinWidgetCuration<AnimatedOpacity>(
    category: WidgetCategory.decoration,
    fires: [WidgetEventName.onEnd],
    // Mirror `Opacity` — a single `opacity` scalar over a child.
    propertyOverrides: {'curve': kCurveLinearOverride},
  ),
  BuiltinWidgetCuration<AnimatedPadding>(
    category: WidgetCategory.layout,
    fires: [WidgetEventName.onEnd],
    // Mirror `Padding` — `padding: EdgeInsetsGeometry` flat-walks to the
    // shared edge-inset surface.
    propertyOverrides: {'curve': kCurveLinearOverride},
  ),
  BuiltinWidgetCuration<AnimatedPositioned>(
    category: WidgetCategory.layout,
    fires: [WidgetEventName.onEnd],
    // Mirror `Positioned` — the six edge/size scalars as lengths. Like
    // `Positioned`, this must be a direct child of a `Stack`.
    propertyOverrides: {
      'left': PropertyOverride(type: PropertyType.length),
      'top': PropertyOverride(type: PropertyType.length),
      'right': PropertyOverride(type: PropertyType.length),
      'bottom': PropertyOverride(type: PropertyType.length),
      'width': PropertyOverride(type: PropertyType.length),
      'height': PropertyOverride(type: PropertyType.length),
      'curve': kCurveLinearOverride,
    },
  ),
  BuiltinWidgetCuration<AnimatedRotation>(
    category: WidgetCategory.decoration,
    fires: [WidgetEventName.onEnd],
    // `turns: double` (one turn = 360°) over a child. The remaining shared
    // opt-outs are documented on `kScaleRotationExcludes`.
    // The concrete-Alignment `alignment` slot routes through the shared
    // `alignmentXY` override.
    excludeParams: kScaleRotationExcludes,
    propertyOverrides: {
      ...kScaleRotationAlignmentOverride,
      'curve': kCurveLinearOverride,
    },
  ),
  BuiltinWidgetCuration<AnimatedScale>(
    category: WidgetCategory.decoration,
    fires: [WidgetEventName.onEnd],
    // `scale: double` over a child. Same remaining opt-outs as
    // `AnimatedRotation` — see `kScaleRotationExcludes`.
    excludeParams: kScaleRotationExcludes,
    propertyOverrides: {
      ...kScaleRotationAlignmentOverride,
      'curve': kCurveLinearOverride,
    },
  ),
  BuiltinWidgetCuration<AnimatedSize>(
    category: WidgetCategory.decoration,
    fires: [WidgetEventName.onEnd],
    propertyOverrides: {
      'alignment': kAlignmentCenterOverride,
      'curve': kCurveLinearOverride,
    },
  ),
  BuiltinWidgetCuration<AnimatedSlide>(
    category: WidgetCategory.decoration,
    fires: [WidgetEventName.onEnd],
    // `offset: Offset` — a fractional translation of the child — over a
    // child. The concrete-`Offset` slot routes through the `offset` decoder
    // with the defensive `Offset.zero` override (see `kOffsetZeroOverride`).
    propertyOverrides: {
      'offset': kOffsetZeroOverride,
      'curve': kCurveLinearOverride,
    },
  ),
  BuiltinWidgetCuration<AspectRatio>(category: WidgetCategory.layout),
  BuiltinWidgetCuration<BackdropFilter>(
    category: WidgetCategory.decoration,
    // `filter: ImageFilter` is built from the paired blur scalars via
    // the `imageFilterBlur` synthetic strategy in the codegen. Other
    // `ImageFilter` shapes (TileMode, dilate, erode, matrix, compose)
    // are not yet supported. `filterConfig` and
    // `backdropGroupKey` are recent additions for backdrop-group
    // composition — structured types out of scope for now.
    excludeParams: ['filter', 'filterConfig', 'backdropGroupKey'],
    synthetics: [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'blurSigmaX',
        type: PropertyType.real,
        description: 'Gaussian blur sigma along the X axis.',
        synthetic: 'imageFilterBlur',
      ),
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'blurSigmaY',
        type: PropertyType.real,
        description: 'Gaussian blur sigma along the Y axis.',
        synthetic: 'imageFilterBlur',
      ),
    ],
  ),
  BuiltinWidgetCuration<Center>(category: WidgetCategory.layout),
  BuiltinWidgetCuration<ClipOval>(
    category: WidgetCategory.decoration,
    // `clipper: CustomClipper<Rect>?` is an imperative-callback type
    // the declarative surface can't carry. Authors needing a custom
    // clip shape compose `ClipPath` (deferred).
    excludeParams: ['clipper'],
  ),
  BuiltinWidgetCuration<ClipRRect>(
    category: WidgetCategory.decoration,
    // The reflector can't decompose `borderRadius: BorderRadiusGeometry`
    // directly. The synthetic below surfaces a uniform-corner radius as
    // a single real and the codegen wraps the scalar back as
    // `BorderRadius.circular(...)` at the Flutter ctor call site.
    // `clipper: CustomClipper<RRect>?` stays excluded — it's an
    // imperative-callback type the declarative surface can't carry.
    excludeParams: ['clipper', 'borderRadius'],
    synthetics: [
      kBorderRadiusCircularSynthetic,
      ...kBorderRadiusPerCornerSynthetics,
    ],
  ),
  BuiltinWidgetCuration<ClipRect>(
    category: WidgetCategory.decoration,
    excludeParams: ['clipper'],
  ),
  BuiltinWidgetCuration<Column>(
    category: WidgetCategory.layout,
    excludeParams: kFlexExcludes,
  ),
  BuiltinWidgetCuration<Container>(
    category: WidgetCategory.layout,
    // `Container`'s ctor carries `isAntiAlias` on top of the shared
    // structural-decoration set.
    excludeParams: [...kContainerCoreExcludes, 'isAntiAlias'],
    brandTokens: {'color': 'background'},
    propertyOverrides: kWidthHeightLengthOverrides,
    synthetics: [...kBoxDecorationSynthetics, ...kBoxConstraintsSynthetics],
    nativeDecomposes: [
      kBoxDecorationNativeDecompose,
      kBoxConstraintsNativeDecompose,
    ],
  ),
  BuiltinWidgetCuration<DecoratedBox>(
    category: WidgetCategory.decoration,
    // `decoration: Decoration` is an abstract base routed through the
    // structured walker as a placeholder. Composition is driven by the
    // `color` synthetic below and the recipe that hoists the BoxDecoration
    // inner ctor args back onto flat properties at translation time.
    // Richer BoxDecoration shapes (gradient, border, borderRadius,
    // boxShadow, image, shape) land in a sibling milestone — see the
    // BoxConstraints follow-up for the same shape.
    synthetics: [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'color',
        type: PropertyType.color,
        description: 'Background color of the decoration.',
        defaultBrandToken: 'background',
      ),
    ],
    nativeDecomposes: [kBoxDecorationColorNativeDecompose],
  ),
  BuiltinWidgetCuration<DefaultTextStyle>(
    category: WidgetCategory.decoration,
    // `style` is reassembled from the shared TextStyle synthetics +
    // recipe — exclude the structured slot from the reflector's
    // direct-property walk. `textHeightBehavior` is a structured
    // type the catalog doesn't surface today.
    excludeParams: ['textHeightBehavior'],
    synthetics: kTextStyleSynthetics,
    nativeDecomposes: [kTextStyleNativeDecompose],
  ),
  BuiltinWidgetCuration<Expanded>(category: WidgetCategory.layout),
  BuiltinWidgetCuration<FadeInImage>(
    category: WidgetCategory.decoration,
    // The default `FadeInImage(placeholder: ImageProvider, image:
    // ImageProvider)` constructor needs an `ImageProvider`-from-String
    // wrap that the codegen doesn't currently emit. The `.assetNetwork`
    // named constructor takes two required `String`s — a local-asset
    // placeholder + a network image URL — matching real paywall
    // patterns (asset shimmer behind a CDN hero image) and threading
    // cleanly through the existing string-decoder surface. The catalog
    // name auto-derives to `FadeInImageAssetNetwork` so the two-string
    // signature is explicit at the call site. The exclude list diverges
    // from `kImageVisualExcludes` because FadeInImage's variant carries
    // `placeholder*` / `image*` split params instead of the plain
    // counterparts (`placeholderCacheWidth` not `cacheWidth`, etc.).
    constructorName: 'assetNetwork',
    excludeParams: [
      // `bundle: AssetBundle` is excluded via the centralized type denylist.
      // Fade curves stay out of the core image surface for now; Track B2 only
      // lifts curve support on the implicit-animation family.
      'placeholderErrorBuilder',
      'imageSemanticLabel',
      'imageErrorBuilder',
      'excludeFromSemantics',
      'fadeOutCurve',
      'fadeInCurve',
      'placeholderScale',
      'placeholderColor',
      'placeholderColorBlendMode',
      'color',
      'colorBlendMode',
      'fadeOutDuration',
      'fadeInDuration',
      'alignment',
      'repeat',
      'matchTextDirection',
      'filterQuality',
      'placeholderCacheWidth',
      'placeholderCacheHeight',
      'imageCacheWidth',
      'imageCacheHeight',
    ],
    propertyOverrides: kWidthHeightLengthOverrides,
  ),
  BuiltinWidgetCuration<FittedBox>(
    category: WidgetCategory.layout,
    propertyOverrides: {'alignment': kAlignmentCenterOverride},
  ),
  BuiltinWidgetCuration<Flexible>(category: WidgetCategory.layout),
  BuiltinWidgetCuration<FractionallySizedBox>(
    category: WidgetCategory.layout,
    propertyOverrides: {'alignment': kAlignmentCenterOverride},
  ),
  BuiltinWidgetCuration<GestureDetector>(
    category: WidgetCategory.input,
    // Three bare `VoidCallback?` gestures only — short tap, long-press,
    // and double-tap. Every other gesture family (pan / scale / drag /
    // secondary / tertiary / force / vertical / horizontal) carries
    // typed payloads that the catalog's event surface doesn't yet
    // serialise.
    excludeParams: [
      'onTapDown',
      'onTapUp',
      'onTapMove',
      'onTapCancel',
      'onSecondaryTap',
      'onSecondaryTapDown',
      'onSecondaryTapUp',
      'onSecondaryTapCancel',
      'onTertiaryTapDown',
      'onTertiaryTapUp',
      'onTertiaryTapCancel',
      'onDoubleTapDown',
      'onDoubleTapCancel',
      'onLongPressDown',
      'onLongPressCancel',
      'onLongPressStart',
      'onLongPressMoveUpdate',
      'onLongPressUp',
      'onLongPressEnd',
      'onSecondaryLongPress',
      'onSecondaryLongPressDown',
      'onSecondaryLongPressCancel',
      'onSecondaryLongPressStart',
      'onSecondaryLongPressMoveUpdate',
      'onSecondaryLongPressUp',
      'onSecondaryLongPressEnd',
      'onTertiaryLongPress',
      'onTertiaryLongPressDown',
      'onTertiaryLongPressCancel',
      'onTertiaryLongPressStart',
      'onTertiaryLongPressMoveUpdate',
      'onTertiaryLongPressUp',
      'onTertiaryLongPressEnd',
      'onVerticalDragDown',
      'onVerticalDragStart',
      'onVerticalDragUpdate',
      'onVerticalDragEnd',
      'onVerticalDragCancel',
      'onHorizontalDragDown',
      'onHorizontalDragStart',
      'onHorizontalDragUpdate',
      'onHorizontalDragEnd',
      'onHorizontalDragCancel',
      'onForcePressStart',
      'onForcePressPeak',
      'onForcePressUpdate',
      'onForcePressEnd',
      'onPanDown',
      'onPanStart',
      'onPanUpdate',
      'onPanEnd',
      'onPanCancel',
      'onScaleStart',
      'onScaleUpdate',
      'onScaleEnd',
      // `behavior: HitTestBehavior` and `dragStartBehavior: DragStartBehavior`
      // are excluded via the centralized type denylist.
      'excludeFromSemantics',
      'supportedDevices',
      'trackpadScrollCausesScale',
      'trackpadScrollToScaleFactor',
    ],
    fires: [
      WidgetEventName.onTap,
      WidgetEventName.onLongPress,
      WidgetEventName.onDoubleTap,
    ],
  ),
  BuiltinWidgetCuration<Image>(
    category: WidgetCategory.decoration,
    constructorName: 'network',
    nameOverride: 'Image',
    descriptionOverride: 'A network image.',
    // Network variant adds `loadingBuilder` / `headers` /
    // `webHtmlElementStrategy` on top of the shared image-visual
    // excludes.
    excludeParams: [
      ...kImageVisualExcludes,
      'loadingBuilder',
      'headers',
      'webHtmlElementStrategy',
    ],
    propertyOverrides: {
      'src': PropertyOverride(name: 'url'),
      ...kWidthHeightLengthOverrides,
      ...kImageAlignmentOverride,
    },
  ),
  BuiltinWidgetCuration<Image>(
    category: WidgetCategory.decoration,
    constructorName: 'asset',
    // Asset variant adds `bundle` + `package` on top of the shared
    // image-visual excludes.
    excludeParams: [...kImageVisualExcludes, 'bundle', 'package'],
    propertyOverrides: {
      ...kWidthHeightLengthOverrides,
      ...kImageAlignmentOverride,
    },
  ),
  BuiltinWidgetCuration<IntrinsicHeight>(category: WidgetCategory.layout),
  BuiltinWidgetCuration<IntrinsicWidth>(category: WidgetCategory.layout),
  BuiltinWidgetCuration<LimitedBox>(
    category: WidgetCategory.layout,
    // `LimitedBox` only takes effect in unbounded contexts and is
    // useless without explicit limits — Flutter's `double.infinity`
    // defaults would round-trip as a no-op. Mark both as required so
    // authors must specify what they're limiting to. (The reflector
    // skips the non-finite defaults regardless; this also makes the
    // codegen emit the throw-on-missing fallback.)
    propertyOverrides: {
      'maxWidth': PropertyOverride(type: PropertyType.length, required: true),
      'maxHeight': PropertyOverride(type: PropertyType.length, required: true),
    },
  ),
  BuiltinWidgetCuration<ListView>(
    category: WidgetCategory.layout,
    // Default constructor only. Named variants (.builder, .separated,
    // .custom) use delegate-driven lazy children and aren't a
    // declarative shape. ListView adds index / repaint / semantic
    // optimisations on top of the shared scrollable imperative set.
    excludeParams: [
      ...kScrollableImperativeExcludes,
      'cacheExtent',
      'itemExtent',
      'itemExtentBuilder',
      'prototypeItem',
      'addAutomaticKeepAlives',
      'addRepaintBoundaries',
      'addSemanticIndexes',
      'semanticChildCount',
    ],
  ),
  // Locale-aware number/currency formatting rendered as text. The
  // formatting configuration is inert data; the value is formatted with
  // `intl.NumberFormat` in compiled widget code. The text surface mirrors
  // `Text` — `style` decomposed through the shared recipe — so a
  // recognized `Text(NumberFormat(...).format(x), ...)` lowers identically;
  // unlike `Text` these surface `overflow`/`softWrap`, which they reproduce
  // faithfully.
  // A curve-based opacity fade (optionally rising) on first appear. The
  // `fromOffset` slot reuses the defensive `Offset.zero` default; `curve`
  // defaults to `easeOut` (not the reflector-default).
  BuiltinWidgetCuration<RestageFadeIn>(
    category: WidgetCategory.decoration,
    fires: [WidgetEventName.onEnd],
    propertyOverrides: {
      'curve': kCurveEaseOutOverride,
      'fromOffset': kOffsetZeroOverride,
    },
  ),
  BuiltinWidgetCuration<RestageFormattedNumber>(
    category: WidgetCategory.decoration,
    descriptionOverride:
        'Locale-aware decimal number formatting, rendered as text.',
    synthetics: kTextStyleSynthetics,
    nativeDecomposes: [kTextStyleNativeDecompose],
  ),
  // A spring-physics entrance: springs `child` from an initial scale/opacity/
  // offset into place on appear. The `fromOffset` slot reuses the defensive
  // `Offset.zero` default.
  BuiltinWidgetCuration<RestageMotion>(
    category: WidgetCategory.decoration,
    fires: [WidgetEventName.onEnd],
    propertyOverrides: {
      'fromOffset': kOffsetZeroOverride,
    },
  ),
  BuiltinWidgetCuration<RestagePrice>(
    category: WidgetCategory.decoration,
    descriptionOverride: 'Locale-aware currency formatting, rendered as text.',
    synthetics: kTextStyleSynthetics,
    nativeDecomposes: [kTextStyleNativeDecompose],
  ),
  // A looping breathing-scale pulse for a call-to-action. `curve` defaults to
  // `easeInOut` (not the reflector-default).
  BuiltinWidgetCuration<RestagePulse>(
    category: WidgetCategory.decoration,
    propertyOverrides: {
      'curve': kCurveEaseInOutOverride,
    },
  ),
  // A staggered cascade entrance over a vertical list of children. The
  // `fromOffset` slot reuses the defensive `Offset.zero` default.
  BuiltinWidgetCuration<RestageStagger>(
    category: WidgetCategory.layout,
    propertyOverrides: {
      'fromOffset': kOffsetZeroOverride,
    },
  ),
  BuiltinWidgetCuration<Opacity>(category: WidgetCategory.decoration),
  BuiltinWidgetCuration<Padding>(category: WidgetCategory.layout),
  BuiltinWidgetCuration<Positioned>(
    category: WidgetCategory.layout,
    propertyOverrides: {
      'left': PropertyOverride(type: PropertyType.length),
      'top': PropertyOverride(type: PropertyType.length),
      'right': PropertyOverride(type: PropertyType.length),
      'bottom': PropertyOverride(type: PropertyType.length),
      'width': PropertyOverride(type: PropertyType.length),
      'height': PropertyOverride(type: PropertyType.length),
    },
  ),
  BuiltinWidgetCuration<Row>(
    category: WidgetCategory.layout,
    excludeParams: kFlexExcludes,
  ),
  BuiltinWidgetCuration<RotatedBox>(category: WidgetCategory.decoration),
  BuiltinWidgetCuration<SafeArea>(
    category: WidgetCategory.layout,
    // `minimum: EdgeInsets.zero` is a const-identifier default the
    // reflector can't decode as a primitive. The four `bool` edge
    // toggles cover the common cases — the rare minimum-padding
    // shape can be replaced with a manual `Padding` wrap.
    excludeParams: ['minimum'],
  ),
  BuiltinWidgetCuration<SingleChildScrollView>(
    category: WidgetCategory.layout,
    excludeParams: kScrollableImperativeExcludes,
  ),
  BuiltinWidgetCuration<SizedBox>(
    category: WidgetCategory.layout,
    propertyOverrides: kWidthHeightLengthOverrides,
  ),
  BuiltinWidgetCuration<Spacer>(category: WidgetCategory.layout),
  BuiltinWidgetCuration<Stack>(
    category: WidgetCategory.layout,
    excludeParams: ['textDirection'],
    // `Stack.alignment`'s default (`AlignmentDirectional.topStart`) is now
    // mechanically resolved from the Flutter constructor parameter — the
    // const-default resolver recovers the static-const member name for
    // alignment-typed properties, so no `defaultValue` override is needed.
  ),
  BuiltinWidgetCuration<Text>(
    category: WidgetCategory.decoration,
    descriptionOverride: 'Static text with optional styling.',
    // `softWrap` / `textWidthBasis` / `semanticsLabel` are surfaced — the
    // common widget-level text-layout knobs, reusing the boolean / enum /
    // string decoders. `overflow` is already provided as a slot via the
    // shared TextStyle decompose (`style.overflow`), so it is not re-added
    // here. The remaining knobs stay excluded: `strutStyle` /
    // `textHeightBehavior` (structured), `textDirection` (directional),
    // `textScaleFactor` / `textScaler` (deprecated / abstract),
    // `semanticsIdentifier` (niche), `selectionColor` (selectable-text only).
    excludeParams: [
      'strutStyle',
      'textDirection',
      // `locale: Locale` is excluded via the centralized type denylist.
      'overflow',
      'textScaleFactor',
      'textScaler',
      'semanticsIdentifier',
      'textHeightBehavior',
      'selectionColor',
    ],
    propertyOverrides: {
      'data': PropertyOverride(name: 'text'),
    },
    synthetics: kTextStyleSynthetics,
    nativeDecomposes: [kTextStyleNativeDecompose],
  ),
  BuiltinWidgetCuration<Text>(
    category: WidgetCategory.decoration,
    // The `Text.rich` named constructor takes a positional `InlineSpan`
    // tree (a `TextSpan` root carrying styled `text` and nested
    // `children`) instead of the plain `Text(String)` data. The catalog
    // name auto-derives to `TextRich` and the flutterType carries the
    // `#Text.rich` suffix, so the codegen recognizer routes the inline-span
    // lowering through the bespoke depth-bounded span decoder. The styling
    // surface mirrors the plain `Text` entry exactly (decomposed `style`,
    // `textAlign`, `maxLines`, and the surfaced `softWrap` / `textWidthBasis`
    // / `semanticsLabel` widget-level layout knobs) so the two `Text` variants
    // present a uniform catalog surface; the same excludes are kept on both.
    constructorName: 'rich',
    descriptionOverride:
        'Rich text — a styled inline-span tree with optional styling.',
    excludeParams: [
      'strutStyle',
      'textDirection',
      // `locale: Locale` is excluded via the centralized type denylist.
      'overflow',
      'textScaleFactor',
      'textScaler',
      'semanticsIdentifier',
      'textHeightBehavior',
      'selectionColor',
    ],
    propertyOverrides: {
      // `textSpan: InlineSpan` is the positional argument. `InlineSpan` is
      // not a mechanically-inferable catalog type, so the override declares
      // it explicitly as the recursive `inlineSpan` slot decoded by the
      // bespoke depth-bounded span decoder.
      'textSpan': PropertyOverride(
        type: PropertyType.inlineSpan,
        positional: true,
      ),
    },
    synthetics: kTextStyleSynthetics,
    nativeDecomposes: [kTextStyleNativeDecompose],
  ),
  BuiltinWidgetCuration<Transform>(
    category: WidgetCategory.decoration,
    // Default `Transform(transform: Matrix4)` requires a structured
    // `Matrix4` the catalog doesn't decompose. Ship the rotation
    // variant — single `angle: double` scalar plus `child` — under
    // the auto-derived `TransformRotate` catalog name so the limited
    // scope is explicit. `Transform.scale` / `.translate` / general
    // matrix variants land in a sibling milestone.
    constructorName: 'rotate',
    // `origin: Offset?` surfaces as an optional `offset` slot (the rotation
    // pivot). It is nullable with a null Flutter default — left optional with
    // no synthetic default so an absent slot centres on `alignment`, faithful
    // to `Transform.rotate`. The concrete-`Offset` source lowering routes it
    // through the shared `offset` decoder.
    propertyOverrides: {'alignment': kAlignmentCenterOverride},
  ),
  BuiltinWidgetCuration<Visibility>(
    category: WidgetCategory.decoration,
    // Start minimal: `visible` toggles the subtree. `replacement` is
    // a non-nullable Widget defaulting to `const SizedBox.shrink()`
    // — a structured const the reflector can't surface as a literal
    // default, and a required catalog slot would worsen UX for the
    // common case of just toggling visibility without a placeholder.
    // The `maintain*` knobs are accessibility / layout-preservation
    // overrides for advanced use. Surface in a sibling milestone if
    // a customer surfaces the gap.
    excludeParams: [
      'replacement',
      'maintainState',
      'maintainAnimation',
      'maintainSize',
      'maintainSemantics',
      'maintainInteractivity',
    ],
  ),
  BuiltinWidgetCuration<Wrap>(
    category: WidgetCategory.layout,
    propertyOverrides: {
      'spacing': PropertyOverride(type: PropertyType.length),
      'runSpacing': PropertyOverride(type: PropertyType.length),
    },
  ),
];
