import 'package:device_preview/device_preview.dart' as dp;
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';

import 'device_info.dart';

/// Renders [child] inside the device chrome described by [device].
///
/// The child receives the device's logical size, safe areas, pixel ratio, and
/// platform. The complete frame scales to fit its incoming constraints.
class DeviceFrameHost extends StatefulWidget {
  /// Creates a framed presentation of [child].
  const DeviceFrameHost({required this.device, required this.child, super.key});

  /// Device whose screen and chrome are presented.
  final DeviceInfo device;

  /// Content laid out inside the logical device screen.
  final Widget child;

  @override
  State<DeviceFrameHost> createState() => _DeviceFrameHostState();
}

class _DeviceFrameHostState extends State<DeviceFrameHost> {
  final _simulation = ValueNotifier<dp.DeviceSimulation?>(null);

  @override
  void didUpdateWidget(DeviceFrameHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device != widget.device) _simulation.value = _resolve();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _simulation.value = _resolve();
  }

  @override
  void dispose() {
    _simulation.dispose();
    super.dispose();
  }

  dp.DeviceSimulation _resolve() => widget.device.backing.resolve().copyWith(
        platformBrightness: MediaQuery.maybePlatformBrightnessOf(context),
      );

  @override
  Widget build(BuildContext context) {
    final metrics = DeviceFrameMetrics.of(widget.device);
    final simulation = _simulation.value!;
    final ambient = MediaQuery.maybeOf(context) ?? const MediaQueryData();
    final screen = MediaQuery(
      data: ambient.copyWith(
        size: metrics.screenRect.size,
        padding: simulation.padding,
        viewPadding: simulation.viewPadding,
        viewInsets: EdgeInsets.zero,
        devicePixelRatio: simulation.devicePixelRatio,
      ),
      child: Theme(
        data: Theme.of(context)
            .copyWith(platform: widget.device.backing.platform),
        child: widget.child,
      ),
    );
    return FittedBox(
      child: SizedBox.fromSize(
        size: metrics.frameSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(
              rect: metrics.screenRect,
              child: dp.DevicePreviewFrame(
                simulation: _simulation,
                child: screen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Maps logical screen coordinates into a device frame box.
@immutable
class DeviceFrameMetrics {
  /// Creates explicit frame metrics. Prefer [DeviceFrameMetrics.of].
  const DeviceFrameMetrics({
    required this.frameSize,
    required this.screenRect,
    required this.scale,
  });

  /// Derives portrait frame geometry for [device].
  factory DeviceFrameMetrics.of(DeviceInfo device) {
    final frame = device.backing.frame;
    final screen = device.screenSize;
    if (frame == null || frame.size.isEmpty) {
      return DeviceFrameMetrics(
        frameSize: screen,
        screenRect: Offset.zero & screen,
        scale: 1,
      );
    }
    return DeviceFrameMetrics(
      frameSize: frame.size,
      screenRect: frame.screenOffset & screen,
      scale: 1,
    );
  }

  /// Size of the whole device frame, bezel included.
  final Size frameSize;

  /// Logical screen bounds within [frameSize].
  final Rect screenRect;

  /// Logical screen point to frame pixel scale.
  final double scale;

  /// Lifts a logical screen rectangle into frame coordinates.
  Rect toFrame(Rect rect) => Rect.fromLTWH(
        screenRect.left + rect.left * scale,
        screenRect.top + rect.top * scale,
        rect.width * scale,
        rect.height * scale,
      );

  /// Converts a frame coordinate to logical screen coordinates.
  Offset toLogical(Offset point) => Offset(
        (point.dx - screenRect.left) / scale,
        (point.dy - screenRect.top) / scale,
      );

  @override
  bool operator ==(Object other) =>
      other is DeviceFrameMetrics &&
      other.frameSize == frameSize &&
      other.screenRect == screenRect &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(frameSize, screenRect, scale);
}

/// Provides a scale-to-fit frame coordinate space to [builder].
class DeviceFrameStage extends StatelessWidget {
  /// Creates a presentation stage for [device].
  const DeviceFrameStage(
      {required this.device, required this.builder, super.key});

  /// Device whose frame defines the stage coordinate space.
  final DeviceInfo device;

  /// Builds content in frame coordinates.
  final Widget Function(BuildContext context, DeviceFrameMetrics metrics)
      builder;

  @override
  Widget build(BuildContext context) {
    final metrics = DeviceFrameMetrics.of(device);
    return FittedBox(
      child: SizedBox.fromSize(
        size: metrics.frameSize,
        child: builder(context, metrics),
      ),
    );
  }
}
