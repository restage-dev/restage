/// Curation file for the `restage.cupertino` widget library — Cupertino
/// (Apple HIG) widgets curated for paywall composition.
///
/// Authors specify only what cannot be derived from a Flutter widget's
/// constructor signature: the catalog [WidgetCategory], parameter
/// exclusions for params the catalog does not surface, brand-token
/// defaults, paywall event mappings, and per-property overrides for
/// renames or non-mechanical defaults. The reflector fills in the rest
/// by walking each constructor parameter (name, type, dartdoc,
/// required-flag, literal default).
///
/// **Brand-token resolution.** Brand tokens (`primary`, `background`)
/// resolve against `CupertinoThemeData` slots (`primaryColor`,
/// `scaffoldBackgroundColor`) at runtime. The token vocabulary is
/// shared with `restage.material` so the same paywall design renders
/// with either theme.
library;

import 'package:flutter/cupertino.dart';
import 'package:restage_shared/restage_shared.dart';

// Shared exclusion list for both `CupertinoButton` ctors. Hoisted so the
// `default` and `.filled` variants stay in lockstep — adding a newly-
// surfaced param to one variant without the other would silently
// diverge their catalog surfaces.
//
// `focusNode: FocusNode` and `mouseCursor: MouseCursor` are excluded
// via the centralized type denylist (suffix `Node` and `MouseCursor`
// respectively).
const _kCupertinoButtonExcludes = [
  'sizeStyle',
  'foregroundColor',
  'disabledColor',
  'minSize',
  'minimumSize',
  'pressedOpacity',
  'borderRadius',
  'alignment',
  'focusColor',
  'onFocusChange',
  'autofocus',
  'onLongPress',
];

// Synthetic catalog property shared by both `CupertinoButton` ctors.
// `gateOnPressed` instructs the codegen emitter to translate
// `disabled: true` into `onPressed: null` (Cupertino buttons have no
// `disabled:` constructor argument).
const _kCupertinoButtonDisabledSynthetic = PropertyEntry(
  wireId: WireId.unallocatedProperty,
  name: 'disabled',
  type: PropertyType.boolean,
  description: 'Whether the button is disabled.',
  defaultSource: LiteralDefault(false),
  synthetic: 'gateOnPressed',
);

// Shared exclusion list for both `CupertinoListSection` ctors —
// `default` and `.insetGrouped` curate to the same property surface.
//
// `decoration: BoxDecoration?` flows through the structured walker as
// a concrete-whitelist placeholder; it is no longer pinned out of the
// catalog here.
const _kCupertinoListSectionExcludes = [
  'margin',
  // Non-nullable `Color` on the Flutter ctor (defaulted to
  // `CupertinoColors.systemGroupedBackground`); the catalog has no way
  // to express a const Color default today, so leaving it null in the
  // emitted factory would fail to satisfy the ctor parameter.
  'backgroundColor',
  'dividerMargin',
  'additionalDividerMargin',
  'topMargin',
  'hasLeading',
  'separatorColor',
];

