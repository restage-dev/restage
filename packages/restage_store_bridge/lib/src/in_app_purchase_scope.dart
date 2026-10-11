part of 'in_app_purchase_controller.dart';

/// Owns a purchase controller above app navigation.
///
/// Mount before querying products. Android purchases recover automatically at
/// startup and on resume; Apple restore remains an explicit user action.
class InAppPurchaseScope extends StatefulWidget {
  /// Creates one controller for this scope's mounted lifetime.
  const InAppPurchaseScope({
    required this.create,
    required this.child,
    super.key,
  });

  /// Called once, before [child] is built.
  ///
  /// Rebuilds retain the controller and its callbacks. Use a different key to
  /// dispose the current controller and create a replacement.
  final InAppPurchaseController Function() create;

  /// The app subtree that uses the controller.
  final Widget child;

  /// Returns the controller owned by the nearest enclosing scope.
  static InAppPurchaseController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_InAppPurchaseInheritedScope>();
    if (scope == null) {
      throw FlutterError.fromParts([
        ErrorSummary('No InAppPurchaseScope found in this context.'),
        ErrorDescription(
          'InAppPurchaseScope.of requires a context below InAppPurchaseScope.',
        ),
        ErrorHint(
          'Wrap your app in InAppPurchaseScope above MaterialApp or your '
          'navigator, then use a descendant context.',
        ),
      ]);
    }
    return scope.controller;
  }

  @override
  State<InAppPurchaseScope> createState() => _InAppPurchaseScopeState();
}

class _InAppPurchaseScopeState extends State<InAppPurchaseScope>
    with WidgetsBindingObserver {
  late final InAppPurchaseController _controller;
  bool _recovering = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.create();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_recoverPurchases());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_recoverPurchases());
    }
  }

  Future<void> _recoverPurchases() async {
    if (_disposed ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        _recovering) {
      return;
    }
    _recovering = true;
    try {
      await _observe(_controller.restorePurchases());
    } finally {
      _recovering = false;
    }
  }

  Future<void> _observe(Future<void> operation) async {
    try {
      await operation;
    } on Object catch (error, stack) {
      await _controller._report(error, stack);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_observe(_controller.dispose()));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _InAppPurchaseInheritedScope(
    controller: _controller,
    child: widget.child,
  );
}

class _InAppPurchaseInheritedScope extends InheritedWidget {
  const _InAppPurchaseInheritedScope({
    required this.controller,
    required super.child,
  });

  final InAppPurchaseController controller;

  @override
  bool updateShouldNotify(_InAppPurchaseInheritedScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}
