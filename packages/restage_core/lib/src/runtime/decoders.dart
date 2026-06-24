import 'dart:ui' show FontFeature, FontVariation, Offset, Size;

import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/painting.dart'
    show
        Alignment,
        AssetImage,
        BeveledRectangleBorder,
        BorderRadius,
        BorderRadiusGeometry,
        BorderSide,
        BoxFit,
        BoxShadow,
        CircleBorder,
        ContinuousRectangleBorder,
        DecorationImage,
        FontStyle,
        FontWeight,
        ImageProvider,
        ImageRepeat,
        InlineSpan,
        LinearBorder,
        LinearBorderEdge,
        NetworkImage,
        RoundedRectangleBorder,
        RoundedSuperellipseBorder,
        Shadow,
        ShapeBorder,
        StadiumBorder,
        StarBorder,
        TextBaseline,
        TextDecoration,
        TextDecorationStyle,
        TextLeadingDistribution,
        TextOverflow,
        TextSpan,
        TextStyle;
import 'package:flutter/foundation.dart' show immutable;
import 'package:restage_shared/restage_shared.dart' show kMaxInlineSpanDepth;
import 'package:rfw/rfw.dart';

/// Decoders for property types that aren't covered by rfw's built-in
/// [ArgumentDecoders].
///
/// Mirrors the static-method shape of [ArgumentDecoders] so generated
/// factory closures can decode arbitrary property values with a single
/// expression. Each helper reads a value from a flat [DataSource] path
/// and returns a typed Dart value (or `null` when the slot is absent).
///
/// Lives in `restage_core` so the registration files for every curated
/// library (including `restage_material` and `restage_cupertino`) and
/// any customer library generated via `@RestageWidget` can call into a
/// single canonical implementation.
abstract final class RestageDecoders {
  /// Decodes a `Duration` from a flat integer count of milliseconds at
  /// [path] in [source]. Returns `null` when the slot is missing so
  /// callers can choose between a `??` fallback (literal default) and
  /// a `throw` (required-no-default contract).
  ///
  /// The on-wire encoding is `int` milliseconds — the standard
  /// convention for transporting `Duration` through a JSON-shaped data
  /// channel.
  static Duration? duration(DataSource source, List<Object> path) {
    final ms = source.v<int>(path);
    return ms == null ? null : Duration(milliseconds: ms);
  }

  /// Decodes a supported Flutter animation curve from its wire name.
  ///
  /// `Curve` is not a Dart enum, so this helper uses a closed lookup table
  /// instead of accepting arbitrary strings. Unknown names decode to `null`
  /// so the generated factory can fall back to Flutter's documented default.
  static Curve? curve(DataSource source, List<Object> path) {
    final name = source.v<String>(path);
    return name == null ? null : _supportedCurvesByName[name];
  }

  /// Canonical set of supported curve vocabulary names for runtime decoding
  /// and other callers that need to present or validate curve wire names.
  static final Set<String> supportedCurveNames = Set.unmodifiable(
    _supportedCurvesByName.keys,
  );

  /// Decodes a concrete `Alignment` from a `{x, y}` map at [path].
  ///
  /// Distinct from rfw's `ArgumentDecoders.alignment` (which returns the
  /// `AlignmentGeometry` base — it may yield an `AlignmentDirectional` for a
  /// named-member string). Constructors typed with the concrete `Alignment`
  /// subtype (e.g. `AnimatedScale.alignment` / `AnimatedRotation.alignment`)
  /// can't accept an `AlignmentGeometry`, so the catalog routes their slot
  /// through this decoder. The on-wire shape is `{x: double, y: double}` (the
  /// same shape the codegen emits for an alignment value); both components
  /// must be present or the slot decodes to `null` so the caller's contract
  /// (literal default `Alignment.center` / the Flutter ctor default) applies.
  static Alignment? alignmentXY(DataSource source, List<Object> path) {
    final x = _number(source, [...path, 'x']);
    final y = _number(source, [...path, 'y']);
    if (x == null || y == null) return null;
    return Alignment(x, y);
  }

