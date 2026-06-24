import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:rfw_catalog_compiler/src/policy/theme_binding_seeds.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Resolves the default of a constructor parameter into a
/// [DefaultValueSource], per the catalog output rule. This is the
/// element-facing entry point the reflector calls — it holds the live
/// [FormalParameterElement] and so can recover identifier names that a
/// bare [DartObject] cannot (true enum members, class static-consts).
///
/// [targetType] is the property's resolved [PropertyType]. It gates the
/// class-static-const recovery branch: a class-static-const member name is
/// only a type-correct catalog literal for the string-backed static-const
/// property types listed in [_staticConstMemberNameTypes]. For any other type
/// a recovered member name (e.g. `'zero'` for `EdgeInsets.zero`) would be a
/// parity-breaking, type-wrong literal — so that branch is skipped.
///
/// Output rule:
///   1. No default, or the default evaluates to `null` → `null` (no claim).
///   2. Primitive literal (String / bool / int / finite-double / List) →
///      [LiteralDefault].
///   3. True Dart enum member → `LiteralDefault(memberName)` (regardless
///      of [targetType]).
///   4. Class static-const identifier resolvable to a member name, ONLY
///      when [targetType] is [PropertyType.alignment] or
///      [PropertyType.curve] →
///      `LiteralDefault(memberName)`.
///   5. Any other present-but-non-bakeable default → `null` (no claim).
///      The mechanical resolver never synthesizes [FlutterCtorDefault] —
///      that variant is an explicit curator/annotation delegation signal,
///      not something the mechanical pass should record.
DefaultValueSource? resolveParameterDefault(
  FormalParameterElement param, {
  required PropertyType targetType,
}) {
  final value = param.computeConstantValue();
  if (value == null || value.isNull) return null;

  // True enum member: the DartObject carries an implicit `_name` field.
  final typeElement = value.type?.element;
  if (typeElement is EnumElement) {
    final name = value.getField('_name')?.toStringValue();
    if (name != null) return LiteralDefault(name);
  }

  // Plain literal (String / bool / num / list).
  final literal = literalFromDartObject(value);
  if (literal != null) return LiteralDefault(literal);

  // A non-finite double (infinity / NaN) is not a bakeable catalog
  // literal; the catalog makes no claim and Flutter's ctor default
  // applies. Guard before the static-const fallback so the value is
  // not mis-recovered as a `double` static-const member name.
  final doubleValue = value.toDoubleValue();
  if (doubleValue != null && !doubleValue.isFinite) return null;

  // Class static-const identifier (e.g. `AlignmentDirectional.topStart`).
  // No `_name` field exists; recover the member name by matching the
  // value against the declaring class's static-const fields. This is only
  // type-correct for string-backed static-const properties — the catalog
  // stores the member name as a string and codegen re-qualifies it. For any
  // other property type a recovered member name would be a type-wrong literal,
  // so the branch is skipped and the default falls through to "no claim".
  if (_staticConstMemberNameTypes.contains(targetType)) {
    final memberName = staticConstMemberName(value);
    if (memberName != null) return LiteralDefault(memberName);
  }

  // Default present, but not a bakeable literal — the catalog makes no
  // claim. The mechanical resolver never synthesizes FlutterCtorDefault.
  return null;
}

const Set<PropertyType> _staticConstMemberNameTypes = {
  PropertyType.alignment,
  PropertyType.curve,
};

