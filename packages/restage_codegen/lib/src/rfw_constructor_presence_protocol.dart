import 'package:restage_codegen/src/dart_import_planner.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Translator-side encoder for Restage's versioned RFW constructor-presence
/// calling convention.
abstract final class RfwConstructorPresenceEncoder {
  /// Whether [property] needs an envelope to preserve Dart's omission boundary.
  ///
  /// Every optional property with a constructor default participates, whatever
  /// its nullability or the default's value. An absent outer property omits the
  /// Dart argument so the ordinary default applies. Any supplied expression,
  /// including one that evaluates missing or null, must remain supplied rather
  /// than being silently reinterpreted as absence. Supplying null is therefore
  /// retained for nullable inputs and fails loudly at ordinary Dart invocation
  /// for non-nullable inputs.
  static bool appliesTo(PropertyEntry property) =>
      !property.required && property.constructorDefault != null;

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

  /// Applies the protocol only when [property] has the omission boundary above.
  static String encode(PropertyEntry property, String valueExpression) =>
      appliesTo(property) ? supplied(valueExpression) : valueExpression;
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
      if (!RfwConstructorPresenceEncoder.appliesTo(property)) continue;

      final suffix = _upperCamel(property.name);
      var localName = '_restagePresence$suffix';
      if (!usedLocalNames.add(localName)) {
        localName = '_restagePresence${ordinal}_$suffix';
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
    final pathSegment = renderDartStringLiteral(property.name);
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