  /// Decodes an `Offset` from a `{x, y}` map at [path].
  ///
  /// The on-wire shape is `{x: double, y: double}` — the same shape rfw's
  /// `offset` decoder reads and the codegen emits for an `Offset(x, y)`
  /// value. Used for concrete `Offset` constructor parameters (e.g.
  /// `AnimatedSlide.offset`). Both components must be present or the slot
  /// decodes to `null` so the caller's contract (literal default
  /// `Offset.zero` / the Flutter ctor default) applies.
  static Offset? offset(DataSource source, List<Object> path) {
    final x = _number(source, [...path, 'x']);
    final y = _number(source, [...path, 'y']);
    if (x == null || y == null) return null;
    return Offset(x, y);
  }

  /// Decodes a `Size` from a `{width, height}` map at [path].
  ///
  /// The on-wire shape is `{width: double, height: double}` — the same shape
  /// the codegen emits for a `Size(width, height)` value. Used for concrete
  /// `Size` slots that surface as a registered structured value (e.g. a
  /// button's `minimumSize` / `fixedSize`). Both components must be present
  /// or the slot decodes to `null` so the caller's contract (literal default
  /// / the Flutter ctor default) applies.
  static Size? size(DataSource source, List<Object> path) {
    final width = _number(source, [...path, 'width']);
    final height = _number(source, [...path, 'height']);
    if (width == null || height == null) return null;
    return Size(width, height);
  }

  /// Decodes a `BorderSide` from a `{color, width, style}` map at [path].
  ///
  /// The on-wire shape is the same `{color, width, style}` map the codegen
  /// emits for a `BorderSide(...)` value (the shape rfw's own `borderSide`
  /// decoder reads, with its color/width/style defaults). Used for concrete
  /// `BorderSide` slots that surface as a registered structured value (e.g. a
  /// button's `side`). Returns `null` when the map is absent so the caller's
  /// contract (literal default / the Flutter ctor default) applies.
  static BorderSide? borderSide(DataSource source, List<Object> path) {
    return ArgumentDecoders.borderSide(source, path);
  }

  /// Decodes a `TextStyle` from its flat map shape at [path].
  ///
  /// The on-wire shape is the same map the codegen emits for a `TextStyle(...)`
  /// value — the flat `TextStyle` decompose encoding (`color`, `fontSize`,
  /// `fontWeight`, …) the `Text(style:)` recipe already produces (and the same
  /// map the inline-span path decodes for a `TextSpan.style`). Used for
  /// concrete `TextStyle` slots that surface as a registered structured value
  /// (e.g. a button's `textStyle`). Returns `null` when the slot is absent so
  /// the caller's contract (the Flutter ctor default) applies.
  static TextStyle? textStyle(DataSource source, List<Object> path) {
    return _textStyle(source, path);
  }

  /// Decodes a nullable `TextDecoration`.
  static TextDecoration? textDecoration(DataSource source, List<Object> path) {
    if (!source.isList(path) && source.v<String>(path) == null) return null;
    return ArgumentDecoders.textDecoration(source, path);
  }

  /// Decodes a list of `Shadow` values using rfw's box-shadow map shape.
  static List<Shadow>? shadows(DataSource source, List<Object> path) {
    final shadows = ArgumentDecoders.list<BoxShadow>(
      source,
      path,
      ArgumentDecoders.boxShadow,
    );
    return shadows == null ? null : List<Shadow>.unmodifiable(shadows);
  }

  /// Decodes Restage's recursive `InlineSpan` wire shape.
  ///
  /// The root slot must be a map and returns `null` when absent, letting the
  /// generated factory enforce required-slot contracts. Malformed child
  /// elements decode to empty terminal spans so one hostile list item cannot
  /// throw out the whole tree.
  static InlineSpan? inlineSpan(DataSource source, List<Object> path) {
    if (!source.isMap(path)) return null;
    return _inlineSpan(source, path, depth: 0);
  }

