import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:meta/meta.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The complete RFW callback payload/signature contract.
///
/// Analyzer-side customer admission and factory-side catalog consumption must
/// both pass through this abstraction. [fromResolvedCustomerPayload] adds the
/// source-identity proof required while inspecting customer Dart, then
/// delegates to [parse], the single serialized-signature grammar used by the
/// factory.
@immutable
final class RfwCallbackSignature {
  const RfwCallbackSignature._({
    required this.source,
    required this.valueType,
  });

  /// Parses a mechanically supported serialized callback [source].
  ///
  /// The payload is either one scalar identifier (optionally nullable), or one
  /// non-null `List` of scalar identifiers (whose elements may be nullable).
  /// Nested lists and outer-nullable lists are intentionally outside the
  /// currently emitted RFW vocabulary.
  static RfwCallbackSignature? parse(String source) {
    final valueType = parseRfwCallbackValueType(source);
    return valueType == null
        ? null
        : RfwCallbackSignature._(source: source, valueType: valueType);
  }

  /// Creates the canonical signature for one resolved customer [payload].
  ///
  /// Customer payloads are limited to RFW-safe `dart:core` scalars. Factory
  /// parsing remains name-based so existing built-in catalog signatures such
  /// as `ValueChanged<DateTime>` retain their current lowering.
  static RfwCallbackSignature? fromResolvedCustomerPayload(DartType payload) {
    final valueType = _resolvedCustomerValueType(payload);
    return valueType == null ? null : parse('ValueChanged<$valueType>');
  }

  /// Canonical `ValueChanged<T>` source stored in the catalog.
  final String source;

  /// The complete `T` source used by the generated handler closure.
  final String valueType;
}

const Set<String> _customerScalarNames = {
  'String',
  'bool',
  'int',
  'double',
  'num',
};

String? _resolvedCustomerValueType(DartType type) {
  final scalar = _resolvedCustomerScalar(type);
  if (scalar != null) return scalar;
  if (type is! InterfaceType ||
      type.element.library.identifier != 'dart:core' ||
      type.element.name != 'List' ||
      type.nullabilitySuffix == NullabilitySuffix.question ||
      type.typeArguments.length != 1) {
    return null;
  }
  final item = _resolvedCustomerScalar(type.typeArguments.single);
  return item == null ? null : 'List<$item>';
}

String? _resolvedCustomerScalar(DartType type) {
  if (type is! InterfaceType ||
      type.element.library.identifier != 'dart:core' ||
      type.typeArguments.isNotEmpty) {
    return null;
  }
  final name = type.element.name;
  if (name == null || !_customerScalarNames.contains(name)) return null;
  final nullable = type.nullabilitySuffix == NullabilitySuffix.question;
  return '$name${nullable ? '?' : ''}';
}
