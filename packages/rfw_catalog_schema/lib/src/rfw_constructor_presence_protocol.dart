import 'package:rfw_catalog_schema/src/property_entry.dart';

/// Reserved internal RFW calling convention for constructor argument presence.
abstract final class RfwConstructorPresenceProtocol {
  /// Whether [property] needs an envelope to preserve constructor omission.
  static bool appliesTo(PropertyEntry property) =>
      !property.required && property.constructorDefault != null;

  /// Protocol version carried under [markerKey].
  static const int version = 1;

  /// Reserved marker identifying a Restage constructor-presence envelope.
  static const String markerKey = r'$restage.constructor.presence';

  /// Nested supplied value. Its absence represents a supplied null.
  static const String valueKey = r'$restage.constructor.value';
}