  /// Decodes Restage's `DecorationImage` wire shape into a real
  /// `DecorationImage` (a `BoxDecoration.image` background).
  ///
  /// The on-wire shape is a self-describing map: a required nested `image`
  /// provider map (`{kind: 'network' | 'asset', src: <string>}`) plus the
  /// optional `fit` / `alignment` (`{x, y}`) / `repeat` / `opacity` / `scale`
  /// fields. Returns `null` when the slot is absent, or when no usable image
  /// provider is present, so the caller's contract (the Flutter ctor default —
  /// no background image) applies rather than constructing a `DecorationImage`
  /// with no provider. Every other field falls back to the `DecorationImage`
  /// constructor's own default when omitted.
  static DecorationImage? decorationImage(
    DataSource source,
    List<Object> path,
  ) {
    if (!source.isMap(path)) return null;
    final provider = _imageProvider(source, [...path, 'image']);
    if (provider == null) return null;
    return DecorationImage(
      image: provider,
      fit: ArgumentDecoders.enumValue<BoxFit>(
        BoxFit.values,
        source,
        [...path, 'fit'],
      ),
      alignment:
          alignmentXY(source, [...path, 'alignment']) ?? Alignment.center,
      repeat: ArgumentDecoders.enumValue<ImageRepeat>(
            ImageRepeat.values,
            source,
            [...path, 'repeat'],
          ) ??
          ImageRepeat.noRepeat,
      opacity: _number(source, [...path, 'opacity']) ?? 1.0,
      scale: _number(source, [...path, 'scale']) ?? 1.0,
    );
  }

  /// Decodes a list of OpenType font features.
  static List<FontFeature>? fontFeatures(
    DataSource source,
    List<Object> path,
  ) {
    return ArgumentDecoders.list<FontFeature>(
      source,
      path,
      ArgumentDecoders.fontFeature,
    );
  }

  /// Decodes a list of OpenType font variation axis values.
  static List<FontVariation>? fontVariations(
    DataSource source,
    List<Object> path,
  ) {
    final count = source.length(path);
    if (count == 0) return null;
    final variations = <FontVariation>[];
    for (var index = 0; index < count; index++) {
      final itemPath = [...path, index];
      final axis = source.v<String>([...itemPath, 'axis']);
      final value = source.v<double>([...itemPath, 'value']) ??
          source.v<int>([...itemPath, 'value'])?.toDouble();
      // Skip malformed entries rather than fabricating a plausible-but-wrong
      // default — a bad item is omitted, consistent with the null-returning
      // siblings that let the caller's contract decide.
      if (axis == null || axis.length != 4 || value == null) continue;
      variations.add(FontVariation(axis, value));
    }
    return variations.isEmpty ? null : variations;
  }

  /// Decodes Restage's shape-border map shape.
  ///
  /// The older rfw decoder covers a subset of the same family, but it
  /// expects border radii in rfw's list-of-radius shape and does not
  /// know Flutter's newer `RoundedSuperellipseBorder`, `LinearBorder`,
  /// or `StarBorder` variants. Restage uses a compact, flat uniform
  /// radius for the representable button/editor surface and decodes the
  /// full supported variant set here.
  static ShapeBorder? shapeBorder(DataSource source, List<Object> path) {
    final count = source.length(path);
    if (count > 0) {
      ShapeBorder? combined;
      for (var i = 0; i < count; i++) {
        final shape = shapeBorder(source, [...path, i]);
        if (shape == null) continue;
        combined = combined == null ? shape : combined + shape;
      }
      return combined;
    }

    final type = source.v<String>([...path, 'type']);
    final side = ArgumentDecoders.borderSide(source, [...path, 'side']) ??
        BorderSide.none;
    switch (type) {
      case null:
        return null;
      case 'rounded':
        return RoundedRectangleBorder(
          side: side,
          borderRadius: _borderRadius(source, [...path, 'borderRadius']),
        );
      case 'roundedSuperellipse':
        return RoundedSuperellipseBorder(
          side: side,
          borderRadius: _borderRadius(source, [...path, 'borderRadius']),
        );
      case 'circle':
        return CircleBorder(
          side: side,
          eccentricity: _number(source, [...path, 'eccentricity']) ?? 0.0,
        );
      case 'stadium':
        return StadiumBorder(side: side);
      case 'continuous':
        return ContinuousRectangleBorder(
          side: side,
          borderRadius: _borderRadius(source, [...path, 'borderRadius']),
        );
      case 'beveled':
        return BeveledRectangleBorder(
          side: side,
          borderRadius: _borderRadius(source, [...path, 'borderRadius']),
        );
      case 'linear':
        return LinearBorder(
          side: side,
          start: _linearBorderEdge(source, [...path, 'start']),
          end: _linearBorderEdge(source, [...path, 'end']),
          top: _linearBorderEdge(source, [...path, 'top']),
          bottom: _linearBorderEdge(source, [...path, 'bottom']),
        );
      case 'star':
        return StarBorder(
          side: side,
          points: _number(source, [...path, 'points']) ?? 5.0,
          innerRadiusRatio:
              _number(source, [...path, 'innerRadiusRatio']) ?? 0.4,
          pointRounding: _number(source, [...path, 'pointRounding']) ?? 0.0,
          valleyRounding: _number(source, [...path, 'valleyRounding']) ?? 0.0,
          rotation: _number(source, [...path, 'rotation']) ?? 0.0,
          squash: _number(source, [...path, 'squash']) ?? 0.0,
        );
      case 'polygon':
        return StarBorder.polygon(
          side: side,
          sides: _number(source, [...path, 'sides']) ?? 5.0,
          pointRounding: _number(source, [...path, 'pointRounding']) ?? 0.0,
          rotation: _number(source, [...path, 'rotation']) ?? 0.0,
          squash: _number(source, [...path, 'squash']) ?? 0.0,
        );
      default:
        return ArgumentDecoders.shapeBorder(source, path);
    }
  }

