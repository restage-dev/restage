import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../stub_products.dart';
import 'flows/lumen_onboarding.dart';
import 'gallery_dismiss.dart';

/// Hosts the meditation onboarding→paywall engagement surface.
///
/// This is the *host* side: the small amount of app code that gives the flow
/// somewhere to run. It composes the public flow primitives directly — a
/// [RestageFlowController] (the brain) under a [RestageFlowView] (the rendering
/// surface) — rather than the convenience `RestageOnboarding` widget, because
/// the embedded paywall step needs the view's `onScreenEvent` seam to route the
/// purchase **through billing**: the flow advances to the subscribed state only
/// on a successful purchase outcome, never on a bare tap.
///
/// It does three things a real app would do:
/// 1. **Supplies the reminder host action.** A real app shows the OS permission
///    dialog and returns the user's answer; this demo returns a fixed
///    [grantReminders] decision so both branches are exercisable.
/// 2. **Routes the purchase through a billing gateway** (the [billingGateway]
///    integration point). When the embedded paywall fires `purchase`, the host
///    purchases the selected product and only advances the flow on success.
///    This demo's default gateway simulates a successful purchase; a real app
///    passes its own `BillingGateway` (the bundled `InAppPurchaseGateway`, …).
/// 3. **Fails closed.** An unavailable flow shows a plain fallback, never a
///    broken or partial flow.
///
/// Like the other examples this ships its flow as a bundled asset (no backend).
/// A production app delivers onboarding over the air by injecting a
/// `ServerFlowResolver` once at startup — the host action, billing, fail-closed,
/// and completion wiring are identical either way.
class LumenOnboardingDemo extends StatefulWidget {
  /// Creates the onboarding host.
  ///
  /// [grantReminders] is the decision the demo's reminder host action returns.
  /// `true` walks the granted path (the flow advances to the recap and the
  /// paywall); `false` walks the declined path (the gate holds on the priming
  /// screen — the flow never proceeds on behaviour it did not get).
  ///
  /// [billingGateway] is the **billing integration point**: the embedded
  /// paywall's purchase is routed through it, and the flow completes only on a
  /// successful outcome. Defaults to a gateway that simulates success; a real
  /// app passes its own.
  const LumenOnboardingDemo({
    super.key,
    this.grantReminders = true,
    this.billingGateway = const _SimulatedSuccessGateway(),
  });

  /// The fixed reminder decision this demo returns from the host action.
  final bool grantReminders;

  /// The billing gateway the embedded paywall's purchase routes through.
  final BillingGateway billingGateway;

  @override
  State<LumenOnboardingDemo> createState() => _LumenOnboardingDemoState();
}

class _LumenOnboardingDemoState extends State<LumenOnboardingDemo> {
  late final LumenOnboardingActions _actions;
  RestageFlowController<LumenOnboardingResult>? _controller;
  FlowUnavailableError? _unavailableError;
  bool _completed = false;
  bool _purchasing = false;

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
      flow: LumenOnboardingFlowDescriptor.ref,
      resolver: Restage.defaultFlowResolver,
      actions: _actions,
      onEvent: (event) {
        if (!mounted || !identical(_controller, controller)) return;
        Restage.fireEvent(event);
      },
      onComplete: (result) {
        if (!mounted || !identical(_controller, controller)) return;
        setState(() => _completed = result.subscribed);
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

  /// Intercepts the embedded paywall's `purchase` before it advances the graph,
  /// so the flow completes only on a successful billing outcome. Every other
  /// screen event flows through to the controller unchanged.
  bool _onScreenEvent(String name, Object? args) {
    // The view passes the RAW rfw event name (`restage.purchase`); the
    // controller normalizes it to the flow event when it isn't intercepted.
    if (name == RestageEventNames.purchase) {
      unawaited(_completePurchase(args));
      return true; // consumed — advance happens on a billing success only
    }
    return false;
  }

  Future<void> _completePurchase(Object? args) async {
    final controller = _controller;
    if (controller == null || _purchasing) return;
    _purchasing = true;
    try {
      // The billing INTEGRATION POINT. A real app purchases the user's selected
      // product through its billing gateway here; the flow advances to the
      // subscribed state ONLY on a successful outcome — never on a bare tap.
      final slot =
          args is Map && args['slot'] is String ? args['slot'] as String : null;
      final outcome = await widget.billingGateway.purchase(_productFor(slot));
      if (!mounted || !identical(_controller, controller)) return;
      if (outcome is PurchaseOutcomeSucceeded) {
        controller.handleEvent(RestageEventNames.purchase, args);
      }
      // A failed / cancelled / pending outcome leaves the user on the paywall;
      // a real app would surface the error and let them retry.
    } finally {
      _purchasing = false;
    }
  }

  /// Resolves the selected plan slot to a configured store product id.
  String _productFor(String? slot) {
    for (final product in kStubProducts) {
      if (product.slot == slot) return product.id;
    }
    return slot ?? 'unknown';
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
    return RestageOnboardingEventDispatcher(
      onEvent: controller.handleEvent,
      child: RestageFlowView<LumenOnboardingResult>(
        controller: controller,
        onScreenEvent: _onScreenEvent,
        loadingBuilder: (context) => const ColoredBox(color: Color(0xFFF7F5FB)),
        chromeBuilder: _chrome,
        priceQueries: kStubPriceQueries,
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

/// A billing gateway that simulates a successful purchase — the demo's stand-in
/// for a real `BillingGateway`. A production app swaps in its own (the bundled
/// `InAppPurchaseGateway`, …).
class _SimulatedSuccessGateway implements BillingGateway {
  const _SimulatedSuccessGateway();

  @override
  Future<PurchaseOutcome> purchase(String productId,
      {String? basePlanId}) async {
    return PurchaseOutcome.succeeded(
      productId: productId,
      transactionId: 'demo-transaction',
      verificationData: null,
      priceMicros: 0,
      currency: 'USD',
    );
  }

  @override
  Future<RestoreOutcome> restore() async => RestoreOutcome.noPurchases();
}

class _CompletionScreen extends StatelessWidget {
  const _CompletionScreen();

  @override
  Widget build(BuildContext context) {
    // The terminal "you subscribed" hand-off. In a real app this is the app
    // itself; in the gallery it needs a way back, so it carries the same
    // close-to-gallery affordance as the flow.
    return const Scaffold(
      backgroundColor: Color(0xFFF7F5FB),
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: Text(
                'Subscription started',
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
