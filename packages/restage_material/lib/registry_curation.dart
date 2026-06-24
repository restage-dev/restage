/// Curation file for the `restage.material` widget library — Material
/// design widgets curated for paywall composition.
///
/// Same authoring contract as `restage_core/lib/registry_curation.dart`:
/// curators specify only what cannot be derived from a Flutter widget's
/// constructor (catalog [WidgetCategory], event mapping, parameter
/// exclusions, brand-token defaults, structured-type decomposition
/// recipes, per-property overrides for renames or non-mechanical
/// defaults). The reflector fills in the rest by walking each constructor
/// parameter (name, type, dartdoc, required-flag, literal default).
///
/// **Decomposition recipe naming.** Same convention as `restage_core`:
/// unprefixed by default (the structured type's constructor argument name
/// is hoisted directly onto the flat property surface), prefixed with the
/// structured-arg parameter name plus `_` when there would otherwise be a
/// name collision.
///
/// All seven Material buttons below flatten their `ButtonStyle` surface
/// via shared native decomposition metadata in
/// `lib/src/decomposition_recipes.dart`.
library;

import 'package:flutter/material.dart';
import 'package:restage_material/src/decomposition_recipes.dart';
import 'package:restage_material/src/widgets/express_checkout_button.dart';
import 'package:restage_material/src/widgets/restage_draggable_sheet.dart';
import 'package:restage_material/src/widgets/restage_dropdown.dart';
import 'package:restage_material/src/widgets/restage_modal_sheet.dart';
import 'package:restage_material/src/widgets/restage_pager.dart';
import 'package:restage_material/src/widgets/restage_radio_group.dart';
import 'package:restage_material/src/widgets/restage_segmented_button.dart';
import 'package:restage_material/src/widgets/restage_toggle_buttons.dart';
import 'package:restage_material/src/widgets/package.dart';
import 'package:restage_shared/restage_shared.dart';

/// Constructor parameters every Material button shares
/// (super-formals on `ButtonStyleButton`). Excluded uniformly so each
/// button entry only lists its own per-variant additions.
///
/// `focusNode: FocusNode` and `statesController: MaterialStatesController`
/// are excluded via the centralized type denylist (suffix `Node` and
/// `Controller` respectively).
const _kSharedButtonExcludeParams = <String>[
  'onLongPress',
  'onHover',
  'onFocusChange',
  'style',
  'autofocus',
];

/// Material 3 button padding default (LTRB: horizontal=24, vertical=12).
/// Hoisted out of `<Button>.styleFrom(padding:)` and reused unchanged
/// across all seven button variants.
const _kButtonPaddingSynthetic = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'padding',
  type: PropertyType.edgeInsets,
  description: 'Padding inside the button.',
  defaultSource: LiteralDefault([24.0, 12.0, 24.0, 12.0]),
);

/// Material button outline shape. Reassembled through
/// `<Button>.styleFrom(shape:)` from Restage's shape-border wire map.
const _kButtonShapeSynthetic = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'shape',
  type: PropertyType.shapeBorder,
  description: 'Button outline shape.',
  valueShape: UnionShape(
    propertyType: PropertyType.shapeBorder,
    unionRef: WireIdRef(
      library: 'restage.material',
      wireId: WireId.unallocatedUnion,
    ),
    wireCodec: CatalogWireCodec.rfwShapeBorder,
  ),
);

/// Material button minimum size. Reassembled through
/// `<Button>.styleFrom(minimumSize:)` from Restage's `{width, height}` wire
/// map via the registered structured `Size` decoder.
const _kButtonMinimumSizeSynthetic = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'minimumSize',
  type: PropertyType.structured,
  description: 'Minimum button size (width, height).',
  structuredRef: WireIdRef(
    library: 'restage.material',
    wireId: WireId.unallocatedStructured,
  ),
  valueShape: StructuredShape(
    propertyType: PropertyType.structured,
    structuredRef: WireIdRef(
      library: 'restage.material',
      wireId: WireId.unallocatedStructured,
    ),
  ),
);

/// Material button fixed size. Reassembled through
/// `<Button>.styleFrom(fixedSize:)` from Restage's `{width, height}` wire map
/// via the registered structured `Size` decoder.
const _kButtonFixedSizeSynthetic = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'fixedSize',
  type: PropertyType.structured,
  description: 'Fixed button size (width, height).',
  structuredRef: WireIdRef(
    library: 'restage.material',
    wireId: WireId.unallocatedStructured,
  ),
  valueShape: StructuredShape(
    propertyType: PropertyType.structured,
    structuredRef: WireIdRef(
      library: 'restage.material',
      wireId: WireId.unallocatedStructured,
    ),
  ),
);

/// Material button border side. Reassembled through
/// `<Button>.styleFrom(side:)` from Restage's `{color, width, style}` wire
/// map via the registered structured `BorderSide` decoder.
const _kButtonSideSynthetic = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'side',
  type: PropertyType.structured,
  description: 'Button border side (color, width, style).',
  structuredRef: WireIdRef(
    library: 'restage.material',
    wireId: WireId.unallocatedStructured,
  ),
  valueShape: StructuredShape(
    propertyType: PropertyType.structured,
    structuredRef: WireIdRef(
      library: 'restage.material',
      wireId: WireId.unallocatedStructured,
    ),
  ),
);

/// Material button text style. Reassembled through
/// `<Button>.styleFrom(textStyle:)` from Restage's `TextStyle` wire map via
/// the registered structured `TextStyle` decoder. This is the
/// structured-on-`ButtonStyle` text style — distinct from (and coexisting
/// with) the flat `TextStyle` decompose on `Text` / `DefaultTextStyle`.
const _kButtonTextStyleSynthetic = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'textStyle',
  type: PropertyType.structured,
  description: 'Button label text style.',
  structuredRef: WireIdRef(
    library: 'restage.material',
    wireId: WireId.unallocatedStructured,
  ),
  valueShape: StructuredShape(
    propertyType: PropertyType.structured,
    structuredRef: WireIdRef(
      library: 'restage.material',
      wireId: WireId.unallocatedStructured,
    ),
  ),
);

/// The four structured `ButtonStyle` sizing/styling synthetics, surfaced
/// together (in this order) on every curated Material button variant.
const List<PropertyEntry> _kButtonStyleSizeSynthetics = [
  _kButtonMinimumSizeSynthetic,
  _kButtonFixedSizeSynthetic,
  _kButtonSideSynthetic,
  _kButtonTextStyleSynthetic,
];

/// Shape-border default-value token for an avatar clipped to a circle.
/// The emitter recognizes this on a `shapeBorder` property and emits
/// `const CircleBorder()` as the `??` fallback.
const String _kAvatarBorderCircle = 'circle';

/// `disabled` synthetic shared by every Material button. Gates the
/// widget's `onPressed` handler when true, rather than being passed as a
/// constructor arg (Flutter buttons have no `disabled:` parameter).
const _kButtonDisabledSynthetic = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'disabled',
  type: PropertyType.boolean,
  description: 'Whether the button is disabled.',
  defaultSource: LiteralDefault(false),
  synthetic: 'gateOnPressed',
);

