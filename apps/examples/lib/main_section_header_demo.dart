import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';

import 'onboarding/flows/section_header_showcase.dart';

/// On-device demo for the `section_header_showcase` screen — two **record
/// properties rendered natively from the delivered blob**.
///
/// The screen (`lib/onboarding/screens/section_header_showcase.dart`) authors
/// a `SectionHeader` in ordinary Flutter. The build-time codegen encodes its
/// heading record and nested entry metadata record into
/// `assets/onboarding/screens/section_header_showcase.rfw` as
/// field-name-keyed maps. This entrypoint renders that bundled blob through
/// the SDK — the generated factory reconstructs both records and paints the
/// header as real Flutter widgets. Run it on a real device to confirm the
/// native render fidelity a web smoke cannot see (status bar, theming, real
/// pixels):
///
///   flutter run -t lib/main_section_header_demo.dart --no-tree-shake-icons
///
/// This closes the chain end to end for record-shaped properties:
/// source → encode → wire → decode → pixels.
///
/// **Do not copy this file's hosting code.** It drives the flow controller and
/// the screen view directly, which is incidental to what is being demonstrated
/// here, not an example of how to host a flow. Record reconstruction does not
/// depend on the host at all — the generated factory is the decoder — so the
/// low-level route proves the same thing while skipping what a real app gets
/// from the wrapper. For the idiomatic host, see
/// `lib/onboarding/minimal_notice_demo.dart`, which renders a
/// structurally identical single-screen flow through `RestageFlowGraph`.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Register the example's custom widgets (incl. SectionHeader) so the
  // delivered blob's `SectionHeader(heading: ..., entry: ...)` reference
  // resolves to its generated factory.
  registerRestageCustomerWidgets();
  Restage.configure(
    apiKey: 'rs_pk_test',
    resolver: const AssetVariantResolver(),
  );
  runApp(const _SectionHeaderDemoApp());
}

class _SectionHeaderDemoApp extends StatelessWidget {
  const _SectionHeaderDemoApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Section header demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6366F1),
        useMaterial3: true,
      ),
      home: const SectionHeaderDemo(),
    );
  }
}

/// Hosts the section header showcase flow.
class SectionHeaderDemo extends StatefulWidget {
  /// Creates the section header showcase host.
  const SectionHeaderDemo({super.key});

  @override
  State<SectionHeaderDemo> createState() => _SectionHeaderDemoState();
}

class _SectionHeaderDemoState extends State<SectionHeaderDemo> {
  RestageFlowController<SectionHeaderShowcaseResult>? _controller;
  FlowUnavailableError? _unavailable;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    late final RestageFlowController<SectionHeaderShowcaseResult> controller;
    controller = RestageFlowController<SectionHeaderShowcaseResult>(
      flow: sectionHeaderShowcaseFlowRef,
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
    return RestageScreenView<SectionHeaderShowcaseResult>(
      controller: controller,
      loadingBuilder: (context) =>
          const Center(child: CircularProgressIndicator()),
    );
  }
}
