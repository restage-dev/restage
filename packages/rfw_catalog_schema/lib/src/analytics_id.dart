import 'package:rfw_catalog_schema/src/property_entry.dart';
import 'package:rfw_catalog_schema/src/property_type.dart';
import 'package:rfw_catalog_schema/src/wire_id.dart';

/// The reserved catalog property used to name an authored widget occurrence.
const String kAnalyticsIdPropertyName = 'analyticsId';

/// The synthetic strategy that keeps [kAnalyticsIdPropertyName] out of native
/// Flutter constructor calls.
const String kAnalyticsIdSyntheticStrategy = 'analyticsId';

/// The largest accepted analytics identifier length.
const int kAnalyticsIdMaximumLength = 128;

final RegExp _analyticsIdPattern = RegExp(r'^[a-z0-9][a-z0-9._:-]*$');

/// Whether [value] is a valid analytics identifier.
///
/// The grammar intentionally matches the measurement identifier contract:
/// lowercase ASCII, a leading alphanumeric character, and at most
/// [kAnalyticsIdMaximumLength] characters.
bool isValidAnalyticsId(String value) =>
    value.length <= kAnalyticsIdMaximumLength &&
    _analyticsIdPattern.hasMatch(value);

/// Creates the optional synthetic property available on catalog widgets.
///
/// The allocator replaces the default wire ID when a catalog is built.
PropertyEntry analyticsIdProperty({
  WireId wireId = WireId.unallocatedProperty,
}) =>
    PropertyEntry(
      wireId: wireId,
      name: kAnalyticsIdPropertyName,
      type: PropertyType.string,
      description: 'Optional identifier for this widget occurrence.',
      synthetic: kAnalyticsIdSyntheticStrategy,
    );