/// Constructor parameters every Material chip variant shares. The
/// `ChipBase`-shaped mixin (label / avatar / tooltip / focus / mouse /
/// theme / shape / chip-animation knobs) repeats across `Chip`,
/// `ActionChip`, `FilterChip`, and `ChoiceChip`. Each variant adds its
/// own selectors (`onSelected`, `selectedColor`, `showCheckmark`, …) or
/// deletion knobs (`onDeleted`, `deleteIcon`, …) inline.
///
/// `focusNode: FocusNode` and `mouseCursor: MouseCursor` are excluded
/// via the centralized type denylist. `avatarBoxConstraints:
/// BoxConstraints` is excluded via `BoxConstraints` in the denylist.
///
/// `side: BorderSide?` flows through the structured walker as a flat
/// concrete-whitelist type so authors can still drive a colored chip
/// outline; it is no longer pinned out of the catalog here. `shape`
/// stays excluded because `OutlinedBorder` is a subtype that is not on
/// the structured-walk whitelist (only the abstract base `ShapeBorder`
/// is).
const _kSharedChipExcludeParams = <String>[
  'labelPadding',
  'shape',
  'autofocus',
  // `color` is `WidgetStateProperty<Color?>?` — the catalog doesn't
  // model `WidgetStateProperty`. Flat `backgroundColor` (where each
  // variant surfaces it) covers the common single-color need.
  'color',
  'visualDensity',
  'materialTapTargetSize',
  'elevation',
  'shadowColor',
  'surfaceTintColor',
  'iconTheme',
  'chipAnimationStyle',
];

/// Brand-token default shared by all chip variants — chip surfaces sit
/// on the M3 `surface` role by default.
const _kChipSurfaceBrandTokens = <String, String>{'backgroundColor': 'surface'};

/// Constructor parameters every `ListTile`-shaped composed input row
/// shares. The composed list-tile widgets (`CheckboxListTile`,
/// `SwitchListTile`) reuse the underlying `ListTile`'s row knobs
/// (`tileColor`, `contentPadding`, `dense`, focus / hover / splash,
/// `horizontalTitleGap`, etc.). Each composed entry adds its own
/// control-specific knobs (`fillColor`, `tristate` for the checkbox;
/// `activeColor`, `activeTrackColor`, `thumbColor`, ... for the switch)
/// inline — `activeColor` is not shared because it's deprecated on
/// `SwitchListTile` (use `activeThumbColor`) but still the live tint
/// knob on `CheckboxListTile`.
///
/// `focusNode: FocusNode` and `mouseCursor: MouseCursor` are excluded
/// via the centralized type denylist.
///
/// `shape: ShapeBorder?` flows through the structured walker as an
/// abstract-whitelist placeholder pending union resolution; it is no
/// longer pinned out of the catalog here.
const _kSharedListTileExcludeParams = <String>[
  'hoverColor',
  'overlayColor',
  'splashRadius',
  'materialTapTargetSize',
  'visualDensity',
  'autofocus',
  'tileColor',
  'isThreeLine',
  'dense',
  'controlAffinity',
  'contentPadding',
  'selectedTileColor',
  'onFocusChange',
  'enableFeedback',
  'horizontalTitleGap',
  'minVerticalPadding',
  'minLeadingWidth',
  'minTileHeight',
  'internalAddSemanticForOnTap',
];

