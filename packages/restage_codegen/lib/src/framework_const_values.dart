import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/theme_recognition.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Prefix of the per-corner `BorderRadius` value the host property-emit
/// splices onto the per-corner catalog slots; it never reaches the blob.
const String kBorderRadiusCornerSentinel = '__rfw_border_radius_corners(';

/// Rewrites every per-corner sentinel in [dsl] as a corner map, the form a
/// radius inside a structured value such as a shape takes.
String borderRadiusCornersAsMap(String dsl) => dsl.replaceAllMapped(
      RegExp('${RegExp.escape(kBorderRadiusCornerSentinel)}([^()]*)\\)'),
      (match) => '{${match[1]}}',
    );

/// Canonical corner order for the per-corner sentinel.
const List<String> kBorderRadiusCornerOrder = [
  'topLeft',
  'topRight',
  'bottomLeft',
  'bottomRight',
];

/// The wire value of a framework constant, and the kind of slot it fits.
final class FrameworkConstValue {
  /// Creates an encoded constant.
  const FrameworkConstValue(this.kind, this.dsl);

  /// What the value is.
  final FrameworkConstKind kind;

  /// The value as RFW text.
  final String dsl;

  /// Whether a slot of [type] decodes this value.
  bool fits(PropertyType type) => switch (kind) {
        FrameworkConstKind.alignment =>
          type == PropertyType.alignment || type == PropertyType.alignmentXY,
        FrameworkConstKind.directionalAlignment =>
          type == PropertyType.alignment,
        FrameworkConstKind.color => type == PropertyType.color,
        FrameworkConstKind.duration => type == PropertyType.duration,
        FrameworkConstKind.offset => type == PropertyType.offset,
        FrameworkConstKind.systemUiOverlayStyle =>
          type == PropertyType.structured,
        // The catalog carries a radius as a number.
        FrameworkConstKind.borderRadius ||
        FrameworkConstKind.radius =>
          type == PropertyType.real,
      };
}

/// The wire shapes a framework constant encodes to.
enum FrameworkConstKind {
  /// `{x, y}`.
  alignment,

  /// `{start, y}`.
  directionalAlignment,

  /// A packed ARGB integer.
  color,

  /// Whole milliseconds.
  duration,

  /// `{x, y}`.
  offset,

  /// A system overlay style field map.
  systemUiOverlayStyle,

  /// A uniform radius scalar, or the per-corner sentinel.
  borderRadius,

  /// A circular radius scalar.
  radius;

  /// The value described for a diagnostic.
  String get label => switch (this) {
        alignment => 'an alignment',
        directionalAlignment => 'a directional alignment',
        color => 'a color',
        duration => 'a duration',
        offset => 'an offset',
        systemUiOverlayStyle => 'a system overlay style',
        borderRadius => 'a border radius',
        radius => 'a radius',
      };
}

/// The evaluated value of a static const member declared by a framework
/// library (`Alignment.centerLeft`, `Colors.white70`, `Duration.zero`), or
/// null when [expr] is not such a reference.
DartObject? frameworkStaticConst(Expression expr) {
  final element = switch (expr) {
    PrefixedIdentifier(:final identifier) => identifier.element,
    PropertyAccess(:final propertyName) => propertyName.element,
    _ => null,
  };
  if (element is! PropertyAccessorElement) return null;
  final variable = element.variable;
  if (variable is! FieldElement || !variable.isStatic || !variable.isConst) {
    return null;
  }
  if (!isFrameworkValueTypeLibrary(variable)) return null;
  return variable.computeConstantValue();
}

