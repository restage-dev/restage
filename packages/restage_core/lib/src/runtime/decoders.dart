import 'dart:math' as math;

import 'canonical_colors.dart';

import 'dart:ui'
    show
        BlendMode,
        Brightness,
        Color,
        ColorFilter,
        ColorSpace,
        FontFeature,
        FontVariation,
        Offset,
        Paint,
        Radius,
        Size;

import 'package:flutter/gestures.dart';
import 'package:restage_core/src/runtime/island_stage.dart';
import 'package:restage_core/src/runtime/resource_builder.dart';
import 'package:restage_core/src/runtime/rfw_constructor_presence.dart';

import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/painting.dart'
    show
        Alignment,
        AlignmentDirectional,
        AlignmentGeometry,
        AssetImage,
        BeveledRectangleBorder,
        BorderDirectional,
        BorderRadius,
        BorderRadiusGeometry,
        BorderRadiusDirectional,
        BorderSide,
        BorderStyle,
        BoxBorder,
        BoxFit,
        BoxShadow,
        CircleBorder,
        ContinuousRectangleBorder,
        DecorationImage,
        EdgeInsets,
        EdgeInsetsDirectional,
        EdgeInsetsGeometry,
        TileMode,
        FontStyle,
        FontWeight,
        Gradient,
        ImageProvider,
        ImageRepeat,
        InlineSpan,
        LinearBorder,
        LinearBorderEdge,
        LinearGradient,
        NetworkImage,
        RadialGradient,
        RoundedRectangleBorder,
        RoundedSuperellipseBorder,
        Shadow,
        ShapeBorder,
        StadiumBorder,
        StarBorder,
        SweepGradient,
        TextBaseline,
        TextDecoration,
        TextDecorationStyle,
        TextLeadingDistribution,
        TextOverflow,
        TextSpan,
        TextStyle,
        TextScaler;
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/rendering.dart' show BoxConstraints;
import 'package:flutter/services.dart' show SystemUiOverlayStyle, TextInputType;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        IconThemeData,
        GlobalKey,
        Key,
        PreferredSizeWidget,
        ScrollNotificationPredicate,
        Widget,
        defaultScrollNotificationPredicate;
import 'package:restage_core/src/runtime/preferred_size_slot.dart';
import 'package:restage_core/src/runtime/builder_binding.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        ScalarCallbackContract,
        ScalarCallbackParameter,
        kIconThemeDataFallbackKey,
        kIconThemeDataLerpKey,
        kMaxInlineSpanDepth,
        kMaxStructuredCopyWithLayers,
        kStructuredCopyWithKey,
        kTextSpanRecognizerDetailCallbacks;
import 'package:rfw/rfw.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'
    show RfwConstructorPresenceProtocol;

import '../widgets/restage_padding.dart';
import 'native_values.dart';

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
/// any custom library generated via `@RestageWidget` can call into a
/// single canonical implementation.
abstract final class RestageDecoders {
  static const _spanCollectionGroupDepthLimit = 8000;

  /// Reads an installed object or native expression; absent inputs stay null.
  static T? nativeBinding<T extends Object>(
    BuildContext context,
    DataSource source,
    List<Object> path, {
    required String type,
  }) {
    if (source.v<String>([...path, 'program']) == null &&
        !source.isMap(path) &&
        !source.isList(path) &&
        source.v<String>(path) == null &&
        source.v<int>(path) == null &&
        source.v<double>(path) == null &&
        source.v<bool>(path) == null) return null;
    return RestageNativeValues.read<T>(context, source, path, type: type);
  }

  /// Resolves a borrowed key for the actual native widget constructor.
  ///
  /// A global key waits while its version is staged beside the shown one.
  static Key? nativeKey(
    BuildContext context,
    DataSource source,
    List<Object> path,
  ) {
    final key = nativeBinding<Key>(context, source, path, type: 'flutter.Key');
    return key is GlobalKey && RestageIslandStage.isCandidate(context)
        ? null
        : key;
  }

  /// Rejects a key whose original widget owner a guarded replacement erases.
  ///
  /// Null retains the replacement's normal unkeyed behavior. Decode the native
  /// key before this check so malformed references still fail at their reader.
  static Key? guardReplacementKey(Key? key, String widget) {
    if (key != null) {
      throw UnsupportedError(
          'A native key requires the original $widget owner; its guarded runtime replacement cannot retain that owner.');
    }
    return null;
  }

  /// Resolves the fixed native child-index callback or its scalar program.
  static int? Function(Key)? keyIndexCallback(
      BuildContext context, DataSource source, List<Object> path,
      {required List<RestageBuilderBinding> bindings}) {
    if (source.v<String>([...path, 'nativeKeyIndex', 'program']) != null ||
        source.isMap([...path, 'nativeKeyIndex'])) {
      final callback = RestageNativeValues.read<int? Function(Key)>(
          context, source, [...path, 'nativeKeyIndex'],
          type: 'flutter.ChildIndexGetter');
      return callback == null
          ? null
          : (key) => callback(RestageBuilderBinding.originalKey(key));
    }
    final binding = RestageBuilderBinding.optional(source, path,
        context: context,
        scalarContract: const ScalarCallbackContract(
            parameters: [ScalarCallbackParameter.valueKey]));
    if (binding == null) return null;
    bindings.add(binding);
    return (key) => binding.evaluateKey(context, key) as int?;
  }

  /// Decodes a native scaler value or a none/linear Flutter recipe.
  static TextScaler? textScaler(
    BuildContext context,
    DataSource source,
    List<Object> path,
  ) {
    if (RestageValueBinding.isNativeValue(source, path)) {
      return RestageNativeValues.read<TextScaler>(context, source, path,
          type: 'flutter.TextScaler');
    }
    if (!source.isMap(path)) {
      if (source.isList(path) ||
          source.v<String>(path) != null ||
          source.v<double>(path) != null ||
          source.v<int>(path) != null ||
          source.v<bool>(path) != null) {
        throw FormatException('Expected a TextScaler recipe at $path.');
      }
      return null;
    }
    final kind = source.v<String>([...path, 'kind']);
    switch (kind) {
      case 'none':
        return TextScaler.noScaling;
      case 'linear':
        final factor = source.v<double>([...path, 'factor']) ??
            source.v<int>([...path, 'factor']);
        if (factor == null || factor.isNaN || factor < 0) {
          throw FormatException('Invalid TextScaler factor at $path.');
        }
        return TextScaler.linear(factor.toDouble());
      case 'nativeBinding':
        return RestageNativeValues.read<TextScaler>(context, source, path,
            type: 'flutter.TextScaler');
      case 'native':
        final key = source.v<String>([...path, 'key']);
        if (key == null) {
          throw FormatException(
              'Native TextScaler binding is unavailable at $path.');
        }
        return RestageNativeValues.textScalerOf(context, key);
      default:
        throw FormatException('Unknown TextScaler recipe at $path.');
    }
  }