/// Curation list consumed by `BuiltinCurationBuilder` to emit
/// `lib/registry.dart` and `lib/src/widget_catalog/catalog.json`.
@RestageBuiltinLibrary(library: WidgetLibrary.material, version: '0.1.0')
const List<BuiltinWidgetCuration> kCuration = [
  // `onPressed` is `VoidCallback?` on the Flutter ctor — passing null is
  // Flutter's convention for the disabled state. Unlike the elevated
  // CTAs (ElevatedButton, FilledButton, etc.), no `disabled` synthetic
  // is surfaced: action chips are incidental tap targets, not the
  // conversion CTAs the gate machinery was added for.
  BuiltinWidgetCuration<ActionChip>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onPressed],
    excludeParams: [
      ..._kSharedChipExcludeParams,
      'pressElevation',
      'tooltip',
      'disabledColor',
    ],
    brandTokens: _kChipSurfaceBrandTokens,
  ),
  BuiltinWidgetCuration<AppBar>(
    category: WidgetCategory.layout,
    excludeParams: [
      'leading',
      'automaticallyImplyLeading',
      'actions',
      'flexibleSpace',
      'bottom',
      'scrolledUnderElevation',
      'notificationPredicate',
      'shadowColor',
      'surfaceTintColor',
      'iconTheme',
      'actionsIconTheme',
      'primary',
      'excludeHeaderSemantics',
      'titleSpacing',
      'toolbarOpacity',
      'bottomOpacity',
      'toolbarHeight',
      'leadingWidth',
      'systemOverlayStyle',
      'forceMaterialTransparency',
      'useDefaultSemanticsOrder',
      'actionsPadding',
      'automaticallyImplyActions',
      'animateColor',
    ],
    brandTokens: {
      'backgroundColor': 'primary',
      'foregroundColor': 'onPrimary',
    },
    propertyOverrides: {
      'elevation': PropertyOverride(type: PropertyType.length),
      // Flutter's `centerTitle` is `bool?` with no constructor default
      // (the runtime infers from theme); we surface the paywall-friendly
      // default so authors don't need to set it explicitly.
      'centerTitle': PropertyOverride(defaultValue: true),
    },
  ),
  // Counter / status overlay (notifications dot, "NEW" tag). `label` is
  // a non-canonical `Widget?` slot used for the badge contents (typically
  // a short `Text` widget); `child` is the canonical anchor below which
  // the badge floats. Brand defaults use the Material 3 filled-badge
  // palette (`error` / `onError`).
  BuiltinWidgetCuration<Badge>(
    category: WidgetCategory.decoration,
    // `offset: Offset?` surfaces as an optional `offset` slot (the badge's
    // position relative to its anchor). It is nullable with a null Flutter
    // default — left optional with no synthetic default so an absent slot uses
    // Badge's text-direction-aware default positioning, faithful to `Badge`;
    // a forced `Offset.zero` would instead pin it to a literal zero offset.
    excludeParams: [
      'smallSize',
      'largeSize',
    ],
    brandTokens: {
      'backgroundColor': 'error',
      'textColor': 'onError',
    },
  ),
  BuiltinWidgetCuration<Card>(
    category: WidgetCategory.decoration,
    excludeParams: [
      'shadowColor',
      'surfaceTintColor',
      'borderOnForeground',
      'semanticContainer',
    ],
    brandTokens: {'color': 'surface'},
    propertyOverrides: {
      'elevation': PropertyOverride(
        type: PropertyType.length,
        defaultValue: 1.0,
      ),
    },
  ),
  // The two M3 Card variants below are flat surfaces (no shadow). `filled`
  // tints with the M3 `surfaceContainerHighest` role; `outlined` is
  // transparent with a stroked border picking up `outline`. Both are
  // factory constructors on the same `Card` class, so the dartdoc
  // description would collapse to the parent class's text without an
  // override.
  BuiltinWidgetCuration<Card>(
    category: WidgetCategory.decoration,
    constructorName: 'filled',
    descriptionOverride:
        'An M3 filled card — flat surface tinted from the palette.',
    excludeParams: [
      'shadowColor',
      'surfaceTintColor',
      'borderOnForeground',
      'semanticContainer',
    ],
    brandTokens: {'color': 'surfaceContainerHighest'},
    propertyOverrides: {
      'elevation': PropertyOverride(
        type: PropertyType.length,
        defaultValue: 0.0,
      ),
    },
  ),
  BuiltinWidgetCuration<Card>(
    category: WidgetCategory.decoration,
    constructorName: 'outlined',
    descriptionOverride:
        'An M3 outlined card — transparent surface with a border.',
    excludeParams: [
      'shadowColor',
      'surfaceTintColor',
      'borderOnForeground',
      'semanticContainer',
    ],
    brandTokens: {'color': 'surface'},
    propertyOverrides: {
      'elevation': PropertyOverride(
        type: PropertyType.length,
        defaultValue: 0.0,
      ),
    },
  ),
  BuiltinWidgetCuration<Checkbox>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onChanged],
    excludeParams: [
      // `focusNode: FocusNode` and `mouseCursor: MouseCursor` are
      // excluded via the centralized type denylist. `side: BorderSide?`
      // flows through the structured walker as a flat concrete-whitelist
      // type; `shape: OutlinedBorder?` is a subtype not on the walker
      // whitelist so it stays pinned here.
      'tristate',
      'fillColor',
      'checkColor',
      'focusColor',
      'hoverColor',
      'overlayColor',
      'splashRadius',
      'materialTapTargetSize',
      'visualDensity',
      'autofocus',
      'shape',
      'isError',
      'semanticLabel',
    ],
    brandTokens: {'activeColor': 'primary'},
    propertyOverrides: {
      // Material `Checkbox` supports the tristate value (true/false/null),
      // so the Flutter ctor types `onChanged` as `ValueChanged<bool?>?`
      // — the inner `bool?` differs from `Switch` (`ValueChanged<bool>?`).
      'onChanged': PropertyOverride(callbackSignature: 'ValueChanged<bool?>'),
    },
  ),
  // Composed `Checkbox` + `ListTile` row. `title` / `subtitle` /
  // `secondary` are non-canonical Widget slots beyond the implicit
  // checkbox. Mirrors the `Checkbox` curation for the value+onChanged
  // pair (tristate-shaped `ValueChanged<bool?>`) and brand-tokens
  // `activeColor` to `primary` (the checkbox tint when checked).
  BuiltinWidgetCuration<CheckboxListTile>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onChanged],
    excludeParams: [
      ..._kSharedListTileExcludeParams,
      'fillColor',
      'checkColor',
      'isError',
      'enabled',
      'tristate',
      'checkboxShape',
      'checkboxSemanticLabel',
      'checkboxScaleFactor',
      'titleAlignment',
    ],
    brandTokens: {'activeColor': 'primary'},
    propertyOverrides: {
      'onChanged': PropertyOverride(callbackSignature: 'ValueChanged<bool?>'),
    },
  ),
  // `label` is required and non-canonical (the param name is `label`,
  // not `child`). Surfaces as a non-canonical `Widget` property — the
  // factory emitter handles non-canonical widget slots already
  // (precedent: `AppBar.title`, `ListTile.{title, subtitle}`).
  BuiltinWidgetCuration<Chip>(
    category: WidgetCategory.decoration,
    excludeParams: [
      ..._kSharedChipExcludeParams,
      'deleteIcon',
      'onDeleted',
      'deleteIconColor',
      'deleteButtonTooltipMessage',
      'deleteIconBoxConstraints',
    ],
    brandTokens: _kChipSurfaceBrandTokens,
  ),
  // Single-select chip group member — fires the new `onSelected` event
  // (catalog enum extended for chip/selection semantics; distinct from
  // `onChanged`'s value-edit shape).
  BuiltinWidgetCuration<ChoiceChip>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onSelected],
    excludeParams: [
      ..._kSharedChipExcludeParams,
      'pressElevation',
      'selectedColor',
      'disabledColor',
      'tooltip',
      'selectedShadowColor',
      'showCheckmark',
      'checkmarkColor',
    ],
    brandTokens: _kChipSurfaceBrandTokens,
    propertyOverrides: {
      'onSelected': PropertyOverride(callbackSignature: 'ValueChanged<bool>'),
      // Flutter defaults the avatar clip to a circle; surface it so the
      // catalog carries the documented default rather than relying on an
      // emitter special-case.
      'avatarBorder': PropertyOverride(defaultValue: _kAvatarBorderCircle),
    },
  ),
  BuiltinWidgetCuration<CircularProgressIndicator>(
    category: WidgetCategory.decoration,
    excludeParams: [
      'backgroundColor',
      'valueColor',
      'strokeAlign',
      'semanticsLabel',
      'semanticsValue',
      'strokeCap',
      'padding',
      'year2023',
      'trackGap',
      'constraints',
      'controller',
    ],
    brandTokens: {'color': 'primary'},
    // Flutter's `strokeWidth` field has no constructor literal default
    // (the conceptual 4.0 is applied later in the build path); surface it
    // here so the catalog still encodes the documented default.
    propertyOverrides: {
      'strokeWidth': PropertyOverride(
        type: PropertyType.length,
        defaultValue: 4.0,
      ),
    },
  ),
  BuiltinWidgetCuration<Divider>(
    category: WidgetCategory.decoration,
    excludeParams: ['indent', 'endIndent', 'radius'],
    brandTokens: {'color': 'onBackground'},
    propertyOverrides: {
      'height': PropertyOverride(
        type: PropertyType.length,
        defaultValue: 16.0,
      ),
      'thickness': PropertyOverride(
        type: PropertyType.length,
        defaultValue: 1.0,
      ),
    },
  ),
  // The seven Material buttons below all flatten a `ButtonStyle` surface
  // built via the `<Button>.styleFrom(...)` static factory. The recipe
  // const declares which named arguments hoist onto each widget's flat
  // property surface — see `lib/src/decomposition_recipes.dart`.
  //
  // Codegen translators emit `<TargetType>.styleFrom(...)` invocations
  // (which take plain `Color`, `EdgeInsetsGeometry`, `double`), NOT raw
  // `ButtonStyle(...)` constructor calls (which take
  // `WidgetStateProperty<T>` wrappers around the same fields).
  BuiltinWidgetCuration<ElevatedButton>(
    category: WidgetCategory.action,
    fires: [WidgetEventName.onPressed],
    excludeParams: _kSharedButtonExcludeParams,
    synthetics: [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'backgroundColor',
        type: PropertyType.color,
        description: 'Background color.',
        defaultBrandToken: 'primary',
      ),
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'foregroundColor',
        type: PropertyType.color,
        description: 'Foreground color (text + icons).',
        defaultBrandToken: 'onPrimary',
      ),
      _kButtonPaddingSynthetic,
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'elevation',
        type: PropertyType.length,
        description: 'Material elevation in logical pixels.',
        defaultSource: LiteralDefault(1.0),
      ),
      _kButtonShapeSynthetic,
      ..._kButtonStyleSizeSynthetics,
      _kButtonDisabledSynthetic,
    ],
    nativeDecomposes: [kFilledButtonStyleNativeDecompose],
  ),
  // FAQ sections, expandable feature lists. State pattern matches the
  // `Switch.value` / `Checkbox.value` convention: `initiallyExpanded`
  // scalar + `onExpansionChanged` event firing the new expansion state
  // (controller-based curation deferred — the value+event shape is the
  // catalog convention). `title` is a required non-canonical `Widget`
  // slot; `leading` / `subtitle` / `trailing` are optional non-canonical
  // widget slots; `children` is the canonical list slot.
  BuiltinWidgetCuration<ExpansionTile>(
    category: WidgetCategory.layout,
    fires: [WidgetEventName.onExpansionChanged],
    excludeParams: [
      'showTrailingIcon',
      'maintainState',
      'tilePadding',
      'expandedCrossAxisAlignment',
      'expandedAlignment',
      'childrenPadding',
      'backgroundColor',
      'collapsedBackgroundColor',
      'textColor',
      'collapsedTextColor',
      'iconColor',
      'collapsedIconColor',
      'controlAffinity',
      'controller',
      'dense',
      'splashColor',
      'visualDensity',
      'minTileHeight',
      'enableFeedback',
      'enabled',
      'expansionAnimationStyle',
      'internalAddSemanticForOnTap',
    ],
    propertyOverrides: {
      'onExpansionChanged': PropertyOverride(
        callbackSignature: 'ValueChanged<bool>',
      ),
    },
  ),
  // Conversion-CTA button for platform-native express-checkout flows
  // (Apple Pay / Google Pay / neutral fallback). The widget renders
  // a styled Material button while billing-channel integration is in
  // flight; the catalog API surface is locked at end-state.
  BuiltinWidgetCuration<ExpressCheckoutButton>(
    category: WidgetCategory.action,
    fires: [WidgetEventName.onPressed],
  ),
  BuiltinWidgetCuration<FilledButton>(
    category: WidgetCategory.action,
    fires: [WidgetEventName.onPressed],
    excludeParams: _kSharedButtonExcludeParams,
    synthetics: [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'backgroundColor',
        type: PropertyType.color,
        description: 'Background color.',
        defaultBrandToken: 'primary',
      ),
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'foregroundColor',
        type: PropertyType.color,
        description: 'Foreground color (text + icons).',
        defaultBrandToken: 'onPrimary',
      ),
      _kButtonPaddingSynthetic,
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'elevation',
        type: PropertyType.length,
        description: 'Material elevation in logical pixels.',
        defaultSource: LiteralDefault(0.0),
      ),
      _kButtonShapeSynthetic,
      ..._kButtonStyleSizeSynthetics,
      _kButtonDisabledSynthetic,
    ],
    nativeDecomposes: [kFilledButtonStyleNativeDecompose],
  ),
  // `FilledButton.tonal` is the M3 secondary CTA — flat tonal surface
  // tinted from `secondaryContainer`. Same property surface as
  // `FilledButton` minus `elevation` (the tonal variant is shadowless).
  // The factory constructor shares its dartdoc with the parent class, so
  // override here to keep the catalog entry distinct.
  BuiltinWidgetCuration<FilledButton>(
    category: WidgetCategory.action,
    constructorName: 'tonal',
    descriptionOverride:
        'An M3 secondary call-to-action button (tonal variant).',
    fires: [WidgetEventName.onPressed],
    excludeParams: _kSharedButtonExcludeParams,
    synthetics: [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'backgroundColor',
        type: PropertyType.color,
        description: 'Background (tonal) color.',
        defaultBrandToken: 'secondaryContainer',
      ),
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'foregroundColor',
        type: PropertyType.color,
        description: 'Foreground color (text + icons).',
        defaultBrandToken: 'onSecondaryContainer',
      ),
      _kButtonPaddingSynthetic,
      _kButtonShapeSynthetic,
      ..._kButtonStyleSizeSynthetics,
      _kButtonDisabledSynthetic,
    ],
    nativeDecomposes: [kTonalButtonStyleNativeDecompose],
  ),
  // Multi-select chip with a typed `bool` payload. Flutter declares
  // `onSelected` as `required this.onSelected` but the field type is
  // `ValueChanged<bool>?` — passing null is the documented way to
  // disable the chip. The override flips `required: false` so the
  // catalog treats the disabled-as-null shape as optional (same
  // pattern as `CupertinoSwitch.onChanged`).
  BuiltinWidgetCuration<FilterChip>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onSelected],
    excludeParams: [
      ..._kSharedChipExcludeParams,
      'deleteIcon',
      'onDeleted',
      'deleteIconColor',
      'deleteButtonTooltipMessage',
      'pressElevation',
      'disabledColor',
      'selectedColor',
      'tooltip',
      'selectedShadowColor',
      'showCheckmark',
      'checkmarkColor',
      'deleteIconBoxConstraints',
    ],
    brandTokens: _kChipSurfaceBrandTokens,
    propertyOverrides: {
      'onSelected': PropertyOverride(
        required: false,
        callbackSignature: 'ValueChanged<bool>',
      ),
      // Flutter defaults the avatar clip to a circle; surface it so the
      // catalog carries the documented default rather than relying on an
      // emitter special-case.
      'avatarBorder': PropertyOverride(defaultValue: _kAvatarBorderCircle),
    },
  ),
  // Default ctor only — `.small` / `.large` / `.extended` variants
  // deferred (each adds a separate property surface and the standard
  // circular FAB covers the common paywall composition need).
  // `onPressed` is `required` on the Flutter ctor but typed
  // `VoidCallback?`; the override flips `required: false` so passing
  // null disables the button (same pattern as Cupertino buttons and
  // FilterChip). Brand defaults use the M3 standard FAB palette
  // (`primaryContainer` / `onPrimaryContainer`).
  BuiltinWidgetCuration<FloatingActionButton>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onPressed],
    excludeParams: [
      // `focusNode: FocusNode` and `mouseCursor: MouseCursor` are
      // excluded via the centralized type denylist.
      'focusColor',
      'hoverColor',
      'splashColor',
      'heroTag',
      'focusElevation',
      'hoverElevation',
      'highlightElevation',
      'disabledElevation',
      'autofocus',
      'materialTapTargetSize',
      'isExtended',
      'enableFeedback',
    ],
    brandTokens: {
      'backgroundColor': 'primaryContainer',
      'foregroundColor': 'onPrimaryContainer',
    },
    propertyOverrides: {
      'onPressed': PropertyOverride(required: false),
      'elevation': PropertyOverride(type: PropertyType.length),
    },
  ),
  // `Icon`'s `IconData icon` argument is surfaced as an `int` codepoint —
  // the catalog's [PropertyType] enum does not yet model `IconData` as a
  // first-class type. The runtime reconstructs `IconData(codepoint,
  // fontFamily: 'MaterialIcons')`. Apps shipping rfw-rendered paywalls
  // build with `--no-tree-shake-icons` because the icon font is
  // referenced by codepoint at runtime, not by `Icons.foo` at compile
  // time.
  BuiltinWidgetCuration<Icon>(
    category: WidgetCategory.decoration,
    excludeParams: [
      'icon',
      'fill',
      'weight',
      'grade',
      'opticalSize',
      'shadows',
      'semanticLabel',
      'textDirection',
      'applyTextScaling',
      'blendMode',
      'fontWeight',
    ],
    propertyOverrides: {
      // `size` is left without an explicit default so the theme-binding
      // seed materializes `iconTheme.size`: Flutter resolves a null
      // `Icon.size` against the ambient `IconTheme`, mirroring how
      // `color` resolves against `iconTheme.color`.
      'size': PropertyOverride(
        type: PropertyType.length,
      ),
    },
    synthetics: [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'iconCodepoint',
        type: PropertyType.integer,
        description: 'Material icon codepoint, e.g. 0xe145 for Icons.add.',
        required: true,
        // Synthetic: the codepoint wraps as `IconData(value,
        // fontFamily: 'MaterialIcons')` and is passed to Flutter's
        // `Icon(IconData icon, ...)` positional arg, not as a named
        // `iconCodepoint:` parameter (which doesn't exist).
        synthetic: 'iconData',
        positional: true,
      ),
    ],
  ),
  BuiltinWidgetCuration<IconButton>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onPressed],
    excludeParams: [
      // `focusNode: FocusNode`, `mouseCursor: MouseCursor`, and
      // `statesController: WidgetStatesController` are excluded via
      // the centralized type denylist.
      'visualDensity',
      'padding',
      'alignment',
      'splashRadius',
      'focusColor',
      'hoverColor',
      'highlightColor',
      'splashColor',
      'disabledColor',
      'onHover',
      'onLongPress',
      'autofocus',
      'enableFeedback',
      'constraints',
      'style',
      'isSelected',
      'selectedIcon',
    ],
    propertyOverrides: {
      'iconSize': PropertyOverride(
        type: PropertyType.length,
        defaultValue: 24.0,
      ),
    },
  ),
  // Material tap visual feedback for arbitrary tap targets. Requires
  // a `Material` ancestor in the widget tree — satisfied by the
  // customer's `Scaffold`, so no extra wrapping needed at runtime.
  // Surfaces `onTap` only; richer gestures (`onDoubleTap`,
  // `onLongPress`, secondary / hover / focus) deferred.
  BuiltinWidgetCuration<InkWell>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onTap],
    excludeParams: [
      // `focusNode: FocusNode`, `mouseCursor: MouseCursor`, and
      // `statesController: WidgetStatesController` are excluded via
      // the centralized type denylist.
      'onDoubleTap',
      'onLongPress',
      'onLongPressUp',
      'onTapDown',
      'onTapUp',
      'onTapCancel',
      'onSecondaryTap',
      'onSecondaryTapUp',
      'onSecondaryTapDown',
      'onSecondaryTapCancel',
      'onHighlightChanged',
      'onHover',
      'focusColor',
      'hoverColor',
      'highlightColor',
      'overlayColor',
      'splashColor',
      'splashFactory',
      'radius',
      'borderRadius',
      'enableFeedback',
      'excludeFromSemantics',
      'canRequestFocus',
      'onFocusChange',
      'autofocus',
      'hoverDuration',
    ],
  ),
  // Loading bars, multi-step progress visualisation. Optional
  // `value: double?` — null renders the indeterminate animation;
  // a value in [0.0, 1.0] renders a determinate fill. Mirrors the
  // `CircularProgressIndicator` curation pattern (brand-default
  // `color`, surface `minHeight` as a length).
  BuiltinWidgetCuration<LinearProgressIndicator>(
    category: WidgetCategory.decoration,
    // `backgroundColor` is surfaced — the translucent progress track is a
    // standard onboarding-progress idiom and the value is a plain `Color?`.
    excludeParams: [
      'valueColor',
      'semanticsLabel',
      'semanticsValue',
      'borderRadius',
      'stopIndicatorColor',
      'stopIndicatorRadius',
      'trackGap',
      // Deprecated in v3.26.0-0.1.pre in favour of the 2024 appearance.
      'year2023',
      'controller',
    ],
    brandTokens: {'color': 'primary'},
    propertyOverrides: {
      'minHeight': PropertyOverride(type: PropertyType.length),
    },
  ),
  BuiltinWidgetCuration<ListTile>(
    category: WidgetCategory.layout,
    fires: [WidgetEventName.onTap],
    excludeParams: [
      'isThreeLine',
      'dense',
      'visualDensity',
      'style',
      'selectedColor',
      'iconColor',
      'textColor',
      'contentPadding',
      'enabled',
      'onLongPress',
      'onFocusChange',
      'selected',
      'focusColor',
      'hoverColor',
      'splashColor',
      'autofocus',
      'tileColor',
      'selectedTileColor',
      'enableFeedback',
      'horizontalTitleGap',
      'minVerticalPadding',
      'minLeadingWidth',
      'titleAlignment',
      'internalAddSemanticForOnTap',
      'minTileHeight',
    ],
  ),
  BuiltinWidgetCuration<MaterialApp>(
    category: WidgetCategory.layout,
    excludeParams: [
      'navigatorKey',
      'scaffoldMessengerKey',
      'routes',
      'initialRoute',
      'onGenerateRoute',
      'onGenerateInitialRoutes',
      'onUnknownRoute',
      'onNavigationNotification',
      'navigatorObservers',
      'builder',
      'onGenerateTitle',
      'color',
      'theme',
      'darkTheme',
      'highContrastTheme',
      'highContrastDarkTheme',
      'themeMode',
      'themeAnimationDuration',
      'themeAnimationCurve',
      'locale',
      'localizationsDelegates',
      'localeListResolutionCallback',
      'localeResolutionCallback',
      'supportedLocales',
      'debugShowMaterialGrid',
      'showPerformanceOverlay',
      'showSemanticsDebugger',
      'debugShowCheckedModeBanner',
      'shortcuts',
      'actions',
      'restorationScopeId',
      'scrollBehavior',
      'themeAnimationStyle',
      'useInheritedMediaQuery',
      // Debug-overlay toggles — not paywall-relevant.
      'checkerboardRasterCacheImages',
      'checkerboardOffscreenLayers',
      // Theming is intentionally not surfaced. `MaterialApp.theme` takes
      // a structured `ThemeData`; the catalog's decomposition recipes
      // don't yet model the constant ctor args (`useMaterial3: true`)
      // the host typically pairs with a brand colour seed. Tracked as a
      // follow-up; in the meantime the host app's own MaterialApp
      // wraps the rendered paywall and supplies the theme.
    ],
  ),
  // Modal bottom sheet for paywall surfaces. Owns its slide animation
  // and drag-to-dismiss gesture internally (no route, no host
  // `Navigator`) — the composition supplies only the `open` flag,
  // styling, and `child`, and names the `onSheetDismissed` event
  // (`VoidCallback?` shape, distinct from the surface-level `onDismiss`).
  //
  // Deferred from the surface — faithful-or-justified-defer, never a
  // silent or deceptive no-op slot:
  //   - `dragHandleSize: Size?` — excluded below: there is no `Size`
  //     property type in the catalog yet (a structured wire type is
  //     needed). The drag handle's color still flows.
  //   - `constraints: BoxConstraints?` — excluded automatically by the
  //     centralized type denylist (layout primitives don't round-trip
  //     through the wire format), so it is not listed here.
  //   - `requestFocus` — a route-focus concept with no route-free
  //     behavior, so it is deliberately not a constructor parameter at
  //     all; a slot accepting a value that does nothing would be a
  //     silent-fidelity lie.
  BuiltinWidgetCuration<RestageModalSheet>(
    category: WidgetCategory.action,
    fires: [WidgetEventName.onSheetDismissed],
    excludeParams: ['dragHandleSize'],
  ),
  // Multi-page swipeable surface for paged paywall layouts. The pager
  // owns its own `PageController` locally — pages are real Flutter
  // widgets composed in the layout tree, not page-route navigation.
  // `onPageChanged` fires the `ValueChanged<int>` shape.
  BuiltinWidgetCuration<RestagePager>(
    category: WidgetCategory.action,
    fires: [WidgetEventName.onPageChanged],
    propertyOverrides: {
      'onPageChanged': PropertyOverride(
        callbackSignature: 'ValueChanged<int>',
      ),
    },
  ),
  // Persistent, resizable detent sheet (peek → drag/expand → non-closeable).
  // Wraps the framework's draggable scrollable sheet — the drag/snap/fling
  // physics and the scroll-coordination live in compiled code; the blob
  // carries only inert detents, the `expanded` state flag, and the child.
  // No events: it never dismisses (it bottoms out at the minimum detent).
  // It owns no surface of its own — the child supplies the look — so there
  // are no decoration parameters; it is platform-neutral (the underlying
  // sheet has no platform variant).
  //   - `snapSizes: List<double>?` — excluded: the catalog has no
  //     fractional-list property type to express it. Without `snapSizes` the
  //     sheet still snaps between the min and max detents (snapping is fully
  //     functional); only intermediate snap stops are unavailable. A future
  //     fractional-list property type would surface it (tracked follow-up).
  // Single-select radio group. Owns the radio-selection wiring internally
  // (the `RadioGroup` ancestor that flows the group value through the rows);
  // the blob carries only the inert `items` option list, the `selected`
  // state value, and names the settled `onChanged` event. The `items` slot is
  // the bespoke `selectionOptionList` wire shape (a list of `{value, label}`
  // maps) decoded by `RestageDecoders.selectionOptionList`. Curated at
  // `<String>` (the canonical wire-comparable value type); the generic binding
  // is specialized at curation time. The optional styling parameters
  // (`activeColor` / `contentPadding` / `dense`) are excluded in this v1 cut —
  // the widget defaults them; surfacing them is a documented follow-on. This
  // is the first built-in stamped above the baseline content version
  // (`sinceVersion: 2`): it floors only the surfaces that use it.
  BuiltinWidgetCuration<RestageRadioGroup<String>>(
    category: WidgetCategory.input,
    nameOverride: 'RestageRadioGroupString',
    sinceVersion: 2,
    fires: [WidgetEventName.onChanged],
    excludeParams: ['activeColor', 'contentPadding', 'dense'],
    propertyOverrides: {
      // `List<RestageSelectionOption>` is not a mechanically-inferable catalog
      // type, so the override declares it explicitly as the bespoke
      // `selectionOptionList` slot decoded by the option-list decoder.
      'items': PropertyOverride(
        type: PropertyType.selectionOptionList,
        required: true,
      ),
      'onChanged': PropertyOverride(
        callbackSignature: 'ValueChanged<String?>',
      ),
    },
  ),
  // Single-select dropdown. Owns the menu overlay route internally (exactly
  // why the bare Flutter `DropdownButton` stays denylisted — it authors an
  // overlay route a declarative blob cannot express); the blob carries only
  // the inert `items` option list, the `selected` state value, and names the
  // settled `onChanged` event. Same `selectionOptionList` items slot,
  // `<String>` instantiation, and `sinceVersion: 2` floor as the radio group.
  // The optional styling parameters (`hint` / `isExpanded` / `elevation` /
  // `dropdownColor` / `borderRadius`) are excluded in this v1 cut.
  BuiltinWidgetCuration<RestageDropdown<String>>(
    category: WidgetCategory.input,
    nameOverride: 'RestageDropdownString',
    sinceVersion: 2,
    fires: [WidgetEventName.onChanged],
    excludeParams: [
      'hint',
      'isExpanded',
      'elevation',
      'dropdownColor',
      'borderRadius',
    ],
    propertyOverrides: {
      'items': PropertyOverride(
        type: PropertyType.selectionOptionList,
        required: true,
      ),
      'onChanged': PropertyOverride(
        callbackSignature: 'ValueChanged<String?>',
      ),
    },
  ),
  // Multi-toggle button set. Each `children` entry is one button's label (the
  // existing widget-list slot); the parallel `isSelected` list gives each
  // button's pressed state by index (the bespoke `booleanList` wire shape
  // decoded by `RestageDecoders.booleanList`); pressing a button names the
  // settled `onPressed` event with that button's index. The wrapper owns the
  // cross-slot length reconciliation (a mismatched `children`/`isSelected`
  // wire is padded/truncated, never a framework-assert crash) — the
  // length-pairing fail-safe the framework `ToggleButtons` cannot express
  // declaratively. Shares the new content-version floor (`sinceVersion: 3`)
  // with this batch: it floors only the surfaces that use it. The optional
  // styling parameters (`color` / `selectedColor` / `fillColor` / `borderColor`
  // / `borderRadius` / `borderWidth` / `constraints` / …) are excluded in this
  // v1 cut — the widget defaults them; surfacing them is a documented
  // follow-on.
  BuiltinWidgetCuration<RestageToggleButtons>(
    category: WidgetCategory.input,
    sinceVersion: 3,
    fires: [WidgetEventName.onPressed],
    propertyOverrides: {
      // `List<bool>` is not a mechanically-inferable catalog type, so the
      // override declares it explicitly as the bespoke `booleanList` slot
      // decoded by the boolean-list decoder.
      'isSelected': PropertyOverride(
        type: PropertyType.booleanList,
        required: true,
      ),
      'onPressed': PropertyOverride(
        callbackSignature: 'ValueChanged<int>',
      ),
    },
  ),
  // Segmented button (single- or multi-select). Owns the framework
  // `SegmentedButton`'s `Set`-driven selection internally (a `Set` is not a
  // wire-safe value); the blob carries only the inert `items` option list and
  // the `selected` value list, and names the settled `onChanged` event. The
  // `items` slot is the bespoke `selectionOptionList` wire shape (a list of
  // `{value, label}` maps) decoded by `RestageDecoders.selectionOptionList`,
  // shared with the radio group / dropdown. The `selected` slot is a plain
  // `stringList` of the selected values (the wire carries a `List`; the widget
  // materializes the `Set`). The settled `onChanged` fires the whole selection
  // as one `List` in segment order — the first list-valued event shape, carried
  // by the `ValueChanged<List<String>>` callback signature. Curated at
  // `<String>` (the canonical wire-comparable value type). The optional styling
  // (`style` / `expandedInsets` / `selectedIcon` / `direction`) is excluded in
  // this v1 cut — the widget defaults it; surfacing it is a documented
  // follow-on. Shares the new content-version floor (`sinceVersion: 4`) with
  // this batch: it floors only the surfaces that use it.
  BuiltinWidgetCuration<RestageSegmentedButton<String>>(
    category: WidgetCategory.input,
    nameOverride: 'RestageSegmentedButtonString',
    sinceVersion: 4,
    fires: [WidgetEventName.onChanged],
    propertyOverrides: {
      // `List<RestageSelectionOption>` is not a mechanically-inferable catalog
      // type, so the override declares it explicitly as the bespoke
      // `selectionOptionList` slot decoded by the option-list decoder.
      'items': PropertyOverride(
        type: PropertyType.selectionOptionList,
        required: true,
      ),
      // `List<String>` (the selected values) is not auto-inferred to a catalog
      // type, so the override declares it as the plain `stringList` slot.
      'selected': PropertyOverride(type: PropertyType.stringList),
      'onChanged': PropertyOverride(
        callbackSignature: 'ValueChanged<List<String>>',
      ),
    },
  ),
  BuiltinWidgetCuration<RestageDraggableSheet>(
    category: WidgetCategory.action,
    excludeParams: ['snapSizes'],
  ),
  BuiltinWidgetCuration<OutlinedButton>(
    category: WidgetCategory.action,
    fires: [WidgetEventName.onPressed],
    excludeParams: _kSharedButtonExcludeParams,
    synthetics: [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'foregroundColor',
        type: PropertyType.color,
        description: 'Foreground color (text + icons).',
        defaultBrandToken: 'primary',
      ),
      _kButtonPaddingSynthetic,
      _kButtonShapeSynthetic,
      ..._kButtonStyleSizeSynthetics,
      _kButtonDisabledSynthetic,
    ],
    nativeDecomposes: [kTransparentButtonStyleNativeDecompose],
  ),
  // `OutlinedButton.icon` separates the icon and label into two named
  // widget slots — neither is a `child:` slot, so `childrenSlot` falls
  // through to `none` (the schema's `single` is reserved for widgets
  // with a canonical `child:` argument). Flutter declares `icon:` as
  // `Widget?` (optional) but the paywall surface treats it as required.
  // The factory constructor shares its dartdoc with the parent class.
  BuiltinWidgetCuration<OutlinedButton>(
    category: WidgetCategory.action,
    constructorName: 'icon',
    descriptionOverride:
        'A secondary call-to-action button with a leading icon.',
    fires: [WidgetEventName.onPressed],
    excludeParams: [..._kSharedButtonExcludeParams, 'iconAlignment'],
    propertyOverrides: {
      'icon': PropertyOverride(required: true),
    },
    synthetics: [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'foregroundColor',
        type: PropertyType.color,
        description: 'Foreground color (text + icons).',
        defaultBrandToken: 'primary',
      ),
      _kButtonPaddingSynthetic,
      _kButtonShapeSynthetic,
      ..._kButtonStyleSizeSynthetics,
      _kButtonDisabledSynthetic,
    ],
    nativeDecomposes: [kTransparentButtonStyleNativeDecompose],
  ),
  // Slot binding for paywall product surfaces — pairs an opaque slot
  // identifier with a child UI tree. The slot is resolved at runtime
  // against the host app's product configuration; the child renders
  // verbatim and reads the matched product's price + metadata via the
  // standard helpers. Both `slot` and `child` are required.
  BuiltinWidgetCuration<Package>(
    category: WidgetCategory.action,
  ),
  BuiltinWidgetCuration<Scaffold>(
    category: WidgetCategory.layout,
    excludeParams: [
      // `appBar: PreferredSizeWidget` and `drawerDragStartBehavior:
      // DragStartBehavior` are excluded via the centralized type
      // denylist.
      //
      // The `appBar` slot is also not surfaced for a runtime reason:
      // the rendering layer wraps user widgets in a proxy stand-in —
      // a static `as PreferredSizeWidget?` cast fails at runtime even
      // when the underlying widget implements `PreferredSizeWidget`.
      // Re-exposing it cleanly needs a runtime wrap helper; tracked
      // as a follow-up.
      'floatingActionButton',
      'floatingActionButtonLocation',
      'floatingActionButtonAnimator',
      'persistentFooterButtons',
      'persistentFooterAlignment',
      'drawer',
      'onDrawerChanged',
      'endDrawer',
      'onEndDrawerChanged',
      'bottomNavigationBar',
      'bottomSheet',
      'resizeToAvoidBottomInset',
      'primary',
      'extendBody',
      'extendBodyBehindAppBar',
      'drawerScrimColor',
      'drawerEdgeDragWidth',
      'drawerEnableOpenDragGesture',
      'endDrawerEnableOpenDragGesture',
      'restorationId',
      'bottomSheetScrimBuilder',
      'drawerBarrierDismissible',
    ],
    brandTokens: {'backgroundColor': 'background'},
  ),
  // Wraps a scrollable child (typically `SingleChildScrollView` /
  // `ListView` from the core library once those land). `controller` is
  // excluded (`ScrollController` not catalog-modeled); `radius` (the
  // thumb `Radius`) and `notificationPredicate` (function type) are
  // unsupported. `scrollbarOrientation` enum is uncommon — skipped to
  // keep the inspector lean.
  BuiltinWidgetCuration<Scrollbar>(
    category: WidgetCategory.layout,
    excludeParams: [
      // `controller: ScrollController` is excluded via the centralized
      // type denylist (suffix `Controller`).
      'notificationPredicate',
      'scrollbarOrientation',
    ],
    propertyOverrides: {
      'thickness': PropertyOverride(type: PropertyType.length),
    },
  ),
  // Stateful scalar input — same pattern as `Switch.value` / `Checkbox.value`:
  // a required `value: double` plus an `onChanged: ValueChanged<double>?`
  // event. Flutter declares both `required`; the catalog treats
  // `onChanged` as optional (null = disabled), `value` stays required
  // (no sensible default). `label` is `String?` — shown inside the
  // value-indicator bubble, surfaces as a plain string property.
  BuiltinWidgetCuration<Slider>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onChanged],
    excludeParams: [
      // `focusNode: FocusNode` and `mouseCursor: MouseCursor` are
      // excluded via the centralized type denylist.
      'onChangeStart',
      'onChangeEnd',
      'activeColor',
      'inactiveColor',
      'secondaryActiveColor',
      'thumbColor',
      'overlayColor',
      'semanticFormatterCallback',
      'autofocus',
      'allowedInteraction',
      'padding',
      'showValueIndicator',
      // Deprecated in v3.27.0-0.2.pre in favour of the 2024 appearance.
      'year2023',
    ],
    propertyOverrides: {
      'onChanged': PropertyOverride(
        required: false,
        callbackSignature: 'ValueChanged<double>',
      ),
    },
  ),
  // `Switch.activeColor` was deprecated in Flutter 3.31 in favour of
  // `activeThumbColor`; the catalog surfaces only `activeThumbColor` so
  // the codegen factory function stops referencing the deprecated arg.
  BuiltinWidgetCuration<Switch>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onChanged],
    excludeParams: [
      // `focusNode: FocusNode`, `mouseCursor: MouseCursor`, and
      // `dragStartBehavior: DragStartBehavior` are excluded via the
      // centralized type denylist.
      'activeColor',
      'activeTrackColor',
      'inactiveThumbColor',
      'inactiveTrackColor',
      'activeThumbImage',
      'onActiveThumbImageError',
      'inactiveThumbImage',
      'onInactiveThumbImageError',
      'thumbColor',
      'trackColor',
      'trackOutlineColor',
      'trackOutlineWidth',
      'thumbIcon',
      'materialTapTargetSize',
      'focusColor',
      'hoverColor',
      'overlayColor',
      'splashRadius',
      'onFocusChange',
      'autofocus',
      'padding',
    ],
    brandTokens: {'activeThumbColor': 'primary'},
    propertyOverrides: {
      'onChanged': PropertyOverride(callbackSignature: 'ValueChanged<bool>'),
    },
  ),
  // Composed `Switch` + `ListTile` row. Mirrors the `Switch` brand
  // tokens and onChanged callback signature. `title` / `subtitle` /
  // `secondary` are non-canonical `Widget?` slots beyond the implicit
  // switch.
  BuiltinWidgetCuration<SwitchListTile>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onChanged],
    excludeParams: [
      ..._kSharedListTileExcludeParams,
      // `dragStartBehavior: DragStartBehavior` is excluded via the
      // centralized type denylist.
      // Deprecated in v3.31.0-2.0.pre in favour of `activeThumbColor`
      // (mirrors the `Switch` curation upstream).
      'activeColor',
      'activeTrackColor',
      'inactiveThumbColor',
      'inactiveTrackColor',
      'activeThumbImage',
      'onActiveThumbImageError',
      'inactiveThumbImage',
      'onInactiveThumbImageError',
      'thumbColor',
      'trackColor',
      'trackOutlineColor',
      'thumbIcon',
      'selected',
    ],
    brandTokens: {'activeThumbColor': 'primary'},
    propertyOverrides: {
      'onChanged': PropertyOverride(callbackSignature: 'ValueChanged<bool>'),
    },
  ),
  BuiltinWidgetCuration<TextButton>(
    category: WidgetCategory.action,
    fires: [WidgetEventName.onPressed],
    excludeParams: [..._kSharedButtonExcludeParams, 'isSemanticButton'],
    synthetics: [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'foregroundColor',
        type: PropertyType.color,
        description: 'Foreground color (text + icons).',
        defaultBrandToken: 'primary',
      ),
      _kButtonPaddingSynthetic,
      _kButtonShapeSynthetic,
      ..._kButtonStyleSizeSynthetics,
      _kButtonDisabledSynthetic,
    ],
    nativeDecomposes: [kTransparentButtonStyleNativeDecompose],
  ),
  // Same `OutlinedButton.icon`-style icon+label split — neither slot is
  // a canonical `child:`, so `childrenSlot` falls through to `none`.
  BuiltinWidgetCuration<TextButton>(
    category: WidgetCategory.action,
    constructorName: 'icon',
    descriptionOverride: 'A low-emphasis text-only button with a leading icon.',
    fires: [WidgetEventName.onPressed],
    excludeParams: [..._kSharedButtonExcludeParams, 'iconAlignment'],
    propertyOverrides: {
      'icon': PropertyOverride(required: true),
    },
    synthetics: [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'foregroundColor',
        type: PropertyType.color,
        description: 'Foreground color (text + icons).',
        defaultBrandToken: 'primary',
      ),
      _kButtonPaddingSynthetic,
      _kButtonShapeSynthetic,
      ..._kButtonStyleSizeSynthetics,
      _kButtonDisabledSynthetic,
    ],
    nativeDecomposes: [kTransparentButtonStyleNativeDecompose],
  ),
  // `Tab` is the leaf used inside `TabBar.tabs` — the constructor
  // asserts at least one of `text` / `child` / `icon` is non-null.
  // The catalog surfaces all three as optional; misuse surfaces as a
  // render-time assert.
  BuiltinWidgetCuration<Tab>(
    category: WidgetCategory.layout,
    propertyOverrides: {
      'height': PropertyOverride(type: PropertyType.length),
    },
  ),
  // Free-form text input. Ships with both `onChanged` and `onSubmitted`
  // (symmetric with `CupertinoTextField`). `decoration` is the
  // structured `InputDecoration` parameter and is intentionally
  // excluded: no decomposition recipe exists yet, and the bare-input
  // shape covers paywall surveys / promo codes. Richer decoration
  // (`label`, `border`, `prefixIcon`, `errorText`, ...) is a separate
  // schema-gap escalation if customer demand surfaces.
  BuiltinWidgetCuration<TextField>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onChanged, WidgetEventName.onSubmitted],
    propertyOverrides: {
      'onChanged': PropertyOverride(callbackSignature: 'ValueChanged<String>'),
      'onSubmitted': PropertyOverride(
        callbackSignature: 'ValueChanged<String>',
      ),
    },
    excludeParams: [
      // `controller: TextEditingController`, `focusNode: FocusNode`,
      // `undoController: UndoHistoryController`,
      // `statesController: WidgetStatesController`,
      // `mouseCursor: MouseCursor`, `dragStartBehavior: DragStartBehavior`,
      // `scrollController: ScrollController`, `scrollPhysics: ScrollPhysics`,
      // `contentInsertionConfiguration: ContentInsertionConfiguration`,
      // `contextMenuBuilder: EditableTextContextMenuBuilder`,
      // `spellCheckConfiguration: SpellCheckConfiguration`, and
      // `magnifierConfiguration: TextMagnifierConfiguration`
      // are excluded via the centralized type denylist.
      'groupId',
      'decoration',
      'keyboardType',
      'textInputAction',
      'textCapitalization',
      'strutStyle',
      'textAlign',
      'textAlignVertical',
      'textDirection',
      'readOnly',
      // Deprecated in v3.3.0-0.5.pre in favour of `contextMenuBuilder`.
      'toolbarOptions',
      'showCursor',
      'autofocus',
      'obscuringCharacter',
      'autocorrect',
      'smartDashesType',
      'smartQuotesType',
      'enableSuggestions',
      'minLines',
      'expands',
      'maxLengthEnforcement',
      'onEditingComplete',
      'onAppPrivateCommand',
      'inputFormatters',
      'enabled',
      'ignorePointers',
      'cursorWidth',
      'cursorHeight',
      'cursorOpacityAnimates',
      'cursorColor',
      'cursorErrorColor',
      'selectionHeightStyle',
      'selectionWidthStyle',
      'keyboardAppearance',
      'scrollPadding',
      'enableInteractiveSelection',
      'selectAllOnFocus',
      'selectionControls',
      'onTap',
      'onTapAlwaysCalled',
      'onTapOutside',
      'onTapUpOutside',
      'buildCounter',
      'autofillHints',
      'restorationId',
      // Deprecated in v3.27.0-0.2.pre in favour of `stylusHandwritingEnabled`.
      'scribbleEnabled',
      'stylusHandwritingEnabled',
      'enableIMEPersonalizedLearning',
      'canRequestFocus',
      'hintLocales',
    ],
  ),
  // Accessibility / long-press hint shown above the wrapped `child`.
  // `richMessage: InlineSpan?` is excluded (`InlineSpan` has no
  // decomposition recipe today); the constructor asserts exactly one
  // of `message` / `richMessage` is non-null, so with `richMessage`
  // out, `message` is effectively required — the override surfaces
  // that at the catalog layer so a missing message fails in the
  // editor / validator rather than at render time. `child` is the
  // canonical anchor slot. Layout / timing / cursor / theme knobs
  // are excluded to keep the inspector lean.
  BuiltinWidgetCuration<Tooltip>(
    category: WidgetCategory.decoration,
    propertyOverrides: {
      'message': PropertyOverride(required: true),
    },
    excludeParams: [
      'richMessage',
      // Deprecated in v3.30.0-0.1.pre in favour of `constraints`.
      'height',
      'constraints',
      'verticalOffset',
      'excludeFromSemantics',
      'textAlign',
      'waitDuration',
      'showDuration',
      'exitDuration',
      'enableTapToDismiss',
      'triggerMode',
      'enableFeedback',
      'onTriggered',
      'mouseCursor',
      'ignorePointer',
      'positionDelegate',
    ],
  ),
];
