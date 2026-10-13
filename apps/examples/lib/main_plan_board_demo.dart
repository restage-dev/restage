import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';

import 'onboarding/flows/plan_board_showcase.dart';

/// Renders bundled RFW to exercise map decoding in a custom widget factory.
/// For ordinary flow hosting, see MinimalNoticeFlowSurface in minimal_notice_demo.dart.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Register the example's custom widgets, including PlanBoard, so the
  // delivered surface's `PlanBoard(...)` renders through its generated factory.
  registerRestageWidgets();
  Restage.configure(
    resolver: const AssetVariantResolver(),
  );
  runApp(const _PlanBoardDemoApp());
}

class _PlanBoardDemoApp extends StatelessWidget {
  const _PlanBoardDemoApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plan board demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6366F1),
        useMaterial3: true,
      ),
      home: const PlanBoardDemo(),
    );
  }
}

/// Hosts the plan board showcase flow.
class PlanBoardDemo extends StatefulWidget {
  /// Creates the plan board showcase host.
  const PlanBoardDemo({super.key});

  @override
  State<PlanBoardDemo> createState() => _PlanBoardDemoState();
}

class _PlanBoardDemoState extends State<PlanBoardDemo> {
  RestageFlowController<PlanBoardShowcaseResult>? _controller;
  FlowUnavailableError? _unavailable;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    late final RestageFlowController<PlanBoardShowcaseResult> controller;
    controller = RestageFlowController<PlanBoardShowcaseResult>(
      flow: planBoardShowcaseFlowRef,
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
    if (_unavailable != null) {
      return const Scaffold(
        body: Center(child: Text('This screen is unavailable right now.')),
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }
    // ignore: experimental_member_use
    return RestageScreenView<PlanBoardShowcaseResult>(
      controller: controller,
      loadingBuilder: (context) =>
          const Center(child: CircularProgressIndicator()),
    );
  }
}
