import 'package:restage_shared/restage_shared.dart'
    show kReservedPreviewConstructorName, kReservedPreviewLibraryName;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart' show WidgetEntry;

/// Rejects customer widgets that claim preview-only runtime symbols.
void validateCustomerPreviewReservations(Iterable<WidgetEntry> widgets) {
  for (final widget in widgets) {
    if (widget.library.namespace == kReservedPreviewLibraryName) {
      throw ArgumentError.value(
        widget.library.namespace,
        'widgets',
        'the library namespace is reserved for internal preview rendering',
      );
    }
    if (widget.name == kReservedPreviewConstructorName) {
      throw ArgumentError.value(
        widget.name,
        'widgets',
        'the constructor name is reserved for internal preview rendering',
      );
    }
  }
}
