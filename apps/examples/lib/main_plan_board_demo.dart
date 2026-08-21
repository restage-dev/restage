import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';

import 'onboarding/flows/plan_board_showcase.dart';

/// On-device demo for the `plan_board_showcase` screen — two **map properties
/// rendered natively from the delivered blob**.
///
/// The screen (`lib/onboarding/screens/plan_board_showcase.dart`) authors a
/// `PlanBoard` in ordinary Flutter, with one string-keyed map of plans and one
/// enum-keyed map of highlights. The build-time codegen encodes each map into
/// `assets/onboarding/screens/plan_board_showcase.rfw` as an ordered list of
/// `key`/`value` entry objects. This entrypoint renders that bundled blob
/// through the SDK — the generated factory reconstructs both maps, keyed and in
/// the authored order, and paints the board as real Flutter widgets. Run it on
/// a real device to confirm the native render fidelity a web smoke cannot see
/// (status bar, theming, real pixels):
///
///   flutter run -t lib/main_plan_board_demo.dart --no-tree-shake-icons
///
/// This closes the chain end to end for map-shaped properties:
/// source → encode → wire → decode → pixels.
///
/// **Do not copy this file's hosting code.** It drives the flow controller and
/// the screen view directly, which is incidental to what is being demonstrated
/// here, not an example of how to host a flow. Map reconstruction does not
/// depend on the host at all — the generated factory is the decoder — so the
/// low-level route proves the same thing while skipping what a real app gets
/// from the wrapper. For the idiomatic host, see
/// `lib/onboarding/minimal_notice_demo.dart`, which renders a structurally
/// identical single-screen flow through `RestageFlowGraph`.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Register the example's custom widgets (incl. PlanBoard) so the delivered
  // blob's `PlanBoard(plans: ..., highlights: ...)` reference resolves to its
  // generated factory.
  registerRestageCustomerWidgets();
  Restage.configure(
    apiKey: 'rs_pk_test',
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