  static BorderRadiusGeometry _borderRadius(
    DataSource source,
    List<Object> path,
  ) {
    final radius = _number(source, path);
    return radius == null ? BorderRadius.zero : BorderRadius.circular(radius);
  }

  static LinearBorderEdge? _linearBorderEdge(
    DataSource source,
    List<Object> path,
  ) {
    if (!source.isMap(path)) return null;
    return LinearBorderEdge(
      size: _number(source, [...path, 'size']) ?? 1.0,
      alignment: _number(source, [...path, 'alignment']) ?? 0.0,
    );
  }

  static double? _number(DataSource source, List<Object> path) =>
      source.v<double>(path) ?? source.v<int>(path)?.toDouble();

  static InlineSpan _inlineSpan(
    DataSource source,
    List<Object> path, {
    required int depth,
  }) {
    if (depth > kMaxInlineSpanDepth || !source.isMap(path)) {
      return const TextSpan();
    }
    return TextSpan(
      text: source.v<String>([...path, 'text']),
      style: _textStyle(source, [...path, 'style']),
      children: ArgumentDecoders.list<InlineSpan>(
        source,
        [...path, 'children'],
        (source, childPath) => _inlineSpan(source, childPath, depth: depth + 1),
      ),
    );
  }

  static TextStyle? _textStyle(DataSource source, List<Object> path) {
    if (!source.isMap(path)) return null;
    return TextStyle(
      inherit: source.v<bool>([...path, 'inherit']) ?? true,
      color: ArgumentDecoders.color(source, [...path, 'color']),
      backgroundColor:
          ArgumentDecoders.color(source, [...path, 'backgroundColor']),
      fontSize: _finiteNumber(source, [...path, 'fontSize']),
      fontWeight: ArgumentDecoders.enumValue<FontWeight>(
        FontWeight.values,
        source,
        [...path, 'fontWeight'],
      ),
      fontStyle: ArgumentDecoders.enumValue<FontStyle>(
        FontStyle.values,
        source,
        [...path, 'fontStyle'],
      ),
      letterSpacing: _finiteNumber(source, [...path, 'letterSpacing']),
      wordSpacing: _finiteNumber(source, [...path, 'wordSpacing']),
      textBaseline: ArgumentDecoders.enumValue<TextBaseline>(
        TextBaseline.values,
        source,
        [...path, 'textBaseline'],
      ),
      height: _finiteNumber(source, [...path, 'height']),
      leadingDistribution: ArgumentDecoders.enumValue<TextLeadingDistribution>(
        TextLeadingDistribution.values,
        source,
        [...path, 'leadingDistribution'],
      ),
      locale: ArgumentDecoders.locale(source, [...path, 'locale']),
      foreground: ArgumentDecoders.paint(source, [...path, 'foreground']),
      background: ArgumentDecoders.paint(source, [...path, 'background']),
      shadows: shadows(source, [...path, 'shadows']),
      fontFeatures: fontFeatures(source, [...path, 'fontFeatures']),
      fontVariations: fontVariations(source, [...path, 'fontVariations']),
      decoration: textDecoration(source, [...path, 'decoration']),
      decorationColor:
          ArgumentDecoders.color(source, [...path, 'decorationColor']),
      decorationStyle: ArgumentDecoders.enumValue<TextDecorationStyle>(
        TextDecorationStyle.values,
        source,
        [...path, 'decorationStyle'],
      ),
      decorationThickness:
          _finiteNumber(source, [...path, 'decorationThickness']),
      debugLabel: source.v<String>([...path, 'debugLabel']),
      fontFamily: source.v<String>([...path, 'fontFamily']),
      // Fail-safe: a non-string element on a corrupt / tamper wire is dropped
      // (the same present-malformed-degrades convention as the top-level
      // `stringList` slots), never thrown on — so a malformed nested
      // `fontFamilyFallback` (in a `TextStyle`, or a `Text.rich` span style via
      // `_inlineSpan`) degrades instead of aborting the render.
      fontFamilyFallback: stringList(source, [...path, 'fontFamilyFallback']),
      package: source.v<String>([...path, 'fontPackage']),
      overflow: ArgumentDecoders.enumValue<TextOverflow>(
        TextOverflow.values,
        source,
        [...path, 'overflow'],
      ),
    );
  }

