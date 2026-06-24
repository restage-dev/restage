import 'package:flutter/widgets.dart';

/// Signature for paywall event callbacks.
///
/// Author-fired events from a rendered paywall (e.g. `paywallEvent('subscribe')`,
/// `paywallPurchase(slot: 'primary')`) reach the host app via this handler.
typedef PaywallEventHandler = void Function(
    String name, Map<String, Object?> args);

/// Stack of currently-active dispatchers. The top of the stack is queried
/// by [paywallEvent] / [paywallPurchase] when invoked outside a codegen
/// context.
///
/// This is a fallback for non-codegen invocations; in codegen-built paywalls
/// these helpers are replaced by RFW references at build time and never run at
/// runtime.
///
/// Design note: lookup is intentionally a module-level stack rather than an
/// `InheritedWidget` + `BuildContext` lookup. The context-based approach is
/// more idiomatic, but it would require the authoring helpers to accept a
/// `BuildContext` (`paywallEvent(context, …)`) — a breaking change to the
/// authoring API that the code-generation transpiler also pattern-matches on
/// by signature. Because this path runs only as the non-codegen fallback, and
/// because the dispatcher reference is captured when the helper is called
/// (during the host's `build()`, not at tap time — see [paywallEvent]), a
/// sibling surface mounted between build and tap cannot steal events via the
/// stack-top read. So the stack is kept as the stable shape.
final List<PaywallEventHandler> _dispatcherStack = <PaywallEventHandler>[];

/// Returns the most-recently-mounted [PaywallEventHandler], or `null` if no
/// [RestagePaywallEventDispatcher] is active.
///
/// Public so authoring helpers (`paywallEvent`, `paywallPurchase`) can look
/// up the active dispatcher without a `BuildContext`.
PaywallEventHandler? activeDispatcher() =>
    _dispatcherStack.isEmpty ? null : _dispatcherStack.last;

/// Provides an event-dispatch handler to its subtree.
///
/// `RestagePaywall` wraps its `RemoteWidget` subtree with this widget so
/// author-fired events from the rendered paywall reach the host's `onEvent`
/// callback.
///
/// Tracks the handler in a module-level stack: `initState` pushes,
/// `didUpdateWidget` swaps in place, `dispose` pops. Free-function authoring
/// helpers ([paywallEvent], [paywallPurchase]) read the top of the stack via
/// [activeDispatcher].
class RestagePaywallEventDispatcher extends StatefulWidget {
  /// Wraps [child] and routes paywall events fired in its subtree to [onEvent].
  const RestagePaywallEventDispatcher({
    super.key,
    required this.onEvent,
    required this.child,
  });

  /// Called when an authored helper (e.g. `paywallEvent`, `paywallPurchase`)
  /// fires while this dispatcher is the topmost in the stack.
  final PaywallEventHandler onEvent;

  /// The subtree under which paywall event helpers should resolve to
  /// [onEvent].
  final Widget child;

  @override
  State<RestagePaywallEventDispatcher> createState() =>
      _RestagePaywallEventDispatcherState();
}

class _RestagePaywallEventDispatcherState
    extends State<RestagePaywallEventDispatcher> {
  @override
  void initState() {
    super.initState();
    _dispatcherStack.add(widget.onEvent);
  }

  @override
  void didUpdateWidget(RestagePaywallEventDispatcher old) {
    super.didUpdateWidget(old);
    if (!identical(old.onEvent, widget.onEvent)) {
      final idx = _dispatcherStack.lastIndexOf(old.onEvent);
      if (idx >= 0) {
        _dispatcherStack[idx] = widget.onEvent;
      }
    }
  }

  @override
  void dispose() {
    final idx = _dispatcherStack.lastIndexOf(widget.onEvent);
    if (idx >= 0) {
      _dispatcherStack.removeAt(idx);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