  /// Decodes ARGB integers or exact floating color components.
  static Color? color(DataSource source, List<Object> path) {
    if (RestageValueBinding.isNativeValue(source, path)) {
      return RestageValueBinding.readNativeFromSource<Color>(source, path,
          type: 'flutter.Color');
    }
    if (!source.isMap(path)) return ArgumentDecoders.color(source, path);
    final materialPath = [...path, 'material'];
    final material = source.v<String>(materialPath);
    if (material == null &&
        (source.v<int>(materialPath) != null ||
            source.v<double>(materialPath) != null ||
            source.v<bool>(materialPath) != null ||
            source.isMap(materialPath) ||
            source.isList(materialPath)))
      throw const FormatException('Invalid Material color token');
    if (material is String && material.isNotEmpty) {
      final color = canonicalMaterialColors[material];
      if (color == null) throw const FormatException('Unknown Material color');
      return color;
    }
    final alpha = number(source, [...path, 'a']);
    final red = number(source, [...path, 'r']);
    final green = number(source, [...path, 'g']);
    final blue = number(source, [...path, 'b']);
    final space =
        enumByName(ColorSpace.values, source, [...path, 'colorSpace']);
    if (alpha == null ||
        red == null ||
        green == null ||
        blue == null ||
        space == null) {
      throw const FormatException('Invalid color components');
    }
    return Color.from(
        alpha: alpha, red: red, green: green, blue: blue, colorSpace: space);
  }

  /// Decodes exact native weights or standard weight tokens.
  static FontWeight? fontWeight(DataSource source, List<Object> path) {
    final value = source.v<int>(path);
    if (value == null) return _fontWeightTokens[source.v<String>(path)];
    if (value < 1 || value > 1000) {
      throw const FormatException('Font weight must be between 1 and 1000');
    }
    return FontWeight(value);
  }

  // An explicit table: release builds strip `FontWeight.toString`.
  static const _fontWeightTokens = <String?, FontWeight>{
    'w100': FontWeight.w100,
    'w200': FontWeight.w200,
    'w300': FontWeight.w300,
    'w400': FontWeight.w400,
    'w500': FontWeight.w500,
    'w600': FontWeight.w600,
    'w700': FontWeight.w700,
    'w800': FontWeight.w800,
    'w900': FontWeight.w900,
  };

  /// Decodes a paint with exact color and mode-filter components.
  static Paint? paint(DataSource source, List<Object> path) {
    final result = ArgumentDecoders.paint(source, path);
    if (result == null) return null;
    final paintColor = color(source, [...path, 'color']);
    if (paintColor != null) result.color = paintColor;
    final filterPath = [...path, 'colorFilter'];
    if (source.v<String>([...filterPath, 'type']) == 'mode') {
      result.colorFilter = colorFilter(source, filterPath);
    }
    return result;
  }

  /// Decodes mode-filter colors without converting to eight-bit channels.
  static ColorFilter? colorFilter(DataSource source, List<Object> path) {
    if (source.v<String>([...path, 'type']) != 'mode') {
      return ArgumentDecoders.colorFilter(source, path);
    }
    return ColorFilter.mode(
      color(source, [...path, 'color']) ?? const Color(0xFF000000),
      ArgumentDecoders.enumValue(
              BlendMode.values, source, [...path, 'blendMode']) ??
          BlendMode.srcOver,
    );
  }

  /// Decodes a box shadow, retaining its exact color.
  static BoxShadow boxShadow(DataSource source, List<Object> path) {
    final result = ArgumentDecoders.boxShadow(source, path);
    final shadowColor = color(source, [...path, 'color']);
    return shadowColor == null ? result : result.copyWith(color: shadowColor);
  }

  /// Decodes widget children, flattening lists emitted by collection elements.
  ///
  /// Empty nested lists contribute no children. Each widget keeps its original
  /// source path so loop values and event arguments remain bound to that item.
  static bool isWidgetList(DataSource source, List<Object> path) =>
      source.isList(path) || source.optionalChild(path) != null;

  static List<Widget> widgetList(DataSource source, List<Object> path,
      {BuildContext? context, List<RestageBuilderBinding>? bindings}) {
    if (!source.isList(path)) {
      // Anything but a builder continuation keeps RFW's own list errors.
      if (context == null ||
          bindings == null ||
          source.optionalChild(path) == null) {
        return source.childList(path);
      }
      final binding = RestageBuilderBinding.optional(source, path)!;
      bindings.add(binding);
      return binding.buildList(context, const {});
    }
    final children = <Widget>[];
    for (var index = 0; index < source.length(path); index++) {
      final childPath = <Object>[...path, index];
      if (source.isList(childPath)) {
        children.addAll(widgetList(source, childPath,
            context: context, bindings: bindings));
      } else {
        children.add(source.child(childPath));
      }
    }
    return children;
  }

  /// Decodes a typed value-change event through RFW's own handler machinery.
  ///
  /// The trigger preserves RFW event lists and argument merging, including an
  /// explicit null value. Keeping the adapter here shares it across factories.
  static void Function(T)? valueChanged<T>(
          DataSource source, List<Object> path) =>
      source.handler<void Function(T)>(path, _valueChanged<T>);

  static void Function(T) _valueChanged<T>(HandlerTrigger trigger) =>
      (T value) => trigger(<String, Object?>{'value': value});

  /// Decodes an event slot that only the app's own callback can fill: a
  /// design event can't supply Flutter's arguments, so it is refused.
  static T? nativeCallback<T extends Function>(
          DataSource source, List<Object> path, String slot) =>
      source.handler<T>(
          path,
          (_) => throw ArgumentError(
              "`$slot` needs a function from the app's code. Flutter calls it "
              "with arguments, which an event from the design can't receive. "
              "Try passing a function from your app's code to "
              "`${slot.split('.').last}`."));

