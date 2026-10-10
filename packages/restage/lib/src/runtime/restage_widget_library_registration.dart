import 'dart:collection' show UnmodifiableListView;

import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart'
    show InstalledLibrary, WidgetLibrary;

import 'restage_widget_factory.dart';

/// Immutable snapshot of one custom widget-library registration.
@immutable
final class RestageWidgetLibraryRegistration {
  RestageWidgetLibraryRegistration({
    required this.library,
    required Iterable<RestageWidgetFactory> widgets,
    this.capabilityVersion,
    this.compatibleSince,
  }) : _widgets = List<RestageWidgetFactory>.unmodifiable(widgets) {
    if (capabilityVersion != null && capabilityVersion! < 1) {
      throw ArgumentError.value(
        capabilityVersion,
        'capabilityVersion',
        'must be positive when provided',
      );
    }
    if (compatibleSince != null &&
        !InstalledLibrary.isValidCompatibleSince(
          compatibleSince,
          capabilityVersion,
        )) {
      throw ArgumentError.value(
        compatibleSince,
        'compatibleSince',
        'must be between 1 and capabilityVersion',
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
    this.compatibleSince,
  })  : _widgets = widgets,
        assert(
          capabilityVersion == null || capabilityVersion >= 1,
          'capabilityVersion must be positive when provided',
        ),
        assert(
          compatibleSince == null ||
              (capabilityVersion != null &&
                  compatibleSince >= 1 &&
                  compatibleSince <= capabilityVersion),
          'compatibleSince must be between 1 and capabilityVersion',
        );

  final WidgetLibrary library;
  final List<RestageWidgetFactory> _widgets;
  final int? capabilityVersion;

  /// The oldest capability version whose content this library still renders,
  /// or `null` for 1.
  final int? compatibleSince;

  /// The library's widget factories, unmodifiable.
  List<RestageWidgetFactory> get widgets =>
      UnmodifiableListView<RestageWidgetFactory>(_widgets);
}
