import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart'
    show StructuredKind, classifyStructured, dartCoreMapType;
import 'package:rfw_catalog_compiler/src/policy/policy_ledger.dart';
import 'package:rfw_catalog_compiler/src/walker/record_shape_resolver.dart';
import 'package:rfw_catalog_compiler/src/walker/type_alias_unwrapper.dart';
import 'package:rfw_catalog_compiler/src/walker/value_shape_resolver.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Which Dart type a map slot's keys have.
enum MapKeyKind {
  /// Keys are `String` values, carried verbatim.
  string,

  /// Keys are enum constants, carried as their member names.
  enumValue,
}

/// Classification of a Dart type at the map-slot boundary.
sealed class MapClassification {
  const MapClassification();
}

/// The classified type is not a map at all; the caller falls through to its
/// existing handling.
final class NotAMap extends MapClassification {
  /// Creates the not-a-map verdict.
  const NotAMap();
}

/// The classified type is a map inside the admitted boundary.
final class MapAdmitted extends MapClassification {
  /// Creates the admitted verdict.
  const MapAdmitted({
    required this.keyKind,
    required this.valueShape,
    required this.valueType,
    this.keyEnumRef,
    this.nestedValue,
  });

  /// Whether keys are strings or enum constants.
  final MapKeyKind keyKind;

  /// The enum's source-qualified type, set iff [keyKind] is
  /// [MapKeyKind.enumValue].
  final DartTypeRef? keyEnumRef;

  /// The build-time shape of the map's value.
  ///
  /// This never reaches the catalog: the slot itself is described by the
  /// opaque map marker, and the value's shape rides the build-time plan.
  final CatalogValueShape valueShape;

  /// The analyzer type of the map's value.
  final DartType valueType;

  /// The value's own classification when the value is itself a map, so a
  /// nested map carries a complete recipe.
  final MapAdmitted? nestedValue;
}

/// The classified type is a map outside the admitted boundary.
final class MapExcluded extends MapClassification {
  /// Creates the excluded verdict carrying [reason].
  const MapExcluded(this.reason);

  /// Customer-actionable sentence naming the offending key, value or slot.
  final String reason;
}

/// The verdict for a map of a customer data class in a position that does not
/// yet admit structured values. Shared by the two arms that can reach it (the
/// admitted-structured arm and the unresolvable-shape fallback) so they cannot
/// drift into telling the customer two different things about one boundary.
const _mapOfDataClassNotOnFieldExcluded = MapExcluded(
  'a map of a customer data class is supported on a widget property but '
  'not yet on a field of a data class; move the map to a widget property',
);

