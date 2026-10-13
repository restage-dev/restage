import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';

import 'onboarding/flows/section_header_showcase.dart';

/// Renders bundled RFW to exercise record decoding in a custom widget factory.
/// For ordinary flow hosting, see MinimalNoticeFlowSurface in minimal_notice_demo.dart.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Register the example's custom widgets (incl. SectionHeader) so the
  // delivered blob's `SectionHeader(heading: ..., entry: ...)` reference
  // resolves to its generated factory.
  registerRestageWidgets();
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
