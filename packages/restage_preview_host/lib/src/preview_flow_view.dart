import 'package:flutter/material.dart' show Theme, ThemeData;
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

import 'android_back_gesture_area.dart';

/// The dashboard's flow presentation, shared with embedded previews.
///
/// An inner navigator gives the SDK view a route of its own to claim for back.
/// Its overlays and transitions stay inside the simulated device, rather than
/// using the surrounding dashboard dialog or the embedding app's route.
class PreviewFlowView<R> extends StatefulWidget {
  /// Displays [controller] inside a route isolated from the surrounding app.
  const PreviewFlowView({
    required this.controller,
    required this.brightness,
    required this.loadingBuilder,
    this.onScreenEvent,
    super.key,
  });

  final RestageFlowController<R> controller;
  final Brightness brightness;
  final WidgetBuilder loadingBuilder;
  final bool Function(String name, Map<String, Object?> arguments)?
      onScreenEvent;

  @override
  State<PreviewFlowView<R>> createState() => _PreviewFlowViewState<R>();
}

class _PreviewFlowViewState<R> extends State<PreviewFlowView<R>> {
  GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  @override
  void didUpdateWidget(PreviewFlowView<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _navigator = GlobalKey<NavigatorState>();
    }
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final navigator = Navigator(
      key: _navigator,
      onGenerateRoute: (settings) => PageRouteBuilder<void>(
        settings: settings,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => RestageFlowView<R>(
          controller: widget.controller,
          loadingBuilder: widget.loadingBuilder,
          onScreenEvent: widget.onScreenEvent,
        ),
      ),
    );
    return Theme(
      data: ThemeData(brightness: widget.brightness, useMaterial3: true)
          .copyWith(platform: platform),
      child: platform == TargetPlatform.android
          ? AndroidBackGestureArea(navigator: _navigator, child: navigator)
          : navigator,
    );
  }
}