/// Classifies [type] against the map value boundary.
MapClassification classifyMapType(
  DartType type, {
  required bool structuredValuesAdmitted,
  WidgetLibrary? library,
  PolicyLedger? policy,
}) {
  // Read the slot's nullability BEFORE any alias unwrapping: unwrapping
  // discards the outer suffix, so a nullable alias would read as
  // non-nullable. The order here is deliberate — do not hoist an unwrap
  // above this check.
  final originalSlotIsNullable =
      type.nullabilitySuffix != NullabilitySuffix.none;
  final unwrapped = dartCoreMapType(unwrapTypeAliases(type));
  if (unwrapped == null) return const NotAMap();

  if (originalSlotIsNullable ||
      unwrapped.nullabilitySuffix != NullabilitySuffix.none) {
    return const MapExcluded(
      'a nullable map slot is unsupported; use a non-nullable map',
    );
  }

  final keyType = unwrapped.typeArguments[0];
  final originalKeyIsNullable =
      keyType.nullabilitySuffix != NullabilitySuffix.none;
  final unwrappedKeyType = unwrapTypeAliases(keyType);
  if (originalKeyIsNullable ||
      unwrappedKeyType.nullabilitySuffix != NullabilitySuffix.none) {
    return MapExcluded(
      'a nullable map key ${keyType.getDisplayString()} is unsupported; '
      'use a non-nullable key',
    );
  }

  final MapKeyKind keyKind;
  final DartTypeRef? keyEnumRef;
  if (unwrappedKeyType is InterfaceType &&
      _isDartCoreClass(unwrappedKeyType, 'String')) {
    keyKind = MapKeyKind.string;
    keyEnumRef = null;
  } else if (unwrappedKeyType is InterfaceType &&
      unwrappedKeyType.element is EnumElement) {
    final enumElement = unwrappedKeyType.element as EnumElement;
    keyKind = MapKeyKind.enumValue;
    keyEnumRef = DartTypeRef(
      libraryUri: enumElement.library.identifier,
      symbolName: enumElement.name ?? unwrappedKeyType.getDisplayString(),
    );
  } else {
    return MapExcluded(
      'map key type ${keyType.getDisplayString()} is unsupported; '
      'use String or an enum',
    );
  }

  final valueType = unwrapped.typeArguments[1];
  if (valueType.nullabilitySuffix != NullabilitySuffix.none) {
    return const MapExcluded(
      'a nullable map value is unsupported because an absent entry and an '
      'authored null cannot be told apart',
    );
  }

  final nestedClassification = classifyMapType(
    valueType,
    structuredValuesAdmitted: structuredValuesAdmitted,
    library: library,
    policy: policy,
  );
  switch (nestedClassification) {
    case MapExcluded():
      return nestedClassification;
    case MapAdmitted():
      return MapAdmitted(
        keyKind: keyKind,
        keyEnumRef: keyEnumRef,
        valueShape: ScalarShape.opaqueStringKeyedMap(),
        valueType: valueType,
        nestedValue: nestedClassification,
      );
    case NotAMap():
      break;
  }

  // The resolver's structured arm is a framework recipe whitelist; customer
  // data classes are recognised through the walk policy instead.
  //
  // The customer-authored check below is load-bearing, and it is deliberately
  // the FULL predicate rather than a library-origin test. Two things to know
  // before simplifying it:
  //
  //  1. With no check at all, the policy reports framework recipe types as
  //     concrete too, so a map of Duration / Color / Offset / EdgeInsets /
  //     Alignment — every one of which is admitted today as an ordinary
  //     scalar value — would be captured by this branch and then excluded as
  //     an unresolvable structured target. That regression is real and
  //     measured; a test pins those shapes as still admitted.
  //  2. A library-origin subset of this predicate is behaviourally IDENTICAL
  //     on every shape we were able to construct, because the remaining
  //     conditions are already implied by `classifyStructured(...) ==
  //     concrete`: the discovery pass seeds the policy using those same
  //     conditions. Measuring the two against each other therefore returns
  //     nothing, and NO TEST CAN PIN WHICH OF THEM IS IN PLACE.
  //
  // The full predicate is used anyway, and the reason is written here because
  // it is the only place it can be recorded: it is the single definition of
  // "customer-authored" this codebase has, shared in intent with the discovery
  // pass and kept in step by an agreement test. A subset would be a second,
  // weaker notion of the same concept with nothing pinning the difference. The
  // conditions that look redundant are anticipatory — they still hold the line
  // if the policy seeding ever loosens. Do not reduce this to a prefix check
  // on the grounds that the two measure the same; that is expected, and it is
  // not evidence that the difference is dead weight.
  final valueIsCustomerStructured = _isCustomerAuthoredClass(valueType) &&
      policy != null &&
      library != null &&
      classifyStructured(valueType, policy) == StructuredKind.concrete;
  if (valueIsCustomerStructured) {
    if (!structuredValuesAdmitted) {
      return _mapOfDataClassNotOnFieldExcluded;
    }
    return MapAdmitted(
      keyKind: keyKind,
      keyEnumRef: keyEnumRef,
      valueShape: StructuredShape(
        propertyType: PropertyType.structured,
        structuredRef: WireIdRef(
          library: library.namespace,
          wireId: WireId.unallocatedStructured,
        ),
      ),
      valueType: valueType,
    );
  }

  // A record value is outside the admitted vocabulary, and it must be rejected
  // BEFORE the shared resolver runs: an admitted record resolves to an opaque
  // scalar shape, which would satisfy the scalar check below and be admitted
  // as though it were an ordinary scalar value.
  if (classifyRecordType(valueType, library: library, policy: policy)
      is! NotARecord) {
    return MapExcluded(
      'a map value of type ${valueType.getDisplayString()} is a record; '
      'a map value must be a scalar, an enum, a nested map, or a customer '
      'data class',
    );
  }

  final valueShape = resolveValueShape(
    valueType,
    library: library,
    policy: policy,
  );

  // The explicit null check is load-bearing for flow analysis as well as for
  // the boundary: Dart cannot promote a variable to the UNION of two negated
  // type tests, so `valueShape` stays nullable past the guard without it.
  if (valueShape == null ||
      (valueShape is! ScalarShape && valueShape is! EnumShape)) {
    if (!structuredValuesAdmitted && _isCustomerAuthoredClass(valueType)) {
      return _mapOfDataClassNotOnFieldExcluded;
    }
    return MapExcluded(
      'map value type ${valueType.getDisplayString()} is unsupported; '
      'use a scalar, enum, map, or customer data class',
    );
  }

  return MapAdmitted(
    keyKind: keyKind,
    keyEnumRef: keyEnumRef,
    valueShape: valueShape,
    valueType: valueType,
  );
}

/// Whether [type] is the `dart:core` class called [name].
///
/// Checked by element identity rather than by an analyzer convenience getter so
/// the predicate states the library it means: a project class merely *named*
/// `String` is not the core one. The map type has its own shared spelling of
/// this rule in `dartCoreMapType`, which this file uses for `Map`.
bool _isDartCoreClass(InterfaceType type, String name) =>
    type.element.name == name && type.element.library.identifier == 'dart:core';

/// Whether [type] is a class the customer could author as a data class —
/// decided from the type itself, with no reference to what the walk happens to
/// have collected.
///
/// Used only to choose a diagnostic. Closure membership cannot answer this: it
/// records what was walked, not what a type IS, so asking it makes the message
/// depend on whether unrelated code mentions the same class.
///
/// The conditions mirror the ones the discovery pass applies when it decides
/// what to collect. They are restated here rather than shared because the
/// dependency runs the other way — this package cannot see that one.
bool _isCustomerAuthoredClass(DartType type) {
  final unwrapped = unwrapTypeAliases(type);
  if (unwrapped is! InterfaceType) return false;
  final element = unwrapped.element;
  if (element is! ClassElement || element.isAbstract) return false;
  final libraryId = element.library.identifier;
  if (libraryId.startsWith('dart:') ||
      libraryId.startsWith('package:flutter/')) {
    return false;
  }
  return element.constructors.any(
    (constructor) =>
        !constructor.isFactory && constructor.formalParameters.isNotEmpty,
  );
}
