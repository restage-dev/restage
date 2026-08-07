import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart' show WidgetLibrary;

import 'restage_widget_factory.dart';

/// Immutable snapshot of one customer widget-library registration.
@immutable
final class RestageWidgetLibraryRegistration {
  RestageWidgetLibraryRegistration({
    required this.library,
    required Iterable<RestageWidgetFactory> widgets,
    this.capabilityVersion,
  }) : widgets = List<RestageWidgetFactory>.unmodifiable(widgets) {
    if (capabilityVersion != null && capabilityVersion! < 1) {
      throw ArgumentError.value(
        capabilityVersion,
        'capabilityVersion',
        'must be positive when provided',
      );
    }
  }

  final WidgetLibrary library;
  final List<RestageWidgetFactory> widgets;
  final int? capabilityVersion;
}