/// Encodes an evaluated framework constant by its runtime class, or null when
/// the class has no wire encoding.
FrameworkConstValue? encodeFrameworkConst(DartObject value) {
  final overlayFields = systemUiOverlayStyleFields(value);
  if (overlayFields != null) {
    final entries = <String>[];
    for (final field in overlayFields.entries) {
      if (field.value.isNull) continue;
      final encoded = encodeSystemUiOverlayStyleField(field.key, field.value);
      if (encoded == null) return null;
      entries.add('${field.key}: $encoded');
    }
    return FrameworkConstValue(
      FrameworkConstKind.systemUiOverlayStyle,
      '{${entries.join(', ')}}',
    );
  }
  final classes = _classNames(value);
  if (classes.contains('AlignmentDirectional')) {
    final start = _double(value, 'start');
    final y = _double(value, 'y');
    if (start == null || y == null) return null;
    return FrameworkConstValue(
      FrameworkConstKind.directionalAlignment,
      '{start: $start, y: $y}',
    );
  }
  if (classes.contains('Alignment')) {
    final x = _double(value, 'x');
    final y = _double(value, 'y');
    if (x == null || y == null) return null;
    return FrameworkConstValue(FrameworkConstKind.alignment, '{x: $x, y: $y}');
  }
  if (classes.contains('Offset')) {
    final x = _double(value, '_dx');
    final y = _double(value, '_dy');
    if (x == null || y == null) return null;
    return FrameworkConstValue(FrameworkConstKind.offset, '{x: $x, y: $y}');
  }
  if (classes.contains('Radius')) {
    final r = _circular(value);
    if (r == null) return null;
    return FrameworkConstValue(FrameworkConstKind.radius, '$r');
  }
  if (classes.contains('BorderRadiusDirectional')) {
    // Without a text direction only a uniform radius has a single value.
    final corners = [
      for (final c in ['topStart', 'topEnd', 'bottomStart', 'bottomEnd'])
        _circularField(value, c),
    ];
    if (corners.contains(null) || corners.toSet().length != 1) return null;
    return FrameworkConstValue(
      FrameworkConstKind.borderRadius,
      '${corners.first}',
    );
  }
  if (classes.contains('BorderRadius')) {
    final corners = {
      for (final c in kBorderRadiusCornerOrder) c: _circularField(value, c),
    };
    if (corners.values.contains(null)) return null;
    final radii = corners.values.toSet();
    return FrameworkConstValue(
      FrameworkConstKind.borderRadius,
      radii.length == 1
          ? '${radii.single}'
          : '$kBorderRadiusCornerSentinel${[
              for (final e in corners.entries) '${e.key}: ${e.value}',
            ].join(', ')})',
    );
  }
  if (classes.contains('Duration')) {
    final micros =
        (_field(value, 'inMicroseconds') ?? _field(value, '_duration'))
            ?.toIntValue();
    if (micros == null || micros % 1000 != 0) return null;
    return FrameworkConstValue(
      FrameworkConstKind.duration,
      '${micros ~/ 1000}',
    );
  }
  // A dynamic colour resolves against the build context, so it has no single
  // wire value.
  if (classes.contains('Color') && !classes.contains('CupertinoDynamicColor')) {
    final argb = _argb(value);
    if (argb == null) return null;
    return FrameworkConstValue(
      FrameworkConstKind.color,
      '0x${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}',
    );
  }
  return null;
}

/// Nullable fields shared by the overlay constructor and `copyWith`.
const Map<String, PropertyType> kSystemUiOverlayStyleFields = {
  'systemNavigationBarColor': PropertyType.color,
  'systemNavigationBarDividerColor': PropertyType.color,
  'systemNavigationBarIconBrightness': PropertyType.enumValue,
  'systemNavigationBarContrastEnforced': PropertyType.boolean,
  'statusBarColor': PropertyType.color,
  'statusBarBrightness': PropertyType.enumValue,
  'statusBarIconBrightness': PropertyType.enumValue,
  'systemStatusBarContrastEnforced': PropertyType.boolean,
};

/// Recognizes the canonical Flutter overlay style class.
bool isSystemUiOverlayStyleClass(Element? element) =>
    element is ClassElement &&
    element.name == 'SystemUiOverlayStyle' &&
    element.library.identifier ==
        'package:flutter/src/services/system_chrome.dart';

