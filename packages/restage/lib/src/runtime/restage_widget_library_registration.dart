import 'dart:collection' show UnmodifiableListView;

import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart' show WidgetLibrary;

import 'restage_widget_factory.dart';

/// Immutable snapshot of one custom widget-library registration.
@immutable
final class RestageWidgetLibraryRegistration {
  RestageWidgetLibraryRegistration({
    required this.library,
    required Iterable<RestageWidgetFactory> widgets,
    this.capabilityVersion,
  }) : _widgets = List<RestageWidgetFactory>.unmodifiable(widgets) {
    if (capabilityVersion != null && capabilityVersion! < 1) {
      throw ArgumentError.value(
        capabilityVersion,
        'capabilityVersion',
        'must be positive when provided',
      );
    }
  }

  /// A constant registration, as generated surface code declares one.
  ///
  /// [widgets] is read back through an unmodifiable view.
  const RestageWidgetLibraryRegistration.constant({
    required this.library,
    required List<RestageWidgetFactory> widgets,
    this.capabilityVersion,
  })  : _widgets = widgets,
        assert(
          capabilityVersion == null || capabilityVersion >= 1,
          'capabilityVersion must be positive when provided',
        );

  final WidgetLibrary library;
  final List<RestageWidgetFactory> _widgets;
  final int? capabilityVersion;

  /// The library's widget factories, unmodifiable.
  List<RestageWidgetFactory> get widgets =>
      UnmodifiableListView<RestageWidgetFactory>(_widgets);
}
