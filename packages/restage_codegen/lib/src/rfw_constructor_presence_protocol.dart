import 'package:restage_codegen/src/emit_utils.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Translator-side encoder for Restage's versioned RFW constructor-presence
/// calling convention.
abstract final class RfwConstructorPresenceEncoder {
  /// Encodes one author-supplied RFW expression.
  ///
  /// A literal null intentionally has no nested value. All other expressions
  /// retain a nested value entry; if such an expression evaluates missing at
  /// runtime, the decoder still observes the outer envelope and supplies null.
  static String supplied(String valueExpression) {
    const marker = RfwConstructorPresenceProtocol.markerKey;
    const version = RfwConstructorPresenceProtocol.version;
    if (valueExpression == 'null') {
      return "{ '$marker': $version }";
    }
    const value = RfwConstructorPresenceProtocol.valueKey;
    return "{ '$marker': $version, '$value': $valueExpression }";
  }

  /// Applies the protocol to optional properties with a constructor default.
  static String encode(PropertyEntry property, String valueExpression) =>
      RfwConstructorPresenceProtocol.appliesTo(property)
          ? supplied(valueExpression)
          : valueExpression;
}

/// Factory-emitter view of one constructor-presence read.
///
/// This is the only generator abstraction that spells the generated decoder
/// call, local name, or nested-value path.
final class RfwConstructorPresenceFactoryPlan {
  RfwConstructorPresenceFactoryPlan._(this.property, this.localName);

  /// Plans every presence read as one deterministic, collision-safe scope.
  ///
  /// Existing readable names remain byte-stable until two property names map
  /// to the same local. A later collision uses its stable presence ordinal
  /// before the readable suffix. Legal Dart parameter names cannot begin with
  /// that ordinal, so the allocated form cannot collide with an unsuffixed
  /// property-derived local.
  static Map<String, RfwConstructorPresenceFactoryPlan> forProperties(
    Iterable<PropertyEntry> properties,
  ) {
    final plans = <String, RfwConstructorPresenceFactoryPlan>{};
    final usedLocalNames = <String>{};
    var ordinal = 0;

    for (final property in properties) {
      if (!RfwConstructorPresenceProtocol.appliesTo(property)) continue;

      final suffix = _upperCamel(property.name);
      var localName = 'restagePresence$suffix';
      if (!usedLocalNames.add(localName)) {
        localName = 'restagePresence$ordinal$suffix';
        if (!usedLocalNames.add(localName)) {
          throw StateError(
            'Could not allocate a unique RFW constructor-presence local for '
            '${property.name}.',
          );
        }
      }
      if (plans.containsKey(property.name)) {
        throw StateError(
          'RFW constructor property names must be unique: ${property.name}.',
        );
      }
      plans[property.name] =
          RfwConstructorPresenceFactoryPlan._(property, localName);
      ordinal += 1;
    }

    return Map.unmodifiable(plans);
  }

  /// Catalog property represented by this plan.
  final PropertyEntry property;

  /// Stable generated local holding the decoded presence.
  final String localName;

  /// Generated declaration for the centralized SDK decoder.
  String get declaration {
    final pathSegment = dartStringLiteral(property.name);
    return '  final $localName = RestageRfwConstructorPresence.read(\n'
        '    source,\n'
        '    <Object>[$pathSegment],\n'
        '  );';
  }

  /// Expression that is true when Dart must receive this argument.
  String get suppliedExpression => '$localName.supplied';

  /// Path from which the ordinary property decoder reads the supplied value.
  String get valuePathExpression => '$localName.valuePath';
}

String _upperCamel(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