  static double? _finiteNumber(DataSource source, List<Object> path) {
    final value = _number(source, path);
    if (value == null || !value.isFinite) return null;
    return value;
  }

  /// Decodes an `ImageProvider` from a `{kind, src, …}` map at [path].
  ///
  /// `kind: 'network'` builds a `NetworkImage(src, scale: …)`; `kind: 'asset'`
  /// builds an `AssetImage(src, package: …)`. The provider-specific keys
  /// (`scale` on network, `package` on asset) are applied when present and fall
  /// back to the Flutter constructor default when absent. Returns `null` when
  /// the map, the `kind`, or the `src` is absent, or when `kind` is an
  /// unrecognized value — the codegen only emits the two serializable
  /// providers, so an absent / unknown provider yields no image rather than a
  /// fabricated wrong one.
  static ImageProvider? _imageProvider(DataSource source, List<Object> path) {
    if (!source.isMap(path)) return null;
    final src = source.v<String>([...path, 'src']);
    if (src == null) return null;
    switch (source.v<String>([...path, 'kind'])) {
      case 'network':
        // `scale` changes the resolved image density; default 1.0 matches the
        // NetworkImage constructor default when the key is absent.
        return NetworkImage(src,
            scale: _number(source, [...path, 'scale']) ?? 1.0);
      case 'asset':
        // `package` changes asset resolution (`packages/<package>/…`); null
        // when absent, matching the AssetImage constructor default. AssetImage
        // has no `scale` constructor parameter (its scale comes from asset
        // resolution variants), so none is applied here.
        return AssetImage(src, package: source.v<String>([...path, 'package']));
      default:
        return null;
    }
  }

