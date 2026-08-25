import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'flows/lumen_onboarding.dart';
import 'gallery_dismiss.dart';

/// Hosts the meditation onboarding→paywall engagement surface.
///
/// This is the *host* side: the small amount of app code that gives the flow
/// somewhere to run. It composes the public flow primitives directly — a
/// [RestageFlowController] (the brain) under a [RestageFlowView] (the rendering
/// surface) rather than the convenience `RestageFlowGraph` widget.
///
/// It does three things a real app would do:
/// 1. **Supplies the reminder host action.** A real app shows the OS permission
///    dialog and returns the user's answer; this demo returns a fixed
///    [grantReminders] decision so both branches are exercisable.
/// 2. **Fails closed.** An unavailable flow shows a plain fallback, never a
///    broken or partial flow.
///
/// Like the other examples this ships its flow as a bundled asset (no backend).
/// A production app delivers onboarding over the air by injecting a
/// `ServerFlowResolver` once at startup; the host action, fail-closed, and
/// completion wiring are identical either way.
class LumenOnboardingDemo extends StatefulWidget {
  /// Creates the onboarding host.
  ///
  /// [grantReminders] is the decision the demo's reminder host action returns.
  /// `true` walks the granted path (the flow advances to the recap and the
  /// paywall); `false` walks the declined path (the gate holds on the priming
  /// screen — the flow never proceeds on behaviour it did not get).
  ///
  const LumenOnboardingDemo({super.key, this.grantReminders = true});

  /// The fixed reminder decision this demo returns from the host action.
  final bool grantReminders;

  @override
  State<LumenOnboardingDemo> createState() => _LumenOnboardingDemoState();
}

class _LumenOnboardingDemoState extends State<LumenOnboardingDemo> {
  late final LumenOnboardingActions _actions;
  RestageFlowController<LumenOnboardingResult>? _controller;
  FlowUnavailableError? _unavailableError;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _actions = LumenOnboardingActions(
      enableReminders: (args, context) async {
        // A real app requests the OS notification permission here and returns
        // the user's answer. The demo returns a fixed decision so both branches
        // are exercisable.
        return ReminderDecision(granted: widget.grantReminders);
      },
    );
    _start();
  }

  void _start() {
    late final RestageFlowController<LumenOnboardingResult> controller;
    controller = RestageFlowController<LumenOnboardingResult>(
      flow: lumenOnboardingFlowRef,
      resolver: Restage.defaultFlowResolver,
      actions: _actions,
      onEvent: (event) {
        if (!mounted || !identical(_controller, controller)) return;
        Restage.fireEvent(event);
      },
      onComplete: (result) {
        if (!mounted || !identical(_controller, controller)) return;
        setState(() => _completed = result.completed);
      },
      onUnavailable: (error) {
        if (!mounted || !identical(_controller, controller)) return;
        setState(() => _unavailableError = error);
      },
    );
    _controller = controller;
    unawaited(controller.load());
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_completed) {
      return const _CompletionScreen();
    }
    final error = _unavailableError;
    if (error != null) {
      return ColoredBox(
        color: const Color(0xFFF7F5FB),
        child: Center(
          child: Text(
            error.message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF2A2833)),
          ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const ColoredBox(color: Color(0xFFF7F5FB));
    }
    return RestageEventDispatcher(
      onEvent: controller.handleEvent,
      child: RestageFlowView<LumenOnboardingResult>(
        controller: controller,
        loadingBuilder: (context) => const ColoredBox(color: Color(0xFFF7F5FB)),
        chromeBuilder: _chrome,
      ),
    );
  }

  Widget _chrome(
    BuildContext context,
    FlowChromeState state,
    Widget screen,
  ) {
    // The flow paints on a light calm canvas, so the chrome glyphs are dark. The
    // top-right close returns to the gallery on every platform (the surface is
    // hosted full-bleed with the gallery escape off, and iOS edge-swipe does not
    // reliably drive the flow's system-back); the top-left chevron is the
    // in-flow back, shown only with history to pop.
    return Stack(
      children: [
        Positioned.fill(child: screen),
        const Positioned(
          top: 0,
          right: 0,
          child: GalleryDismissButton(
            color: Color(0xFF2A2833),
            scrim: Color(0x2E000000),
          ),
        ),
        if (state.canBack)
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Semantics(
                  button: true,
                  label: 'Back',
                  child: GestureDetector(
                    key: const Key('lumen-onboarding-back'),
                    behavior: HitTestBehavior.opaque,
                    onTap: state.onBack,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: ExcludeSemantics(
                          child: Icon(
                            Icons.arrow_back,
                            color: Color(0xFF2A2833),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CompletionScreen extends StatelessWidget {
  const _CompletionScreen();

  @override
  Widget build(BuildContext context) {
    // The terminal hand-off. In the gallery it needs a way back, so it carries
    // the same close-to-gallery affordance as the flow.
    return const Scaffold(
      backgroundColor: Color(0xFFF7F5FB),
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: Text(
                'Onboarding complete',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF2A2833),
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: GalleryDismissButton(
              color: Color(0xFF2A2833),
              scrim: Color(0x2E000000),
            ),
          ),
        ],
      ),
    );
  }
}