/// Returns the name of the static-const field on [value]'s declaring
/// class whose constant value structurally equals [value], or `null`
/// when [value] is not a class-typed value or no field matches.
///
/// Matching is by structural [DartObject] equality. When two or more
/// static-consts are structurally identical (same type, same field
/// values), the value cannot be unambiguously attributed to one member,
/// so this returns `null` — the caller then makes no catalog claim
/// rather than silently baking the wrong member name. Value-bearing const
/// families such as `AlignmentDirectional`, whose members all differ,
/// resolve cleanly; a fieldless const family where every member is
/// structurally equal resolves to `null`.
String? staticConstMemberName(DartObject value) {
  final typeElement = value.type?.element;
  if (typeElement is! ClassElement) return null;
  final matches = <String>[];
  for (final field in typeElement.fields) {
    if (!field.isStatic || !field.isConst) continue;
    final fieldValue = field.computeConstantValue();
    if (fieldValue != null && fieldValue == value) {
      final name = field.name;
      if (name != null) matches.add(name);
    }
  }
  return matches.length == 1 ? matches.single : null;
}

/// Resolves a parameter's pre-computed constant default into a
/// [DefaultValueSource], following the catalog output rule. Returns
/// `null` when the catalog makes no claim about the default.
///
/// This is the literal-only core; [resolveParameterDefault] is the
/// element-facing entry point that additionally handles enum and
/// class-static-const identifiers.
///
/// [hasDefault] distinguishes a parameter with no `=` default at all
/// from one whose default evaluates to `null`; both map to a `null`
/// return, so this is informational only here.
DefaultValueSource? resolveDefaultFromConstant({
  required bool hasDefault,
  required DartObject? value,
}) {
  if (!hasDefault || value == null || value.isNull) return null;
  final literal = literalFromDartObject(value);
  if (literal != null) return LiteralDefault(literal);
  // Default is present but not a bakeable literal — the catalog makes no
  // claim. The mechanical resolver never synthesizes FlutterCtorDefault;
  // that variant records explicit curator delegation intent.
  return null;
}

/// Resolves a theme-binding default for [widgetName].[propertyName] by
/// looking the pair up in the policy's [seeds] table. Returns `null`
/// when no seed matches. This is deterministic table application — not
/// analyzer source inference; the seed table is a hand-maintained
/// policy artifact.
ThemeBindingDefault? resolveThemeBindingDefault({
  required String widgetName,
  required String propertyName,
  required ThemeBindingSeeds seeds,
}) {
  final path = seeds.namePatterns['$widgetName.$propertyName'];
  if (path == null) return null;
  return ThemeBindingDefault(path);
}

/// Classifies a [DartObject] into a catalog-bakeable literal, or `null`
/// when the value is not a supported literal shape. Mirrors the reflector's
/// `_decodePrimitive` classification so the projected `defaultValue` stays
/// byte-identical across the two default-resolution paths.
///
/// Supported shapes: [String], [bool], [int], finite [double], Dart enum
/// members (decoded to their member name), and [List] of these. Non-finite
/// doubles (infinity, NaN) are dropped to `null` because they are not
/// representable as JSON numbers. A nested list element that is not itself
/// a supported literal becomes a `null` hole at its position — the list is
/// preserved positionally rather than dropped, matching `_decodePrimitive`'s
/// behaviour. The enum branch is shared by the top-level and list-recursion
/// paths so `const [E.a]` decodes to `['a']`, matching the reflector.
Object? literalFromDartObject(DartObject value) {
  final stringValue = value.toStringValue();
  if (stringValue != null) return stringValue;
  final boolValue = value.toBoolValue();
  if (boolValue != null) return boolValue;
  final intValue = value.toIntValue();
  if (intValue != null) return intValue;
  final doubleValue = value.toDoubleValue();
  if (doubleValue != null) return doubleValue.isFinite ? doubleValue : null;
  // Dart enum member: the DartObject carries an implicit `_name` field.
  // Mirrors the reflector's `_decodePrimitive` enum branch so a nested enum in
  // a list (`const [E.a]`) decodes to its member name rather than a hole.
  if (value.type?.element is EnumElement) {
    final name = value.getField('_name')?.toStringValue();
    if (name != null) return name;
  }
  final listValue = value.toListValue();
  if (listValue != null) {
    final elements = <Object?>[];
    for (final element in listValue) {
      elements.add(literalFromDartObject(element));
    }
    return elements;
  }
  return null;
}