  /// Decodes a single-select widget's `items` list — an ordered list of
  /// `{value, label}` option maps — into a list of [RestageSelectionOption].
  ///
  /// `value` is the option's string-comparable selection key; `label` is its
  /// display string.
  ///
  /// **Absent vs present-but-empty are distinct.** Returns `null` only when the
  /// slot is **absent** (not a list on the wire) — letting the caller's
  /// required-slot contract or default apply. A **present** list (even an empty
  /// one, or one whose every entry is malformed) returns a list — possibly
  /// empty (`[]`) — never `null`. This is the fail-safe boundary: a
  /// present-but-degenerate wire renders the compiled widget's empty state (a
  /// `SizedBox.shrink`), never trips the caller's required-slot throw (which
  /// would crash the render). Codegen guarantees the slot is present, so the
  /// `null` (absent) branch is a corruption/tamper case; a present-but-empty
  /// list is the degenerate-tamper case that must fail safe rather than crash.
  ///
  /// A malformed entry — not a map, or missing a string `value` — is **omitted**
  /// rather than fabricated into a plausible-but-wrong option, mirroring the
  /// other list decoders ([fontVariations]) that drop a bad item instead of
  /// guessing. A missing `label` falls back to the `value` so the option stays
  /// selectable with an honest (key-as-label) display rather than a blank row.
  /// The compiled widget owns the final fail-safe: an empty resulting list
  /// renders a safe empty state, never a wrong selection. The
  /// recognition/validation layers reject a malformed authored list at build
  /// time, so a malformed wire here is a corruption/tamper case, not an
  /// authoring path.
  static List<RestageSelectionOption>? selectionOptionList(
    DataSource source,
    List<Object> path,
  ) {
    // Absent (not a list on the wire) → null, so the required-slot contract
    // applies. A present list — including an empty one — is decoded, never
    // collapsed to null, so a present-but-degenerate wire fails safe (the
    // compiled widget renders its empty state) instead of tripping the
    // required-slot throw.
    if (!source.isList(path)) return null;
    final count = source.length(path);
    final options = <RestageSelectionOption>[];
    for (var index = 0; index < count; index++) {
      final itemPath = [...path, index];
      if (!source.isMap(itemPath)) continue;
      final value = source.v<String>([...itemPath, 'value']);
      if (value == null) continue;
      final label = source.v<String>([...itemPath, 'label']) ?? value;
      options.add(RestageSelectionOption(value: value, label: label));
    }
    return options;
  }

  /// Decodes a multi-toggle widget's `isSelected` list — an ordered list of
  /// booleans, one per child button (`ToggleButtons.isSelected`).
  ///
  /// **Absent vs present-but-empty are distinct**, exactly as
  /// [selectionOptionList]: returns `null` only when the slot is **absent**
  /// (not a list on the wire) — letting the caller's required-slot contract or
  /// default apply. A **present** list (even an empty one) returns a list,
  /// never `null`, so a present-but-degenerate wire fails safe (the compiled
  /// widget renders its empty state) instead of tripping the required-slot
  /// throw that would crash the render.
  ///
  /// A malformed entry — a value that is not a `bool` on the wire — is
  /// **coerced to `false`** (the unselected state, the safe toggle default)
  /// rather than dropped. Coercing keeps the list **length** stable: each entry
  /// pairs by index with the corresponding `children` button, so dropping a bad
  /// entry would shift every later selection onto the wrong button. The
  /// length-pairing fail-safe against a `children`/`isSelected` length mismatch
  /// lives in the consuming widget (which has both lists); this decoder's job
  /// is only the safe `List<bool>` read.
  static List<bool>? booleanList(DataSource source, List<Object> path) {
    // Absent (not a list on the wire) → null, so the required-slot contract
    // applies. A present list — including an empty one — is decoded, never
    // collapsed to null, so a present-but-degenerate wire fails safe.
    if (!source.isList(path)) return null;
    final count = source.length(path);
    final values = <bool>[];
    for (var index = 0; index < count; index++) {
      // A non-bool entry coerces to `false` (unselected) — never dropped, so
      // the per-index pairing with `children` stays aligned.
      values.add(source.v<bool>([...path, index]) ?? false);
    }
    return values;
  }

  /// Decodes a `List<String>` slot fail-safe, **dropping** any non-string
  /// entry rather than throwing on it.
  ///
  /// **Absent vs present-but-degenerate are distinct**, exactly as
  /// [booleanList] / [selectionOptionList]: returns `null` only when the slot
  /// is **absent** (not a list on the wire), letting the caller's required-slot
  /// contract or default apply. A **present** list — even an empty one, or one
  /// whose every entry is malformed — returns a list, possibly empty (`[]`),
  /// never `null`.
  ///
  /// A malformed entry — a value that is not a `String` on the wire — is
  /// **dropped** (not coerced, not thrown on). Unlike [booleanList], a
  /// string-list slot carries an unordered value set (e.g. the selected values
  /// of a multi-select), so there is no per-index pairing to preserve and a
  /// fabricated placeholder string would be a wrong value; dropping degrades to
  /// the smaller valid set. The consuming widget owns the final fail-safe. The
  /// recognition/validation layers reject a malformed authored list at build
  /// time, so a malformed wire here is a corruption/tamper case — and it now
  /// fails safe instead of throwing and crashing the render.
  static List<String>? stringList(DataSource source, List<Object> path) {
    if (!source.isList(path)) return null;
    final count = source.length(path);
    final values = <String>[];
    for (var index = 0; index < count; index++) {
      final value = source.v<String>([...path, index]);
      if (value != null) values.add(value);
    }
    return values;
  }
}