/// Curation list consumed by `BuiltinCurationBuilder` to emit
/// `lib/registry.dart` and `lib/src/widget_catalog/catalog.json`.
@RestageBuiltinLibrary(library: WidgetLibrary.cupertino, version: '0.1.0')
const List<BuiltinWidgetCuration> kCuration = [
  BuiltinWidgetCuration<CupertinoActivityIndicator>(
    category: WidgetCategory.decoration,
    // `radius` is typed `double` on the Flutter constructor; tag it as
    // PropertyType.length so the editor inspector gets the logical-pixel
    // hint. Codegen treats length and real identically.
    propertyOverrides: {
      'radius': PropertyOverride(type: PropertyType.length),
    },
  ),
  // `onPressed` is `required this.onPressed` on the Flutter ctor but
  // typed `VoidCallback?` — passing `null` is the documented way to
  // disable the button, so the catalog surfaces it as optional and
  // relies on the `disabled` synthetic to translate the catalog-level
  // optional into the ctor-level null at codegen time.
  BuiltinWidgetCuration<CupertinoButton>(
    category: WidgetCategory.action,
    fires: [WidgetEventName.onPressed],
    excludeParams: _kCupertinoButtonExcludes,
    propertyOverrides: {
      'onPressed': PropertyOverride(required: false),
    },
    synthetics: [_kCupertinoButtonDisabledSynthetic],
  ),
  BuiltinWidgetCuration<CupertinoButton>(
    category: WidgetCategory.action,
    constructorName: 'filled',
    nameOverride: 'CupertinoButtonFilled',
    descriptionOverride: 'A filled Cupertino call-to-action button.',
    fires: [WidgetEventName.onPressed],
    excludeParams: _kCupertinoButtonExcludes,
    brandTokens: {'color': 'primary'},
    propertyOverrides: {
      'onPressed': PropertyOverride(required: false),
    },
    synthetics: [_kCupertinoButtonDisabledSynthetic],
  ),
  BuiltinWidgetCuration<CupertinoListSection>(
    category: WidgetCategory.layout,
    excludeParams: _kCupertinoListSectionExcludes,
  ),
  BuiltinWidgetCuration<CupertinoListSection>(
    category: WidgetCategory.layout,
    constructorName: 'insetGrouped',
    nameOverride: 'CupertinoListSectionInsetGrouped',
    descriptionOverride: 'Inset-rounded variant of CupertinoListSection.',
    excludeParams: _kCupertinoListSectionExcludes,
  ),
  BuiltinWidgetCuration<CupertinoListTile>(
    category: WidgetCategory.layout,
    fires: [WidgetEventName.onTap],
    excludeParams: [
      'additionalInfo',
      'backgroundColorActivated',
      'padding',
      'leadingSize',
      'leadingToTitle',
    ],
  ),
  BuiltinWidgetCuration<CupertinoNavigationBar>(
    category: WidgetCategory.layout,
    excludeParams: [
      'automaticallyImplyLeading',
      'automaticallyImplyMiddle',
      'previousPageTitle',
      'automaticBackgroundVisibility',
      'enableBackgroundFilterBlur',
      'brightness',
      'padding',
      'transitionBetweenRoutes',
      'heroTag',
      'bottom',
    ],
    brandTokens: {'backgroundColor': 'background'},
  ),
  // `navigationBar` is excluded because Flutter types it as
  // `ObstructingPreferredSizeWidget?` — the rendering layer's proxy
  // wrap defeats the static downcast strategy (same blocker as
  // `Scaffold.appBar`).
  BuiltinWidgetCuration<CupertinoPageScaffold>(
    category: WidgetCategory.layout,
    excludeParams: [
      'navigationBar',
      'resizeToAvoidBottomInset',
    ],
    brandTokens: {'backgroundColor': 'background'},
  ),
  // `onChanged` is `required this.onChanged` on the Flutter ctor but
  // typed `ValueChanged<bool>?` — same pattern as `CupertinoButton`'s
  // `onPressed` above. The `callbackSignature` override keeps the
  // codegen / runtime aware of the bool payload (the reflector emits
  // a bare-VoidCallback signature otherwise).
  BuiltinWidgetCuration<CupertinoSwitch>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onChanged],
    excludeParams: [
      // `focusNode: FocusNode`, `mouseCursor: MouseCursor`, and
      // `dragStartBehavior: DragStartBehavior` are excluded via the
      // centralized type denylist.
      'activeColor',
      'trackColor',
      'inactiveTrackColor',
      'thumbColor',
      'inactiveThumbColor',
      'applyTheme',
      'focusColor',
      'onLabelColor',
      'offLabelColor',
      'activeThumbImage',
      'onActiveThumbImageError',
      'inactiveThumbImage',
      'onInactiveThumbImageError',
      'trackOutlineColor',
      'trackOutlineWidth',
      'thumbIcon',
      'onFocusChange',
      'autofocus',
    ],
    brandTokens: {'activeTrackColor': 'primary'},
    propertyOverrides: {
      'onChanged': PropertyOverride(
        required: false,
        callbackSignature: 'ValueChanged<bool>',
      ),
    },
  ),
  // `onChanged` and `onSubmitted` are both typed `ValueChanged<String>?`
  // on the Flutter ctor. The `callbackSignature` overrides keep the
  // codegen / runtime aware of the typed payload (the reflector emits
  // a bare-VoidCallback signature otherwise, and the factory emitter
  // silently drops non-void event properties without a callbackSignature).
  BuiltinWidgetCuration<CupertinoTextField>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onChanged, WidgetEventName.onSubmitted],
    propertyOverrides: {
      'onChanged': PropertyOverride(
        callbackSignature: 'ValueChanged<String>',
      ),
      'onSubmitted': PropertyOverride(
        callbackSignature: 'ValueChanged<String>',
      ),
    },
    excludeParams: [
      // `controller: TextEditingController`, `focusNode: FocusNode`,
      // `undoController: UndoHistoryController`,
      // `dragStartBehavior: DragStartBehavior`,
      // `scrollController: ScrollController`,
      // `scrollPhysics: ScrollPhysics`,
      // `contentInsertionConfiguration: ContentInsertionConfiguration`,
      // `contextMenuBuilder: EditableTextContextMenuBuilder`,
      // `spellCheckConfiguration: SpellCheckConfiguration`, and
      // `magnifierConfiguration: TextMagnifierConfiguration`
      // are excluded via the centralized type denylist.
      'groupId',
      'padding',
      'prefix',
      'prefixMode',
      'suffix',
      'suffixMode',
      'crossAxisAlignment',
      'clearButtonMode',
      'clearButtonSemanticLabel',
      'keyboardType',
      'textInputAction',
      'textCapitalization',
      'strutStyle',
      'textAlign',
      'textAlignVertical',
      'textDirection',
      'readOnly',
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
      'onTapOutside',
      'onTapUpOutside',
      'inputFormatters',
      'enabled',
      'cursorWidth',
      'cursorHeight',
      'cursorOpacityAnimates',
      'cursorColor',
      'selectionHeightStyle',
      'selectionWidthStyle',
      'keyboardAppearance',
      'scrollPadding',
      'enableInteractiveSelection',
      'selectAllOnFocus',
      'selectionControls',
      'onTap',
      'autofillHints',
      'restorationId',
      'scribbleEnabled',
      'stylusHandwritingEnabled',
      'enableIMEPersonalizedLearning',
    ],
  ),
  // Same `required this.onChanged but typed `ValueChanged<T>?`` shape
  // as `CupertinoSwitch` above (double payload instead of bool).
  // `thumbColor` defaults to a non-nullable `CupertinoColors.white`
  // const the catalog can't express as a primitive default — rely on
  // the runtime Flutter default by excluding. `onChangeStart` /
  // `onChangeEnd` are imperative drag-lifecycle hooks outside the
  // catalog's event taxonomy.
  BuiltinWidgetCuration<CupertinoSlider>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onChanged],
    excludeParams: ['onChangeStart', 'onChangeEnd', 'thumbColor'],
    brandTokens: {'activeColor': 'primary'},
    propertyOverrides: {
      'onChanged': PropertyOverride(
        required: false,
        callbackSignature: 'ValueChanged<double>',
      ),
    },
  ),
  // The DateTime params (`initialDateTime`, `minimumDate`,
  // `maximumDate`) excluded — the catalog has no DateTime
  // PropertyType today, so the runtime default to `now` / no bounds
  // applies. `selectionOverlayBuilder` and `selectableDayPredicate`
  // take imperative callbacks that don't fit declarative serialization.
  // `onDateTimeChanged` is the Flutter ctor name; `firesAs: 'onChanged'`
  // maps it to the catalog's event taxonomy.
  BuiltinWidgetCuration<CupertinoDatePicker>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onChanged],
    excludeParams: [
      'initialDateTime',
      'minimumDate',
      'maximumDate',
      'selectionOverlayBuilder',
      'selectableDayPredicate',
    ],
    brandTokens: {'backgroundColor': 'background'},
    propertyOverrides: {
      'onDateTimeChanged': PropertyOverride(
        firesAs: 'onChanged',
        callbackSignature: 'ValueChanged<DateTime>',
      ),
    },
  ),
  // `initialTimerDuration` defaults to `Duration.zero` — the catalog
  // can't express const Duration defaults as primitive literals today,
  // so excluded; runtime falls back to the Flutter default. `alignment`
  // defaults to `const Alignment.center` which the catalog can't render
  // as a primitive default either — supply the string member name and
  // the codegen interprets it against `AlignmentDirectional` at
  // translation time (same shape as `Stack.alignment` in
  // `restage.core`). `firesAs` on `onTimerDurationChanged` maps the
  // Flutter ctor name onto the catalog's `onChanged` taxonomy.
  BuiltinWidgetCuration<CupertinoTimerPicker>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onChanged],
    excludeParams: ['initialTimerDuration', 'selectionOverlayBuilder'],
    brandTokens: {'backgroundColor': 'background'},
    propertyOverrides: {
      'onTimerDurationChanged': PropertyOverride(
        firesAs: 'onChanged',
        callbackSignature: 'ValueChanged<Duration>',
      ),
      'alignment': PropertyOverride(defaultValue: 'center'),
    },
  ),
  // Generic wheel picker — widget-list `children`, int payload via
  // `onSelectedItemChanged`. `scrollController` excluded by the
  // catalog-wide controller convention; `selectionOverlay` defaults to
  // a const `CupertinoPickerDefaultSelectionOverlay()` the catalog
  // can't express as a primitive default, so customers can't override
  // the overlay through curation today (the Flutter default still
  // renders at runtime). The `.builder` named constructor is not
  // curated — delegate-based child resolution is a separate story
  // (mirrors the `ListView` default-constructor-only precedent).
  // `firesAs` on `onSelectedItemChanged` maps the Flutter ctor name
  // onto the catalog's `onChanged` taxonomy.
  BuiltinWidgetCuration<CupertinoPicker>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onChanged],
    excludeParams: ['scrollController', 'selectionOverlay'],
    brandTokens: {'backgroundColor': 'background'},
    propertyOverrides: {
      'onSelectedItemChanged': PropertyOverride(
        firesAs: 'onChanged',
        callbackSignature: 'ValueChanged<int>',
      ),
    },
  ),
  // Visual styling on top of `TextField` — the exclude list mirrors
  // `CupertinoTextField` above (focus / restoration / scrolling / IME
  // / cursor-styling imperative knobs; structured `TextStyle` /
  // `BoxDecoration` / `BorderRadius` defaults; per-icon const widget
  // defaults). Both `onChanged` and `onSubmitted` fire with the
  // `ValueChanged<String>` typed-payload callback signature.
  BuiltinWidgetCuration<CupertinoSearchTextField>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onChanged, WidgetEventName.onSubmitted],
    excludeParams: [
      // `controller: TextEditingController` and `focusNode: FocusNode`
      // are excluded via the centralized type denylist (exact match and
      // suffix `Node` respectively).
      'keyboardType',
      'padding',
      'itemColor',
      'prefixInsets',
      'prefixIcon',
      'suffixInsets',
      'suffixIcon',
      'suffixMode',
      'onSuffixTap',
      'restorationId',
      'smartQuotesType',
      'smartDashesType',
      'enableIMEPersonalizedLearning',
      'autofocus',
      'onTap',
      'autocorrect',
      'enabled',
      'cursorWidth',
      'cursorHeight',
      'cursorRadius',
      'cursorOpacityAnimates',
      'cursorColor',
    ],
    brandTokens: {'backgroundColor': 'background'},
    propertyOverrides: {
      'onChanged': PropertyOverride(
        callbackSignature: 'ValueChanged<String>',
      ),
      'onSubmitted': PropertyOverride(
        callbackSignature: 'ValueChanged<String>',
      ),
    },
  ),
  // `value: bool?` reads through the reflector as
  // `PropertyType.boolean` (nullability stripped) — it ships binary,
  // not tristate (the catalog can't surface `null` for the mixed
  // state). Same `required this.onChanged but typed
  // `ValueChanged<T>?`` shape as `CupertinoSwitch`, but with the
  // tristate-aware `ValueChanged<bool?>` payload. `inactiveColor` is
  // deprecated upstream; `fillColor` is `WidgetStateProperty<Color?>?`
  // which the catalog can't express; `side` / `shape` are structured
  // border-config knobs deferred.
  BuiltinWidgetCuration<CupertinoCheckbox>(
    category: WidgetCategory.input,
    fires: [WidgetEventName.onChanged],
    excludeParams: [
      // `mouseCursor: MouseCursor` and `focusNode: FocusNode` are
      // excluded via the centralized type denylist. `side: BorderSide?`
      // flows through the structured walker as a flat concrete-whitelist
      // type; `shape: OutlinedBorder?` is a subtype not on the walker
      // whitelist so it stays pinned here.
      'inactiveColor',
      'fillColor',
      'focusColor',
      'autofocus',
      'shape',
      'tapTargetSize',
    ],
    brandTokens: {'activeColor': 'primary'},
    propertyOverrides: {
      'onChanged': PropertyOverride(
        required: false,
        callbackSignature: 'ValueChanged<bool?>',
      ),
    },
  ),
];
