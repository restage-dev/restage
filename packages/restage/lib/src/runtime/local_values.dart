import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show kLocalValueSetEventName;
import 'package:restage_shared/restage_shared.dart' show DeliveredIconFont;
import 'package:rfw/rfw.dart' show DynamicContent;

/// The reserved event a value callback sends to write a screen-local value.
const String kLocalSetEventName = kLocalValueSetEventName;

/// The data key screen-local values are published under.
const String kLocalDataKey = 'local';

/// The longest string a screen-local value may hold, in UTF-16 code units.
const int kMaxLocalStringLength = 4096;

final RegExp _localKey = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$');

/// The payload sections a mounted surface reads: delivered icon fonts and
/// initial screen-local values keyed by root widget or screen id.
@internal
@immutable
final class SurfaceSections {
  /// Creates the sections carried by one delivered surface.
  const SurfaceSections({
    this.iconFonts = const <DeliveredIconFont>[],
    this.localSeeds = const <String, Map<String, Object>>{},
  });

  /// A surface that carries no sections.
  static const SurfaceSections none = SurfaceSections();

  /// The subset icon fonts delivered with the surface.
  final List<DeliveredIconFont> iconFonts;

  /// Initial values keyed by root widget or screen id, then by value key.
  final Map<String, Map<String, Object>> localSeeds;
}

/// Tells the host above a flow view that a screen-local value was written.
@internal
class LocalWriteListener extends InheritedWidget {
  /// Calls [onWrite] for each accepted or dropped local write below.
  const LocalWriteListener({
    required this.onWrite,
    required super.child,
    super.key,
  });

  /// Called on each local write.
  final VoidCallback onWrite;

  /// Notifies the nearest listener above [context], if any.
  static void notify(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LocalWriteListener>()?.onWrite();

  @override
  bool updateShouldNotify(LocalWriteListener oldWidget) => false;
}

/// The screen-local values of one mounted surface or flow screen, published to
/// its content as `data.local`.
@internal
final class LocalValues {
  /// Publishes [seed] into [data] before the first build.
  LocalValues(this._data, {Map<String, Object>? seed}) {
    if (seed != null) {
      for (final MapEntry(:key, :value) in seed.entries) {
        if (_admissible(key, value)) _values[key] = value;
      }
    }
    _publish();
  }

  final DynamicContent _data;
  final Map<String, Object> _values = <String, Object>{};
  var _cleared = false;

  /// The values held now.
  Map<String, Object> get values => Map<String, Object>.unmodifiable(_values);

  /// Consumes [name] when it is the reserved write event, applying a valid
  /// write and dropping an invalid one. Returns false for any other event.
  bool intercept(String name, Object? args) {
    if (name != kLocalSetEventName) return false;
    if (_cleared || args is! Map) return true;
    final key = args['key'];
    final Object? value = args['value'];
    if (key is! String || !_admissible(key, value)) return true;
    _values[key] = value!;
    _publish();
    return true;
  }

  /// Drops every value; later writes are ignored.
  void clear() {
    _cleared = true;
    _values.clear();
  }

  void _publish() =>
      _data.update(kLocalDataKey, Map<String, Object>.of(_values));

  static bool _admissible(String key, Object? value) {
    if (!_localKey.hasMatch(key)) return false;
    return switch (value) {
      final String text => text.length <= kMaxLocalStringLength,
      final double number => number.isFinite,
      int() || bool() => true,
      _ => false,
    };
  }
}
