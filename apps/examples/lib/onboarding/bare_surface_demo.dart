import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'flows/bare_surface.dart';

/// Gallery host for the bare surface starter.
///
/// This uses the low-level controller plus current-screen renderer directly.
/// The rendered surface is just the delivered screen; route escape and theme
/// controls are supplied by the gallery around it.
class BareSurfaceDemo extends StatefulWidget {
  /// Creates the bare surface gallery host.
  const BareSurfaceDemo({super.key});

  @override
  State<BareSurfaceDemo> createState() => _BareSurfaceDemoState();
}

class _BareSurfaceDemoState extends State<BareSurfaceDemo> {
  RestageFlowController<BareSurfaceResult>? _controller;
  FlowUnavailableError? _unavailable;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    late final RestageFlowController<BareSurfaceResult> controller;
    controller = RestageFlowController<BareSurfaceResult>(
      flow: BareSurfaceFlowDescriptor.ref,
      resolver: Restage.defaultFlowResolver,
      actions: null,
      onEvent: Restage.fireEvent,
      onComplete: (_) {},
      onUnavailable: (error) {
        if (!mounted || !identical(_controller, controller)) return;
        setState(() => _unavailable = error);
      },
    );
    _controller = controller;
    unawaited(controller.load());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _unavailable;
    if (error != null) {
      return const Scaffold(
        body: Center(child: Text('Surface is unavailable right now.')),
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }
    // ignore: experimental_member_use
    return RestageScreenView<BareSurfaceResult>(
      controller: controller,
      loadingBuilder: (context) => const SizedBox.shrink(),
    );
  }
}