/// One option in a single-select widget (a radio group / dropdown).
///
/// [value] is the selection key compared against the widget's `selected`
/// value and fired on the settled `onChanged`; [label] is the option's
/// display string.
@immutable
class RestageSelectionOption {
  /// Creates a selection option with a [value] key and a display [label].
  const RestageSelectionOption({required this.value, required this.label});

  /// The selection key — compared against the widget's `selected` value and
  /// surfaced on the settled selection event.
  final String value;

  /// The option's display string.
  final String label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RestageSelectionOption &&
          runtimeType == other.runtimeType &&
          value == other.value &&
          label == other.label;

  @override
  int get hashCode => Object.hash(value, label);

  @override
  String toString() => 'RestageSelectionOption(value: $value, label: $label)';
}

/// Returns [items] with later entries repeating an earlier entry's
/// [RestageSelectionOption.value] dropped — first occurrence wins, order
/// preserved.
///
/// The compiled single-select widgets call this to enforce the unique-value
/// invariant Flutter's `DropdownButton` / radio selection requires, defending
/// against a duplicate-value wire (a corruption / tamper case the build-time
/// recognition already rejects).
List<RestageSelectionOption> dedupeSelectionOptionsByValue(
  List<RestageSelectionOption> items,
) {
  final seen = <String>{};
  final result = <RestageSelectionOption>[];
  for (final option in items) {
    if (seen.add(option.value)) result.add(option);
  }
  return result;
}

const Map<String, Curve> _supportedCurvesByName = {
  'linear': Curves.linear,
  'decelerate': Curves.decelerate,
  'fastLinearToSlowEaseIn': Curves.fastLinearToSlowEaseIn,
  'ease': Curves.ease,
  'easeIn': Curves.easeIn,
  'easeInToLinear': Curves.easeInToLinear,
  'easeInSine': Curves.easeInSine,
  'easeInQuad': Curves.easeInQuad,
  'easeInCubic': Curves.easeInCubic,
  'easeInQuart': Curves.easeInQuart,
  'easeInQuint': Curves.easeInQuint,
  'easeInExpo': Curves.easeInExpo,
  'easeInCirc': Curves.easeInCirc,
  'easeInBack': Curves.easeInBack,
  'easeOut': Curves.easeOut,
  'linearToEaseOut': Curves.linearToEaseOut,
  'easeOutSine': Curves.easeOutSine,
  'easeOutQuad': Curves.easeOutQuad,
  'easeOutCubic': Curves.easeOutCubic,
  'easeOutQuart': Curves.easeOutQuart,
  'easeOutQuint': Curves.easeOutQuint,
  'easeOutExpo': Curves.easeOutExpo,
  'easeOutCirc': Curves.easeOutCirc,
  'easeOutBack': Curves.easeOutBack,
  'easeInOut': Curves.easeInOut,
  'easeInOutSine': Curves.easeInOutSine,
  'easeInOutQuad': Curves.easeInOutQuad,
  'easeInOutCubic': Curves.easeInOutCubic,
  'easeInOutCubicEmphasized': Curves.easeInOutCubicEmphasized,
  'easeInOutQuart': Curves.easeInOutQuart,
  'easeInOutQuint': Curves.easeInOutQuint,
  'easeInOutExpo': Curves.easeInOutExpo,
  'easeInOutCirc': Curves.easeInOutCirc,
  'easeInOutBack': Curves.easeInOutBack,
  'fastOutSlowIn': Curves.fastOutSlowIn,
  'slowMiddle': Curves.slowMiddle,
  'bounceIn': Curves.bounceIn,
  'bounceOut': Curves.bounceOut,
  'bounceInOut': Curves.bounceInOut,
  'elasticIn': Curves.elasticIn,
  'elasticOut': Curves.elasticOut,
  'elasticInOut': Curves.elasticInOut,
};