  /// Decodes an enum member by its declared name.
  ///
  /// [EnumName.name] is the declared member name by construction, while
  /// `toString()` can be overridden — by the enum itself, or by a mixin it
  /// applies. Returns `null` when [path] is absent, is not a string, or does
  /// not name a member of [values].
  ///
  /// The `T extends Enum` bound is load-bearing for CORRECTNESS, not just for
  /// reuse, and these two facts are one fact: `name` is not a member of [Enum]
  /// at all — it comes from `extension EnumName on Enum`. Extension members
  /// bind to the STATIC type, so inside this bound `value.name` resolves to the
  /// extension and yields the declared name even for an enum that declares its
  /// own `name` getter. Specialise this to a concrete type and that shadow
  /// wins instead, which silently reopens the failure this exists to close: a
  /// spelling the enum does not declare resolving to a real member.
  static T? enumByName<T extends Enum>(
    List<T> values,
    DataSource source,
    List<Object> path,
  ) {
    final name = source.v<String>(path);
    if (name == null) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// Decodes a real scalar at [path], accepting either wire number shape.
  ///
  /// `DataSource.v<double>` is a strict type check: an `int` on the wire reads
  /// back as `null` through it, indistinguishable from an absent slot — so a
  /// producer that writes a whole number as `200` rather than `200.0` silently
  /// loses the value and the slot takes its default. This read accepts both and
  /// widens the `int`, so a real slot means what it says.
  ///
  /// Returns `null` only when the slot is genuinely absent (or carries a
  /// non-number), leaving the caller's required-slot throw or literal default to
  /// apply. It does no bounding: NaN and infinity pass through, so use it only
  /// where the assembled value is repaired downstream (as a `BoxConstraints` is
  /// by [safeConstraints]) or where a non-finite value is harmless.
  static double? number(DataSource source, List<Object> path) =>
      _number(source, path);

  /// Repairs constraints before layout, including in release builds.
  ///
  /// Invalid or infinite minima become zero; NaN maxima become unbounded.
  /// Maxima below their minima rise to meet them. Infinite maxima and all
  /// other legal constraints are preserved. Infinite minima are removed
  /// because an unbounded parent would produce invalid layout geometry.
  ///
  /// Raw widget width and height values use [constraintScalar] separately.
  static BoxConstraints safeConstraints(BoxConstraints constraints) {
    final minWidth = _safeConstraintMin(constraints.minWidth);
    final minHeight = _safeConstraintMin(constraints.minHeight);
    return BoxConstraints(
      minWidth: minWidth,
      maxWidth: _safeConstraintMax(constraints.maxWidth, minWidth),
      minHeight: minHeight,
      maxHeight: _safeConstraintMax(constraints.maxHeight, minHeight),
    );
  }

  static double _safeConstraintMin(double value) =>
      value.isFinite && value > 0.0 ? value : 0.0;

  static double _safeConstraintMax(double value, double min) {
    if (value.isNaN) return double.infinity;
    return value < min ? min : value;
  }

  /// Decodes physical or directional maps without changing native components.
  /// Legacy lists retain directional shorthand and layout repairs.
  static EdgeInsetsGeometry? edgeInsets(DataSource source, List<Object> path) {
    if (source.isMap(path)) {
      final directional = _number(source, [...path, 'start']) != null ||
          _number(source, [...path, 'end']) != null;
      final leftOrStart =
          _number(source, [...path, directional ? 'start' : 'left']) ?? 0.0;
      final top = _number(source, [...path, 'top']) ?? 0.0;
      final rightOrEnd =
          _number(source, [...path, directional ? 'end' : 'right']) ?? 0.0;
      final bottom = _number(source, [...path, 'bottom']) ?? 0.0;
      return directional
          ? EdgeInsetsDirectional.fromSTEB(leftOrStart, top, rightOrEnd, bottom)
          : EdgeInsets.fromLTRB(leftOrStart, top, rightOrEnd, bottom);
    }
    final start = source.v<double>([...path, 0]);
    if (start == null) return null;
    final top = source.v<double>([...path, 1]);
    final end = source.v<double>([...path, 2]);
    final bottom = source.v<double>([...path, 3]);
    final horizontal = restageSafeInsetAxis(start, end ?? start);
    final vertical = restageSafeInsetAxis(top ?? start, bottom ?? top ?? start);
    return EdgeInsetsDirectional.fromSTEB(
      horizontal.$1,
      vertical.$1,
      horizontal.$2,
      vertical.$2,
    );
  }

  /// Decodes an inset for a concrete physical Flutter slot.
  static EdgeInsets? physicalEdgeInsets(DataSource source, List<Object> path) {
    final value = edgeInsets(source, path);
    return value is EdgeInsets ? value : null;
  }

  /// Decodes an inset for a concrete directional Flutter slot.
  static EdgeInsetsDirectional? directionalEdgeInsets(
      DataSource source, List<Object> path) {
    final value = edgeInsets(source, path);
    return value is EdgeInsetsDirectional ? value : null;
  }

  /// Decodes an alignment for a concrete directional Flutter slot.
  static AlignmentDirectional? directionalAlignment(
      DataSource source, List<Object> path) {
    final value = alignment(source, path);
    return value is AlignmentDirectional ? value : null;
  }

  /// Decodes exact colors while retaining directional gradient alignments.
  static Gradient? gradient(DataSource source, List<Object> path) {
    final type = source.v<String>([...path, 'type']);
    if (type != 'linear' && type != 'radial' && type != 'sweep') {
      return ArgumentDecoders.gradient(source, path);
    }
    final colors = ArgumentDecoders.list<Color>(source, [...path, 'colors'],
            (source, path) => color(source, path) ?? const Color(0xFF000000)) ??
        const [Color(0xFF000000), Color(0xFFFFFFFF)];
    final stops = ArgumentDecoders.list<double>(
        source, [...path, 'stops'], ArgumentDecoders.doubleOrZero);
    final tileMode =
        enumByName(TileMode.values, source, [...path, 'tileMode']) ??
            TileMode.clamp;
    switch (type) {
      case 'linear':
        return LinearGradient(
            begin:
                alignment(source, [...path, 'begin']) ?? Alignment.centerLeft,
            end: alignment(source, [...path, 'end']) ?? Alignment.centerRight,
            colors: colors,
            stops: stops,
            tileMode: tileMode);
      case 'radial':
        return RadialGradient(
            center: alignment(source, [...path, 'center']) ?? Alignment.center,
            radius: _number(source, [...path, 'radius']) ?? 0.5,
            focal: alignment(source, [...path, 'focal']),
            focalRadius: _number(source, [...path, 'focalRadius']) ?? 0.0,
            colors: colors,
            stops: stops,
            tileMode: tileMode);
      case 'sweep':
        return SweepGradient(
            center: alignment(source, [...path, 'center']) ?? Alignment.center,
            startAngle: _number(source, [...path, 'startAngle']) ?? 0.0,
            endAngle: _number(source, [...path, 'endAngle']) ?? math.pi * 2,
            colors: colors,
            stops: stops,
            tileMode: tileMode);
      default:
        return ArgumentDecoders.gradient(source, path);
    }
  }

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

  /// Decodes a keyboard type from its wire name.
  ///
  /// `TextInputType` is not a Dart enum, so this uses a closed lookup table.
  /// Unknown names decode to `null` and the field keeps Flutter's default.
  static TextInputType? textInputType(DataSource source, List<Object> path) {
    final name = source.v<String>(path);
    return name == null ? null : _supportedTextInputTypesByName[name];
  }

  /// Accepts scroll notifications at the depth at [path], or applies Flutter's
  /// default predicate when none is given.
  static ScrollNotificationPredicate scrollNotificationPredicate(
    DataSource source,
    List<Object> path,
  ) {
    final depth = source.v<int>(path);
    if (depth == null) return defaultScrollNotificationPredicate;
    return (notification) => notification.depth == depth;
  }

  /// The keyboard type wire names [textInputType] decodes.
  static final Set<String> supportedTextInputTypeNames = Set.unmodifiable(
    _supportedTextInputTypesByName.keys,
  );

  /// Decodes a concrete `Alignment` from `{x, y}` at [path].
  /// Missing components return null so the caller's default applies.
  /// Each non-finite component becomes `0.0`; finite values, including negative
  /// values, are preserved without a ceiling.
  static Alignment? alignmentXY(DataSource source, List<Object> path) {
    final x = _number(source, [...path, 'x']);
    final y = _number(source, [...path, 'y']);
    if (x == null || y == null) return null;
    return Alignment(_finiteOrZero(x), _finiteOrZero(y));
  }

  /// Decodes `{x, y}` or `{start, y}`, preserving the rfw subtype choice and
  /// replacing each non-finite component independently with zero.
  static AlignmentGeometry? alignment(
    DataSource source,
    List<Object> path,
  ) {
    if (!source.isMap(path)) return null;
    final x = source.v<double>([...path, 'x']);
    final start = source.v<double>([...path, 'start']);
    final y = source.v<double>([...path, 'y']);
    if (x == null && start == null) return null;
    if (y == null) return null;
    if (start != null) {
      return AlignmentDirectional(
        _finiteOrZero(start),
        _finiteOrZero(y),
      );
    }
    return Alignment(_finiteOrZero(x!), _finiteOrZero(y));
  }

  /// Decodes `{x, y}`, replacing non-finite components independently with zero
  /// while preserving finite negative offsets.
  static Offset? offset(DataSource source, List<Object> path) {
    final x = _number(source, [...path, 'x']);
    final y = _number(source, [...path, 'y']);
    if (x == null || y == null) return null;
    return Offset(_finiteOrZero(x), _finiteOrZero(y));
  }

  /// Decodes `{width, height}`, returning null for missing or non-finite
  /// components and clamping finite negative components to zero.
  static Size? size(DataSource source, List<Object> path) {
    final width = _number(source, [...path, 'width']);
    final height = _number(source, [...path, 'height']);
    if (width == null || height == null) return null;
    if (!width.isFinite || !height.isFinite) return null;
    return Size(
      width < 0.0 ? 0.0 : width,
      height < 0.0 ? 0.0 : height,
    );
  }

  /// Decodes rfw's `{color, width, style}` shape, replacing non-finite or
  /// negative widths with the zero-width border identity.
  static BorderSide? borderSide(DataSource source, List<Object> path) =>
      _repairedBorderSide(source, path);

  /// Decodes a [BorderDirectional] through [borderSide], preserving rfw's side
  /// fallback order and returning null when the first side is absent.
  static BoxBorder? border(DataSource source, List<Object> path) {
    final start = _repairedBorderSide(source, [...path, 0]);
    if (start == null) return null;
    final top = _repairedBorderSide(source, [...path, 1]);
    final end = _repairedBorderSide(source, [...path, 2]);
    final bottom = _repairedBorderSide(source, [...path, 3]);
    return BorderDirectional(
      start: start,
      top: top ?? start,
      end: end ?? start,
      bottom: bottom ?? top ?? start,
    );
  }

  /// Decodes a constraint scalar, dropping only non-finite values.
  static double? constraintScalar(
    DataSource source,
    List<Object> path,
  ) =>
      _finiteNumber(source, path);

  /// Decodes a required finite scalar, additionally requiring a positive value
  /// when [mustBePositive] is set, and otherwise throws for [slot].
  static double requiredLayoutScalar(
    DataSource source,
    List<Object> path, {
    required String slot,
    bool mustBePositive = false,
  }) {
    final value = _finiteNumber(source, path);
    if (value == null || mustBePositive && value <= 0.0) {
      final requirement = mustBePositive
          ? 'a finite number greater than zero'
          : 'a finite number';
      throw ArgumentError('$slot is required and must be $requirement.');
    }
    return value;
  }

  /// Decodes a text metric, dropping non-finite values like nested text styles.
  static double? textMetric(DataSource source, List<Object> path) =>
      _finiteNumber(source, path);

  /// Decodes a layout factor, dropping non-finite and negative values so the
  /// consuming widget uses natural sizing.
  static double? layoutFactor(DataSource source, List<Object> path) {
    final value = _finiteNumber(source, path);
    if (value == null || value < 0.0) return null;
    return value;
  }

  /// Decodes non-negative finite spacing, replacing it with zero when its total
  /// child-gap contribution would be non-finite.
  static double derivedSpacing(
    DataSource source,
    List<Object> path,
    int childCount,
  ) {
    final spacing = layoutFactor(source, path) ?? 0.0;
    final derivedSpacing = spacing * (childCount - 1);
    return derivedSpacing.isFinite ? spacing : 0.0;
  }

  /// Decodes an optional scalar, returning null unless it is finite and positive.
  static double? positiveLayoutScalar(DataSource source, List<Object> path) {
    final value = _finiteNumber(source, path);
    if (value == null || value <= 0.0) return null;
    return value;
  }

  /// Decodes an optional finite factor in the interval `(0, 1]`.
  static double? unitIntervalFactor(DataSource source, List<Object> path) {
    final value = _finiteNumber(source, path);
    if (value == null || value <= 0.0 || value > 1.0) return null;
    return value;
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

  /// Decodes a system overlay style, preserving nullable platform options.
  static SystemUiOverlayStyle? systemUiOverlayStyle(
    DataSource source,
    List<Object> path,
  ) {
    if (!source.isMap(path)) return null;
    final layers = _copyLayers(source, path);
    if (layers == null) return null;
    var style = _systemUiOverlayStyleFields(source, path);
    for (final layer in layers) {
      final copy = _systemUiOverlayStyleFields(source, layer);
      style = style.copyWith(
        statusBarColor: copy.statusBarColor,
        statusBarBrightness: copy.statusBarBrightness,
        statusBarIconBrightness: copy.statusBarIconBrightness,
        systemNavigationBarColor: copy.systemNavigationBarColor,
        systemNavigationBarDividerColor: copy.systemNavigationBarDividerColor,
        systemNavigationBarIconBrightness:
            copy.systemNavigationBarIconBrightness,
        systemNavigationBarContrastEnforced:
            copy.systemNavigationBarContrastEnforced,
        systemStatusBarContrastEnforced: copy.systemStatusBarContrastEnforced,
      );
    }
    return style;
  }

  /// The paths of a structured value's `copyWith` layers, in order, or `null`
  /// when the layer list is malformed.
  static List<List<Object>>? _copyLayers(
    DataSource source,
    List<Object> path,
  ) {
    final copiesPath = <Object>[...path, kStructuredCopyWithKey];
    if (!source.isList(copiesPath)) {
      return _hasValue(source, copiesPath) ? null : const [];
    }
    final count = source.length(copiesPath);
    if (count > kMaxStructuredCopyWithLayers) return null;
    final layers = <List<Object>>[];
    for (var index = 0; index < count; index++) {
      final copyPath = <Object>[...copiesPath, index];
      if (!source.isMap(copyPath) ||
          _hasValue(source, [...copyPath, kStructuredCopyWithKey])) {
        return null;
      }
      layers.add(copyPath);
    }
    return layers;
  }

  static bool _hasValue(DataSource source, List<Object> path) =>
      source.isMap(path) ||
      source.isList(path) ||
      source.v<String>(path) != null ||
      source.v<int>(path) != null ||
      source.v<double>(path) != null ||
      source.v<bool>(path) != null;

  static SystemUiOverlayStyle _systemUiOverlayStyleFields(
    DataSource source,
    List<Object> path,
  ) {
    return SystemUiOverlayStyle(
      statusBarColor: color(source, [...path, 'statusBarColor']),
      statusBarBrightness: enumByName(
          Brightness.values, source, [...path, 'statusBarBrightness']),
      statusBarIconBrightness: enumByName(
        Brightness.values,
        source,
        [...path, 'statusBarIconBrightness'],
      ),
      systemNavigationBarColor:
          color(source, [...path, 'systemNavigationBarColor']),
      systemNavigationBarDividerColor: color(
        source,
        [...path, 'systemNavigationBarDividerColor'],
      ),
      systemNavigationBarIconBrightness: enumByName(
        Brightness.values,
        source,
        [...path, 'systemNavigationBarIconBrightness'],
      ),
      systemNavigationBarContrastEnforced:
          source.v<bool>([...path, 'systemNavigationBarContrastEnforced']),
      systemStatusBarContrastEnforced:
          source.v<bool>([...path, 'systemStatusBarContrastEnforced']),
    );
  }

  /// Decodes an icon theme, leaving defaults, interpolation and validation to
  /// Flutter.
  static IconThemeData? iconThemeData(DataSource source, List<Object> path) =>
      _iconThemeData(source, path, 0);

  static IconThemeData? _iconThemeData(
    DataSource source,
    List<Object> path,
    int depth,
  ) {
    if (!source.isMap(path) || depth > kMaxStructuredCopyWithLayers) {
      return null;
    }
    final layers = _copyLayers(source, path);
    if (layers == null) return null;
    final lerpPath = <Object>[...path, kIconThemeDataLerpKey];
    final fallbackPath = <Object>[...path, kIconThemeDataFallbackKey];
    IconThemeData theme;
    if (_hasValue(source, lerpPath)) {
      final t = number(source, [...lerpPath, 't']);
      if (!source.isMap(lerpPath) || t == null) return null;
      final ends = <IconThemeData?>[];
      for (final end in const ['a', 'b']) {
        final endPath = <Object>[...lerpPath, end];
        final value = _iconThemeData(source, endPath, depth + 1);
        if (value == null && _hasValue(source, endPath)) return null;
        ends.add(value);
      }
      theme = IconThemeData.lerp(ends[0], ends[1], t);
    } else if (_hasValue(source, fallbackPath)) {
      if (source.v<bool>(fallbackPath) != true) return null;
      theme = const IconThemeData.fallback();
    } else {
      theme = _iconThemeFields(source, path, IconThemeData.new);
    }
    for (final layer in layers) {
      theme = _iconThemeFields(source, layer, theme.copyWith);
    }
    return theme;
  }

  /// Passes the icon theme fields at [path] to [build], the constructor or a
  /// `copyWith`.
  static IconThemeData _iconThemeFields(
    DataSource source,
    List<Object> path,
    IconThemeData Function({
      Color? color,
      double? size,
      double? opacity,
      double? fill,
      double? weight,
      double? grade,
      double? opticalSize,
      List<Shadow>? shadows,
      bool? applyTextScaling,
    }) build,
  ) =>
      build(
        color: color(source, [...path, 'color']),
        size: number(source, [...path, 'size']),
        opacity: number(source, [...path, 'opacity']),
        fill: number(source, [...path, 'fill']),
        weight: number(source, [...path, 'weight']),
        grade: number(source, [...path, 'grade']),
        opticalSize: number(source, [...path, 'opticalSize']),
        shadows: shadows(source, [...path, 'shadows']),
        applyTextScaling: source.v<bool>([...path, 'applyTextScaling']),
      );

  /// [style] with a `packages/<package>/` family that arrived without its
  /// package split into family and package, so merging it over a packaged
  /// ambient style does not prefix it twice. Fallbacks under the same prefix
  /// lose it too.
  static TextStyle packagedFont(TextStyle style) {
    final family = style.fontFamily;
    if (family == null || !family.startsWith('packages/')) return style;
    final separator = family.indexOf('/', 'packages/'.length);
    if (separator < 0 || separator == family.length - 1) return style;
    final package = family.substring('packages/'.length, separator);
    final prefix = 'packages/$package/';
    final fallback = style.fontFamilyFallback;
    return style.copyWith(
      fontFamily: family.substring(prefix.length),
      package: package,
      fontFamilyFallback: fallback == null
          ? null
          : [
              for (final name in fallback)
                name.startsWith(prefix) ? name.substring(prefix.length) : name,
            ],
    );
  }

  /// Decodes a nullable `TextDecoration`.
  static TextDecoration? textDecoration(DataSource source, List<Object> path) {
    final mask = source.v<int>(path);
    if (mask != null) {
      if (mask < 0 || mask > 7) {
        throw const FormatException('Invalid text decoration mask');
      }
      return TextDecoration.combine([
        if (mask & 1 != 0) TextDecoration.underline,
        if (mask & 2 != 0) TextDecoration.overline,
        if (mask & 4 != 0) TextDecoration.lineThrough,
      ]);
    }
    if (source.isList(path)) {
      return TextDecoration.combine([
        for (var index = 0; index < source.length(path); index++)
          textDecoration(source, [...path, index]) ?? TextDecoration.none,
      ]);
    }
    if (source.v<String>(path) == null) return null;
    return ArgumentDecoders.textDecoration(source, path);
  }

  /// Decodes a list of `Shadow` values using rfw's box-shadow map shape.
  static List<Shadow>? shadows(DataSource source, List<Object> path) {
    if (!source.isList(path)) return null;
    return List<Shadow>.unmodifiable(
      List<Shadow>.generate(source.length(path), (index) {
        final shadowPath = <Object>[...path, index];
        return Shadow(
          color: color(source, [...shadowPath, 'color']) ??
              const Color(0xFF000000),
          offset: Offset(
            number(source, [...shadowPath, 'offset', 'x']) ?? 0,
            number(source, [...shadowPath, 'offset', 'y']) ?? 0,
          ),
          blurRadius: number(source, [...shadowPath, 'blurRadius']) ?? 0,
        );
      }),
    );
  }

  /// Decodes Restage's recursive `InlineSpan` wire shape.
  ///
  /// The root slot must be a map and returns `null` when absent, letting the
  /// generated factory enforce required-slot contracts. Malformed child
  /// elements decode to empty terminal spans so one hostile list item cannot
  /// throw out the whole tree.
  static InlineSpan? inlineSpan(DataSource source, List<Object> path,
      {BuildContext? context, RestageResources? resources}) {
    if (!source.isMap(path)) return null;
    return _inlineSpan(source, path,
        depth: 0, context: context, resources: resources);
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
    final imageAlignment = alignment(source, [...path, 'alignment']);
    return DecorationImage(
      image: provider,
      fit: RestageDecoders.enumByName<BoxFit>(
        BoxFit.values,
        source,
        [...path, 'fit'],
      ),
      // Preserve the original physical decoder's integer components. Only a
      // successfully decoded directional pair selects the new geometry path.
      alignment: imageAlignment is AlignmentDirectional
          ? imageAlignment
          : alignmentXY(source, [...path, 'alignment']) ?? Alignment.center,
      repeat: RestageDecoders.enumByName<ImageRepeat>(
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

  /// Decodes shape-border maps using flat uniform radii.
  /// Supports RoundedSuperellipseBorder, LinearBorder and StarBorder, with
  /// [borderSide] applied while preserving each variant's subtype.
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
    final side =
        _repairedBorderSide(source, [...path, 'side']) ?? BorderSide.none;
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

  /// A uniform radius, or a `{topLeft, topRight, bottomLeft, bottomRight}`
  /// map whose missing corners are square.
  static BorderRadiusGeometry _borderRadius(
    DataSource source,
    List<Object> path,
  ) {
    if (source.isMap(path)) {
      Radius corner(String name) =>
          Radius.circular(_number(source, [...path, name]) ?? 0.0);
      if (['topStart', 'topEnd', 'bottomStart', 'bottomEnd'].any(
        (name) => _number(source, [...path, name]) != null,
      )) {
        return BorderRadiusDirectional.only(
          topStart: corner('topStart'),
          topEnd: corner('topEnd'),
          bottomStart: corner('bottomStart'),
          bottomEnd: corner('bottomEnd'),
        );
      }
      return BorderRadius.only(
        topLeft: corner('topLeft'),
        topRight: corner('topRight'),
        bottomLeft: corner('bottomLeft'),
        bottomRight: corner('bottomRight'),
      );
    }
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

  static double _finiteOrZero(double value) => value.isFinite ? value : 0.0;

  static BorderSide? _repairedBorderSide(
    DataSource source,
    List<Object> path,
  ) {
    if (!source.isMap(path)) return null;
    final decodedWidth = source.v<double>([...path, 'width']) ?? 1.0;
    final width =
        decodedWidth.isFinite && decodedWidth >= 0.0 ? decodedWidth : 0.0;
    return BorderSide(
      color: color(source, [...path, 'color']) ?? const Color(0xFF000000),
      width: width,
      style: ArgumentDecoders.enumValue<BorderStyle>(
            BorderStyle.values,
            source,
            [...path, 'style'],
          ) ??
          BorderStyle.solid,
    );
  }

  static InlineSpan _inlineSpan(
    DataSource source,
    List<Object> path, {
    required int depth,
    RestageResources? resources,
    BuildContext? context,
  }) {
    if (depth > kMaxInlineSpanDepth || !source.isMap(path)) {
      return const TextSpan();
    }
    return TextSpan(
      text: string(source, [...path, 'text'], context: context),
      recognizer:
          _spanRecognizer(source, [...path, 'recognizer'], resources, context),
      style: _textStyle(source, [...path, 'style']),
      children: _inlineSpanChildren(source, [...path, 'children'],
          depth: depth + 1, context: context, resources: resources),
    );
  }

  static List<InlineSpan>? _inlineSpanChildren(
    DataSource source,
    List<Object> path, {
    required int depth,
    RestageResources? resources,
    BuildContext? context,
  }) {
    if (!source.isList(path)) return null;
    final children = <InlineSpan>[];
    final pending = <({List<Object> path, int index, int groups})>[
      (path: path, index: 0, groups: 0)
    ];
    while (pending.isNotEmpty) {
      final frame = pending.removeLast();
      if (frame.index >= source.length(frame.path)) continue;
      pending.add(
          (path: frame.path, index: frame.index + 1, groups: frame.groups));
      final childPath = [...frame.path, frame.index];
      if (source.isList(childPath)) {
        if (frame.groups < _spanCollectionGroupDepthLimit) {
          pending.add((path: childPath, index: 0, groups: frame.groups + 1));
        }
      } else {
        children.add(_inlineSpan(source, childPath,
            depth: depth, context: context, resources: resources));
      }
    }
    return children;
  }

  static GestureRecognizer? _spanRecognizer(
    DataSource source,
    List<Object> path,
    RestageResources? resources,
    BuildContext? context,
  ) {
    if (!source.isMap(path)) return null;
    if (source.v<String>([...path, 'borrowed', 'program']) != null ||
        source.isMap([...path, 'borrowed'])) {
      if (context == null)
        throw StateError('A borrowed recognizer requires its native context.');
      return RestageValueBinding.readNative<GestureRecognizer>(
        source,
        [...path, 'borrowed'],
        context,
        type: 'flutter.GestureRecognizer',
      );
    }
    final kind = source.v<String>([...path, 'kind']);
    void Function(D)? callback<D extends Object>(String name) {
      if (source.v<String>([...path, name, 'program']) == null &&
          !source.isMap([...path, name])) return null;
      if (context == null)
        throw StateError('A native gesture callback requires its context.');
      final native = RestageValueBinding.readNative<void Function(D)>(
        source,
        [...path, name],
        context,
        type: kTextSpanRecognizerDetailCallbacks[kind]![name]!,
      );
      final measure = source.voidHandler([...path, '${name}Measurement']);
      if (native == null || measure == null) return native;
      return (details) {
        native(details);
        measure();
      };
    }

    if (resources == null)
      throw StateError(
        'Interactive spans require a RestageResourceBuilder owner.',
      );
    final devicesPath = [...path, 'supportedDevices'];
    final devices = source.isList(devicesPath)
        ? <PointerDeviceKind>{
            for (var index = 0; index < source.length(devicesPath); index++)
              PointerDeviceKind.values.byName(
                source.v<String>([...devicesPath, index])!,
              ),
          }
        : null;
    final slopArguments = <Symbol, Object?>{};
    for (final (name, symbol) in const [
      ('preAcceptSlopTolerance', #preAcceptSlopTolerance),
      ('postAcceptSlopTolerance', #postAcceptSlopTolerance),
    ]) {
      final presence = RestageRfwConstructorPresence.read(source, [
        ...path,
        name,
      ]);
      if (presence.supplied)
        slopArguments[symbol] = number(source, presence.valuePath);
    }
    switch (kind) {
      case 'tap':
        final recognizer = Function.apply(TapGestureRecognizer.new, const [], {
          #supportedDevices: devices,
          ...slopArguments,
        }) as TapGestureRecognizer;
        final handle = resources.manage<TapGestureRecognizer>(
          recognizer,
          dispose: (value) {
            value.onTapDown = null;
            value.onSecondaryTapDown = null;
            value.onTertiaryTapDown = null;
            value.onTapUp = null;
            value.onSecondaryTapUp = null;
            value.onTertiaryTapUp = null;
            value.onTapMove = null;
            value.onTap = null;
            value.onTapCancel = null;
            value.onSecondaryTap = null;
            value.onSecondaryTapCancel = null;
            value.onTertiaryTapCancel = null;
            value.dispose();
          },
        );
        recognizer.onTapDown = callback<TapDownDetails>('onTapDown');
        recognizer.onSecondaryTapDown =
            callback<TapDownDetails>('onSecondaryTapDown');
        recognizer.onTertiaryTapDown =
            callback<TapDownDetails>('onTertiaryTapDown');
        recognizer.onTapUp = callback<TapUpDetails>('onTapUp');
        recognizer.onSecondaryTapUp =
            callback<TapUpDetails>('onSecondaryTapUp');
        recognizer.onTertiaryTapUp = callback<TapUpDetails>('onTertiaryTapUp');
        recognizer.onTapMove = callback<TapMoveDetails>('onTapMove');
        recognizer.onTap = source.voidHandler([...path, 'onTap']);
        recognizer.onTapCancel = source.voidHandler([...path, 'onTapCancel']);
        recognizer.onSecondaryTap = source.voidHandler([
          ...path,
          'onSecondaryTap',
        ]);
        recognizer.onSecondaryTapCancel = source.voidHandler([
          ...path,
          'onSecondaryTapCancel',
        ]);
        recognizer.onTertiaryTapCancel = source.voidHandler([
          ...path,
          'onTertiaryTapCancel',
        ]);
        recognizer.team = _ResourceArenaTeam(handle.retain, handle.settle);
        return recognizer;
      case 'doubleTap':
        final recognizer = DoubleTapGestureRecognizer(
          supportedDevices: devices,
        );
        resources.own<DoubleTapGestureRecognizer>(
          recognizer,
          dispose: (value) {
            value.onDoubleTapDown = null;
            value.onDoubleTap = null;
            value.onDoubleTapCancel = null;
            value.dispose();
          },
          settleDelay: kDoubleTapTimeout,
        );
        recognizer.onDoubleTapDown =
            callback<TapDownDetails>('onDoubleTapDown');
        recognizer.onDoubleTap = source.voidHandler([...path, 'onDoubleTap']);
        recognizer.onDoubleTapCancel = source.voidHandler([
          ...path,
          'onDoubleTapCancel',
        ]);
        return recognizer;
      case 'longPress':
        if (slopArguments.containsKey(#preAcceptSlopTolerance))
          throw StateError(
            'Long press has no pre-accept slop constructor argument.',
          );
        final recognizer =
            Function.apply(LongPressGestureRecognizer.new, const [], {
          #supportedDevices: devices,
          #duration: duration(source, [...path, 'duration']),
          ...slopArguments,
        }) as LongPressGestureRecognizer;
        final handle = resources.manage<LongPressGestureRecognizer>(
          recognizer,
          dispose: (value) {
            value.onLongPressDown = null;
            value.onLongPressStart = null;
            value.onLongPressMoveUpdate = null;
            value.onLongPressEnd = null;
            value.onSecondaryLongPressDown = null;
            value.onSecondaryLongPressStart = null;
            value.onSecondaryLongPressMoveUpdate = null;
            value.onSecondaryLongPressEnd = null;
            value.onTertiaryLongPressDown = null;
            value.onTertiaryLongPressStart = null;
            value.onTertiaryLongPressMoveUpdate = null;
            value.onTertiaryLongPressEnd = null;
            value.onLongPress = null;
            value.onLongPressUp = null;
            value.onLongPressCancel = null;
            value.onSecondaryLongPress = null;
            value.onSecondaryLongPressUp = null;
            value.onSecondaryLongPressCancel = null;
            value.onTertiaryLongPress = null;
            value.onTertiaryLongPressUp = null;
            value.onTertiaryLongPressCancel = null;
            value.dispose();
          },
        );
        recognizer.onLongPressDown =
            callback<LongPressDownDetails>('onLongPressDown');
        recognizer.onLongPressStart =
            callback<LongPressStartDetails>('onLongPressStart');
        recognizer.onLongPressMoveUpdate =
            callback<LongPressMoveUpdateDetails>('onLongPressMoveUpdate');
        recognizer.onLongPressEnd =
            callback<LongPressEndDetails>('onLongPressEnd');
        recognizer.onSecondaryLongPressDown =
            callback<LongPressDownDetails>('onSecondaryLongPressDown');
        recognizer.onSecondaryLongPressStart =
            callback<LongPressStartDetails>('onSecondaryLongPressStart');
        recognizer.onSecondaryLongPressMoveUpdate =
            callback<LongPressMoveUpdateDetails>(
                'onSecondaryLongPressMoveUpdate');
        recognizer.onSecondaryLongPressEnd =
            callback<LongPressEndDetails>('onSecondaryLongPressEnd');
        recognizer.onTertiaryLongPressDown =
            callback<LongPressDownDetails>('onTertiaryLongPressDown');
        recognizer.onTertiaryLongPressStart =
            callback<LongPressStartDetails>('onTertiaryLongPressStart');
        recognizer.onTertiaryLongPressMoveUpdate =
            callback<LongPressMoveUpdateDetails>(
                'onTertiaryLongPressMoveUpdate');
        recognizer.onTertiaryLongPressEnd =
            callback<LongPressEndDetails>('onTertiaryLongPressEnd');
        recognizer.onLongPress = source.voidHandler([...path, 'onLongPress']);
        recognizer.onLongPressUp = source.voidHandler([
          ...path,
          'onLongPressUp',
        ]);
        recognizer.onLongPressCancel = source.voidHandler([
          ...path,
          'onLongPressCancel',
        ]);
        recognizer.onSecondaryLongPress = source.voidHandler([
          ...path,
          'onSecondaryLongPress',
        ]);
        recognizer.onSecondaryLongPressUp = source.voidHandler([
          ...path,
          'onSecondaryLongPressUp',
        ]);
        recognizer.onSecondaryLongPressCancel = source.voidHandler([
          ...path,
          'onSecondaryLongPressCancel',
        ]);
        recognizer.onTertiaryLongPress = source.voidHandler([
          ...path,
          'onTertiaryLongPress',
        ]);
        recognizer.onTertiaryLongPressUp = source.voidHandler([
          ...path,
          'onTertiaryLongPressUp',
        ]);
        recognizer.onTertiaryLongPressCancel = source.voidHandler([
          ...path,
          'onTertiaryLongPressCancel',
        ]);
        recognizer.team = _ResourceArenaTeam(handle.retain, handle.settle);
        return recognizer;
      default:
        throw StateError('Unsupported native span recognizer: $kind');
    }
  }

  static TextStyle? _textStyle(DataSource source, List<Object> path) {
    if (!source.isMap(path)) return null;
    return packagedFont(TextStyle(
      inherit: source.v<bool>([...path, 'inherit']) ?? true,
      color: color(source, [...path, 'color']),
      backgroundColor: color(source, [...path, 'backgroundColor']),
      fontSize: _finiteNumber(source, [...path, 'fontSize']),
      fontWeight: fontWeight(source, [...path, 'fontWeight']),
      fontStyle: RestageDecoders.enumByName<FontStyle>(
        FontStyle.values,
        source,
        [...path, 'fontStyle'],
      ),
      letterSpacing: _finiteNumber(source, [...path, 'letterSpacing']),
      wordSpacing: _finiteNumber(source, [...path, 'wordSpacing']),
      textBaseline: RestageDecoders.enumByName<TextBaseline>(
        TextBaseline.values,
        source,
        [...path, 'textBaseline'],
      ),
      height: _finiteNumber(source, [...path, 'height']),
      leadingDistribution: RestageDecoders.enumByName<TextLeadingDistribution>(
        TextLeadingDistribution.values,
        source,
        [...path, 'leadingDistribution'],
      ),
      locale: ArgumentDecoders.locale(source, [...path, 'locale']),
      foreground: paint(source, [...path, 'foreground']),
      background: paint(source, [...path, 'background']),
      shadows: shadows(source, [...path, 'shadows']),
      fontFeatures: fontFeatures(source, [...path, 'fontFeatures']),
      fontVariations: fontVariations(source, [...path, 'fontVariations']),
      decoration: textDecoration(source, [...path, 'decoration']),
      decorationColor: color(source, [...path, 'decorationColor']),
      decorationStyle: RestageDecoders.enumByName<TextDecorationStyle>(
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
      overflow: RestageDecoders.enumByName<TextOverflow>(
        TextOverflow.values,
        source,
        [...path, 'overflow'],
      ),
    ));
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

  /// Decodes a `String` slot: a string, or a list of strings joined in order.
  /// A non-string part reads as empty. Absent → null.
  static String? string(DataSource source, List<Object> path,
      {BuildContext? context}) {
    if (source.isMap(path) && source.v<String>([...path, 'program']) != null) {
      return RestageValueBinding.read<String>(source, path, context);
    }
    final value = source.v<String>(path);
    if (value != null || !source.isList(path)) return value;
    return [
      for (var index = 0; index < source.length(path); index++)
        RestageValueBinding.read<String>(source, [...path, index], context) ??
            '',
    ].join();
  }

  /// Decodes a `List<int>` slot, dropping any entry that is not an int.
  /// Absent → null; a present list, even an empty one, is a list.
  static List<int>? integerList(DataSource source, List<Object> path) {
    if (!source.isList(path)) return null;
    final count = source.length(path);
    return [
      for (var index = 0; index < count; index++)
        if (source.v<int>([...path, index]) case final value?) value,
    ];
  }

  /// Decodes a `List<double>` slot, reading an int entry as a double and
  /// dropping any other entry. Absent → null.
  static List<double>? realList(DataSource source, List<Object> path) {
    if (!source.isList(path)) return null;
    final count = source.length(path);
    return [
      for (var index = 0; index < count; index++)
        if (source.v<double>([...path, index]) ??
                source.v<int>([...path, index])?.toDouble()
            case final value?)
          value,
    ];
  }

  /// Adapts a built slot value to a `PreferredSizeWidget` argument at
  /// [height], or the standard toolbar height when none is given. `null`
  /// when the slot is absent.
  static PreferredSizeWidget? optionalPreferredSize(
    Widget? child, [
    double? height,
  ]) =>
      child == null ? null : preferredSize(child, height);

  /// Adapts an AppBar slot while preserving its native themed toolbar height.
  static PreferredSizeWidget? appBarPreferredSize(
    Widget? child,
    double? height,
    double? toolbarHeight,
    double? bottomHeight,
  ) {
    if (child == null) return null;
    if (bottomHeight == null) return preferredSize(child, height);
    return RestagePreferredSizeSlot.appBar(
      toolbarHeight: toolbarHeight,
      bottomHeight: bottomHeight,
      child: child,
    );
  }

  /// Decodes the bottom height of an AppBar slot. A supplied null is a nested
  /// AppBar's unset toolbar height, which Flutter sizes at `kToolbarHeight`.
  static double? appBarBottomHeight(DataSource source, List<Object> path) {
    if (!source.isMap(path)) return number(source, path);
    final version =
        source.v<int>([...path, RfwConstructorPresenceProtocol.markerKey]);
    if (version != RfwConstructorPresenceProtocol.version) return null;
    return number(source, [...path, RfwConstructorPresenceProtocol.valueKey]) ??
        kRestagePreferredSlotHeight;
  }

  /// Adapts a built slot value to a required `PreferredSizeWidget`
  /// argument at [height], or the standard toolbar height.
  static PreferredSizeWidget preferredSize(Widget child, [double? height]) =>
      RestagePreferredSizeSlot(
        preferredHeight: height ?? kRestagePreferredSlotHeight,
        child: child,
      );
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

const Map<String, TextInputType> _supportedTextInputTypesByName = {
  'text': TextInputType.text,
  'multiline': TextInputType.multiline,
  'number': TextInputType.number,
  'phone': TextInputType.phone,
  'emailAddress': TextInputType.emailAddress,
  'url': TextInputType.url,
  'name': TextInputType.name,
};

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

// Observes the native arena entry without adding a competing member.
final class _ResourceArenaTeam extends GestureArenaTeam {
  _ResourceArenaTeam(this.retain, this.settle);
  final void Function(int) retain;
  final void Function(int) settle;

  @override
  GestureArenaEntry add(int pointer, GestureArenaMember member) {
    retain(pointer);
    return GestureBinding.instance.gestureArena
        .add(pointer, _ResourceArenaMember(member, settle));
  }
}

final class _ResourceArenaMember implements GestureArenaMember {
  _ResourceArenaMember(this.member, this.settle);
  final GestureArenaMember member;
  final void Function(int) settle;

  @override
  void acceptGesture(int pointer) {
    try {
      member.acceptGesture(pointer);
    } finally {
      settle(pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    try {
      member.rejectGesture(pointer);
    } finally {
      settle(pointer);
    }
  }
}
