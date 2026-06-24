/// Property value types the catalog supports.
///
/// Authored on each `PropertyEntry` in the per-library registry and
/// inferred from a customer field's static Dart type at codegen time.
/// Consumed by the editor inspector and the codegen AST validator.
enum PropertyType {
  /// A nested widget (single-child slot).
  widget,

  /// A list of nested widgets (list-child slot).
  widgetList,

  /// A color value, typically a 32-bit ARGB int.
  color,

  /// A length / dimension (`double`), e.g. width, height, padding.
  length,

  /// An `EdgeInsets`-like value (top/right/bottom/left).
  edgeInsets,

  /// An `AlignmentGeometry` value (e.g. center, topLeft). Decoded via
  /// rfw's `alignment` decoder, which returns the `AlignmentGeometry`
  /// base (a `{x, y}` map yields an `Alignment`; a named member may yield
  /// an `AlignmentDirectional`).
  alignment,

  /// A concrete `Alignment` value, decoded from a `{x, y}` map.
  ///
  /// Distinct from [alignment]: some constructor parameters are typed with
  /// the concrete `Alignment` subtype (e.g. `AnimatedScale.alignment`,
  /// `AnimatedRotation.alignment`) and cannot accept the `AlignmentGeometry`
  /// base that the [alignment] decoder returns. This member marks the slot
  /// so the codegen emits the concrete-`Alignment` decoder
  /// (`RestageDecoders.alignmentXY`) and an `Alignment.<member>` default.
  alignmentXY,

  /// An `Offset` value, decoded from a `{x, y}` map.
  ///
  /// Used for constructor parameters typed with the concrete `Offset`
  /// (e.g. `AnimatedSlide.offset`). This member marks the slot so the codegen
  /// emits the `Offset` decoder (`RestageDecoders.offset`) and an `Offset.zero`
  /// default. The on-wire shape `{x: double, y: double}` matches rfw's
  /// `offset` decoder and the codegen's `Offset(x, y)` lowering.
  offset,

  /// A `FontWeight` value.
  fontWeight,

  /// A `Duration` value. Encoded on the wire as an integer count of
  /// milliseconds; decoded at runtime to a `Duration` via the SDK
  /// helper. Used for animation duration parameters
  /// (e.g. `AnimatedContainer.duration`).
  duration,

  /// A Flutter `Curve` value. Encoded on the wire as a string naming a
  /// closed set of supported `Curves.*` constants and decoded at runtime
  /// via Restage's SDK helper.
  curve,

  /// A boolean flag.
  boolean,

  /// An integer scalar.
  integer,

  /// A floating-point scalar (`double`).
  real,

  /// A string literal.
  string,

  /// A list of string literals.
  stringList,

  /// A list of boolean literals (e.g. `ToggleButtons.isSelected`, a per-child
  /// selection flag list).
  booleanList,

  /// A reference to a `WidgetEventName` event handler.
  event,

  /// A reference to runtime data (e.g. product price, user state).
  dataReference,

  /// A value of a Dart `enum` declared by the widget package.
  enumValue,

  /// A `Gradient` value (`LinearGradient`, `RadialGradient`, etc.).
  /// The wire format is a map matching the rfw `gradient` decoder
  /// (`{type: 'linear' | 'radial' | 'sweep', ...}`).
  gradient,

  /// A `BoxBorder` value (`Border`, `BorderDirectional`). The wire
  /// format is a list of up to four `BorderSide` maps matching the
  /// rfw `border` decoder (start / top / end / bottom positions).
  border,

  /// A list of `BoxShadow` values. The wire format is a list of maps
  /// matching the rfw `boxShadow` decoder (`{color, offset, blurRadius,
  /// spreadRadius}` per entry).
  boxShadowList,

  /// A `Locale` value.
  locale,

  /// A `Paint` value.
  paint,

  /// A list of `Shadow` values.
  shadowList,

  /// A list of `FontFeature` values.
  fontFeatureList,

  /// A list of `FontVariation` values.
  fontVariationList,

  /// A `TextDecoration` value.
  textDecoration,

  /// A `ShapeBorder` / `OutlinedBorder` value.
  ///
  /// The wire format is a map with a `type` discriminator and
  /// variant-specific scalar fields, decoded by Restage's runtime
  /// shape-border decoder.
  shapeBorder,

  /// A value of a structured type declared elsewhere in the catalog
  /// (e.g. a `BoxDecoration`, `TextStyle`, or `BorderRadius` value).
  /// The owning property or structured-field entry carries a
  /// `structuredRef` pointing at the target structured entry's wire
  /// ID — that reference is the authoritative pointer; this enum
  /// member only marks the slot as structured.
  ///
  /// Introduced as an additive enum member: future schema versions
  /// can land new members the same way without breaking older
  /// decoder builds (unknown names fall back to [unknown]).
  structured,

  /// An `InlineSpan` tree (a `Text.rich` / `TextSpan` value). The wire format
  /// is a single recursive span map — an optional `text`, an optional nested
  /// `TextStyle` field map, and an optional `children` list of further span
  /// maps — decoded at runtime by Restage's recursive, depth-bounded
  /// inline-span decoder into a real `InlineSpan`.
  ///
  /// Like [boxShadowList] / [shapeBorder] / [gradient], it is a complex
  /// map-shaped slot whose structure lives in the bespoke decoder, not in a
  /// recursive schema structured-type. It carries no `structuredRef`. Added as
  /// an additive member (unknown names fall back to [unknown]).
  inlineSpan,

  /// A `DecorationImage` value (a `BoxDecoration.image` background image). The
  /// wire format is a self-describing map: a nested `image` provider map
  /// (`{kind: 'network' | 'asset', src: <string>}`) plus the optional `fit`,
  /// `alignment` (`{x, y}`), `repeat`, `opacity`, and `scale` fields — decoded
  /// at runtime by Restage's image decoder into a real `DecorationImage`.
  ///
  /// Like [inlineSpan] / [gradient] / [shapeBorder], it is a complex map-shaped
  /// slot whose structure lives in the bespoke decoder, not in a recursive
  /// schema structured-type. It carries no `structuredRef`. Added as an
  /// additive member (unknown names fall back to [unknown]).
  decorationImage,

  /// An ordered list of single-select options — each a `{value, label}` map
  /// (`value` = the wire-comparable selection scalar; `label` = the option's
  /// display string). The slot for a compiled single-select widget's `items`
  /// (radio group / dropdown). The wire format is a list of two-field maps,
  /// decoded at runtime by Restage's selection-option decoder into a list of
  /// option records.
  ///
  /// Like [inlineSpan] / [decorationImage] / [gradient] / [shapeBorder], it is
  /// a complex map-shaped slot whose structure lives in the bespoke decoder,
  /// not in a recursive schema structured-type. It carries no `structuredRef`.
  /// Added as an additive member (unknown names fall back to [unknown]).
  selectionOptionList,

  /// Sentinel emitted by the decoder when a JSON payload carries a
  /// [PropertyType] name this build doesn't recognize. Downstream
  /// consumers should treat as opaque and skip without throwing —
  /// new enum members can land additively in newer catalog schemas.
  unknown,
}
