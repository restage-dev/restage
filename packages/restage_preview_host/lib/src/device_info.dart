import 'package:device_preview/presets.dart'
    show DeviceKind, DevicePreset, DevicePresets;
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/widgets.dart' show Size;

/// A presentation device with a stable identifier and curated display label.
@immutable
class DeviceInfo {
  const DeviceInfo._(
      {required this.id, required this.backing, required this.label});

  /// Canonical name used for serialization and value equality.
  final String id;

  /// Logical metrics, safe areas, and bezel artwork for this device.
  final DevicePreset backing;

  /// Curated display label for device pickers.
  final String label;

  /// Whether the backing device is a tablet.
  bool get isTablet => backing.kind == DeviceKind.tablet;

  /// The logical screen size in portrait.
  Size get screenSize => backing.portraitSize;

  /// The portrait device-body size, or the bare screen when artwork is absent.
  Size get frameSize => backing.frame?.size ?? backing.portraitSize;

  /// iPhone SE — the small-viewport stress test.
  static const DeviceInfo iPhoneSE = DeviceInfo._(
    id: 'iPhoneSE',
    backing: DevicePresets.iPhoneSe3,
    label: 'iPhone SE',
  );

  /// iPhone 16 Pro Max — the default presentation device.
  static const DeviceInfo iPhone16ProMax = DeviceInfo._(
    id: 'iPhone16ProMax',
    backing: DevicePresets.iPhone16ProMax,
    label: 'iPhone 16 Pro Max',
  );

  /// Pixel 9. Its identifier is retained for stored preference compatibility.
  static const DeviceInfo googlePixel9ProXL = DeviceInfo._(
    id: 'googlePixel9ProXL',
    backing: DevicePresets.pixel9,
    label: 'Pixel 9',
  );

  /// iPad Pro 11-inch (M4).
  static const DeviceInfo iPadPro11 = DeviceInfo._(
    id: 'iPadPro11InchesM4',
    backing: DevicePresets.iPadPro11M4,
    label: 'iPad Pro 11"',
  );

  /// Available devices in picker display order.
  static final List<DeviceInfo> values = List.unmodifiable([
    iPhoneSE,
    iPhone16ProMax,
    googlePixel9ProXL,
    iPadPro11,
  ]);

  /// Finds a catalog device by its stable identifier.
  static DeviceInfo? byId(String id) {
    for (final device in values) {
      if (device.id == id) return device;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is DeviceInfo && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