/// Recognizes the canonical Flutter icon theme class.
bool isIconThemeDataClass(Element? element) =>
    element is ClassElement &&
    element.name == 'IconThemeData' &&
    element.library.identifier ==
        'package:flutter/src/widgets/icon_theme_data.dart';

/// Recognizes Flutter's instance method, including calls through aliases.
bool isSystemUiOverlayStyleCopyWith(MethodInvocation expression) =>
    _isMethodOf(expression, 'copyWith', isSystemUiOverlayStyleClass);

/// Recognizes Flutter's `IconThemeData.copyWith`.
bool isIconThemeDataCopyWith(MethodInvocation expression) =>
    _isMethodOf(expression, 'copyWith', isIconThemeDataClass);

/// Recognizes Flutter's static `IconThemeData.lerp`.
bool isIconThemeDataLerp(MethodInvocation expression) =>
    _isMethodOf(expression, 'lerp', isIconThemeDataClass, isStatic: true);

bool _isMethodOf(
  MethodInvocation expression,
  String name,
  bool Function(Element?) isClass, {
  bool isStatic = false,
}) {
  final method = expression.methodName.element;
  return method is MethodElement &&
      method.name == name &&
      method.isStatic == isStatic &&
      isClass(method.enclosingElement);
}

/// Reads evaluated fields without duplicating Flutter's static constants.
Map<String, DartObject>? systemUiOverlayStyleFields(DartObject value) {
  if (!isSystemUiOverlayStyleClass(value.type?.element)) return null;
  final fields = <String, DartObject>{};
  for (final name in kSystemUiOverlayStyleFields.keys) {
    final field = value.getField(name);
    if (field == null) return null;
    fields[name] = field;
  }
  return fields;
}

/// Encodes one evaluated nullable overlay field.
String? encodeSystemUiOverlayStyleField(String name, DartObject value) {
  if (value.isNull) return 'null';
  return switch (kSystemUiOverlayStyleFields[name]) {
    PropertyType.color => encodeFrameworkConst(value)?.dsl,
    PropertyType.boolean => value.toBoolValue()?.toString(),
    PropertyType.enumValue => switch (
          value.getField('_name')?.toStringValue()) {
        final String name => '"$name"',
        _ => null,
      },
    _ => null,
  };
}

/// The value's class and every supertype declared by a framework library.
Set<String> _classNames(DartObject value) {
  final type = value.type;
  if (type is! InterfaceType) return const {};
  return {
    for (final t in [type, ...type.element.allSupertypes])
      if (isFrameworkValueTypeLibrary(t.element)) t.element.name ?? '',
  };
}

/// A field of [value], looked up through its superclass chain.
DartObject? _field(DartObject value, String name) {
  DartObject? current = value;
  while (current != null) {
    final field = current.getField(name);
    if (field != null) return field;
    current = current.getField('(super)');
  }
  return null;
}

double? _double(DartObject value, String name) {
  final field = _field(value, name);
  final d = field?.toDoubleValue() ?? field?.toIntValue()?.toDouble();
  return d != null && d.isFinite ? d : null;
}

/// The radius of a circular `Radius`, or null for an elliptical one.
double? _circular(DartObject radius) {
  final x = _double(radius, 'x');
  final y = _double(radius, 'y');
  return x != null && x == y ? x : null;
}

double? _circularField(DartObject value, String name) {
  final radius = _field(value, name);
  return radius == null ? null : _circular(radius);
}

int? _argb(DartObject value) {
  final legacy = _field(value, 'value')?.toIntValue();
  if (legacy != null) return legacy;
  final space = _field(value, 'colorSpace');
  if (space != null && _field(space, '_name')?.toStringValue() != 'sRGB') {
    return null;
  }
  int channel(String name) {
    final c = _double(value, name);
    return c == null ? -1 : (c * 255.0).round() & 0xff;
  }

  final a = channel('a');
  final r = channel('r');
  final g = channel('g');
  final b = channel('b');
  if ([a, r, g, b].contains(-1)) return null;
  return (a << 24) | (r << 16) | (g << 8) | b;
}
