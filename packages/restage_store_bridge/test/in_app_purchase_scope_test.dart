import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:restage_store_bridge/restage_store_bridge.dart';

import 'support/fake_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  InAppPurchase.instance;
  debugDefaultTargetPlatformOverride = null;

  late FakeStore store;
  late List<Object> errors;
  late List<InAppPurchaseController> controllers;

  InAppPurchaseController create({
    Future<bool> Function(PurchaseDetails)? verify,
    Future<void> Function(PurchaseDetails)? deliver,
    FutureOr<void> Function(Object, StackTrace)? onError,
  }) {
    final controller = InAppPurchaseController(
      verifyPurchase: verify ?? (_) async => true,
      deliverPurchase: deliver ?? (_) async {},
      onError: (error, stack) {
        errors.add(error);
        return onError?.call(error, stack);
      },
    );
    controllers.add(controller);
    return controller;
  }

  setUp(() {
    store = FakeStore();
    InAppPurchasePlatform.instance = store;
    errors = [];
    controllers = [];
  });

  tearDown(() {
    for (final controller in controllers) {
      unawaited(
        controller.dispose().catchError((Object error) {
          expect(errors, contains(error));
        }),
      );
    }
    unawaited(store.updates.close());
  });

  void testScopeWidgets(
    String description,
    WidgetTesterCallback callback, {
    TargetPlatform platform = TargetPlatform.linux,
  }) {
    testWidgets(
      description,
      callback,
      variant: TargetPlatformVariant({platform}),
    );
  }

  testScopeWidgets('subscribes before child startup and catalog queries', (
    tester,
  ) async {
    final catalogStore = _CatalogStore();
    store = catalogStore;
    InAppPurchasePlatform.instance = store;
    await tester.pumpWidget(
      InAppPurchaseScope(
        create: create,
        child: _Startup(
          onStart: () {
            expect(store.updates.hasListener, isTrue);
            unawaited(InAppPurchase.instance.queryProductDetails({'pro'}));
          },
        ),
      ),
    );
    expect(catalogStore.queries, 1);
    expect(controllers, hasLength(1));
  });

  testScopeWidgets('rebuilds retain the controller and ignore a new factory', (
    tester,
  ) async {
    final observed = <InAppPurchaseController>[];
    Widget child() => Builder(
      builder: (context) {
        observed.add(InAppPurchaseScope.of(context));
        return const SizedBox();
      },
    );
    await tester.pumpWidget(InAppPurchaseScope(create: create, child: child()));
    await tester.pumpWidget(
      InAppPurchaseScope(
        create: () => throw StateError('Must retain the existing owner.'),
        child: child(),
      ),
    );
    expect(controllers, hasLength(1));
    expect(observed, [controllers.single, controllers.single]);
    expect(store.updates.hasListener, isTrue);
    expect(await observed.last.purchase(product()), isTrue);
  });

  testScopeWidgets('a new key replaces and disposes the owner', (tester) async {
    await tester.pumpWidget(
      InAppPurchaseScope(
        key: const ValueKey('first'),
        create: create,
        child: const SizedBox(),
      ),
    );
    final first = controllers.single;
    await tester.pumpWidget(
      InAppPurchaseScope(
        key: const ValueKey('second'),
        create: create,
        child: const SizedBox(),
      ),
    );
    expect(controllers, hasLength(2));
    expect(controllers.last, isNot(same(first)));
    await expectLater(first.purchase(product()), throwsStateError);
    expect(await controllers.last.purchase(product()), isTrue);
    expect(store.updates.hasListener, isTrue);
  });

  testScopeWidgets('controller survives route opening and dismissal', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final observed = <InAppPurchaseController>[];
    Widget page(BuildContext context) {
      observed.add(InAppPurchaseScope.of(context));
      return const SizedBox();
    }

    await tester.pumpWidget(
      InAppPurchaseScope(
        create: create,
        child: MaterialApp(
          navigatorKey: navigator,
          home: Builder(builder: page),
        ),
      ),
    );
    unawaited(navigator.currentState!.push(MaterialPageRoute(builder: page)));
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(observed.length, greaterThanOrEqualTo(2));
    expect(observed, everyElement(same(controllers.single)));
    expect(store.updates.hasListener, isTrue);
    expect(await controllers.single.purchase(product()), isTrue);
  });

  testScopeWidgets(
    'unmount cancels the subscription and removes the observer',
    (tester) async {
      await tester.pumpWidget(
        InAppPurchaseScope(create: create, child: const SizedBox()),
      );
      final observer =
          tester.state(find.byType(InAppPurchaseScope))
              as WidgetsBindingObserver;
      expect(store.updates.hasListener, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(store.updates.hasListener, isFalse);
      expect(tester.binding.removeObserver(observer), isFalse);
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(store.calls, ['restore']);
      expect(errors, isEmpty);
      await expectLater(
        controllers.single.purchase(product()),
        throwsStateError,
      );
      await expectLater(
        controllers.single.restorePurchases(),
        throwsStateError,
      );
      await expectLater(
        controllers.single.retryPendingPurchases(),
        throwsStateError,
      );
    },
    platform: TargetPlatform.android,
  );

  for (final blockedStage in ['verify', 'deliver', 'complete']) {
    testScopeWidgets('unmount observes already-running $blockedStage work', (
      tester,
    ) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final stages = <String>[];
      Future<void> stage(String name) async {
        stages.add(name);
        if (name == blockedStage) await gate.future;
      }

      store.onComplete = (_) => stage('complete');
      await tester.pumpWidget(
        InAppPurchaseScope(
          create: () => create(
            verify: (_) async {
              await stage('verify');
              return true;
            },
            deliver: (_) => stage('deliver'),
          ),
          child: const SizedBox(),
        ),
      );
      store.updates.add([apple()]);
      await tester.pump();
      expect(stages.last, blockedStage);
      await tester.pumpWidget(const SizedBox());
      expect(store.updates.hasListener, isFalse);
      var disposed = false;
      unawaited(controllers.single.dispose().then((_) => disposed = true));
      await tester.pump();
      expect(disposed, isFalse);
      gate.complete();
      await tester.pump();
      await tester.runAsync(() async {});
      await tester.pump();
      expect(stages, ['verify', 'deliver', 'complete']);
      expect(disposed, isTrue);
      expect(errors, isEmpty);
    });
  }

  testScopeWidgets('purchase processing failures after unmount are reported', (
    tester,
  ) async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final failure = StateError('Delivery failed.');
    await tester.pumpWidget(
      InAppPurchaseScope(
        create: () => create(
          deliver: (_) async {
            await gate.future;
            throw failure;
          },
        ),
        child: const SizedBox(),
      ),
    );
    store.updates.add([apple()]);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump();
    expect(errors, [failure]);
    expect(store.completed, isEmpty);
  });

  testScopeWidgets(
    'Android recovers at startup and resume while coalescing overlap',
    (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      store.onRestore = () {
        expectSync(store.updates.hasListener, isTrue);
        return gate.future;
      };
      await tester.pumpWidget(
        InAppPurchaseScope(create: create, child: const SizedBox()),
      );
      expect(store.calls, ['restore']);
      for (var i = 0; i < 3; i++) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pump();
      expect(store.calls, ['restore']);
      gate.complete();
      await tester.pump();
      expect(store.calls, ['restore']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(store.calls, ['restore', 'restore']);
      await tester.pumpWidget(const SizedBox());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(store.calls, ['restore', 'restore']);
      expect(errors, isEmpty);
    },
    platform: TargetPlatform.android,
  );

  testScopeWidgets(
    'automatic recovery failures use the controller error callback',
    (tester) async {
      final failure = StateError('Restore failed.');
      final reporting = Completer<void>();
      addTearDown(() {
        if (!reporting.isCompleted) reporting.complete();
      });
      store.onRestore = () async => throw failure;
      await tester.pumpWidget(
        InAppPurchaseScope(
          create: () => create(onError: (_, _) => reporting.future),
          child: const SizedBox(),
        ),
      );
      expect(errors, [failure]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(store.calls, ['restore']);
      expect(errors, [failure]);
      reporting.complete();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(store.calls, ['restore', 'restore']);
      expect(errors, [failure, failure]);
      expect(tester.takeException(), isNull);
    },
    platform: TargetPlatform.android,
  );

  testScopeWidgets('in-flight recovery errors remain observed after unmount', (
    tester,
  ) async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final failure = StateError('Restore failed after unmount.');
    store.onRestore = () => gate.future;
    await tester.pumpWidget(
      InAppPurchaseScope(create: create, child: const SizedBox()),
    );
    await tester.pumpWidget(const SizedBox());
    gate.completeError(failure);
    await tester.pump();
    expect(errors, [failure]);
    expect(store.updates.hasListener, isFalse);
    expect(tester.takeException(), isNull);
  }, platform: TargetPlatform.android);

  testScopeWidgets(
    'iOS restore is explicit and preserves caller-owned errors',
    (tester) async {
      await tester.pumpWidget(
        InAppPurchaseScope(create: create, child: const SizedBox()),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(store.calls, isEmpty);
      final failure = StateError('Explicit restore failed.');
      store.onRestore = () async => throw failure;
      await expectLater(
        controllers.single.restorePurchases(),
        throwsA(same(failure)),
      );
      expect(store.calls, ['restore']);
      expect(errors, isEmpty);
    },
    platform: TargetPlatform.iOS,
  );

  testScopeWidgets(
    'asynchronous disposal errors use the controller error callback',
    (tester) async {
      final failure = StateError('Cancellation failed.');
      store = _CancellationFailureStore(failure);
      InAppPurchasePlatform.instance = store;
      final reporting = Completer<void>();
      addTearDown(() {
        if (!reporting.isCompleted) reporting.complete();
      });
      await tester.pumpWidget(
        InAppPurchaseScope(
          create: () => create(onError: (_, _) => reporting.future),
          child: const SizedBox(),
        ),
      );
      final observer =
          tester.state(find.byType(InAppPurchaseScope))
              as WidgetsBindingObserver;
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(store.updates.hasListener, isFalse);
      expect(tester.binding.removeObserver(observer), isFalse);
      expect(errors, [failure]);
      reporting.complete();
      await tester.pump();
      expect(errors, [failure]);
      expect(tester.takeException(), isNull);
    },
  );

  testScopeWidgets(
    'missing scope explains app placement and descendant context',
    (tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            InAppPurchaseScope.of(context);
            return const SizedBox();
          },
        ),
      );
      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect(error.toString(), contains('No InAppPurchaseScope found'));
      expect(error.toString(), contains('above MaterialApp'));
      expect(error.toString(), contains('descendant context'));
    },
  );
}

class _CatalogStore extends FakeStore {
  var queries = 0;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) {
    expect(updates.hasListener, isTrue);
    queries++;
    return Future.value(
      ProductDetailsResponse(productDetails: [product()], notFoundIDs: []),
    );
  }
}

class _CancellationFailureStore extends FakeStore {
  _CancellationFailureStore(Object error)
    : _updates = StreamController<List<PurchaseDetails>>(
        onCancel: () => Future<void>.error(error),
      );

  final StreamController<List<PurchaseDetails>> _updates;

  @override
  StreamController<List<PurchaseDetails>> get updates => _updates;
}

class _Startup extends StatefulWidget {
  const _Startup({required this.onStart});

  final VoidCallback onStart;

  @override
  State<_Startup> createState() => _StartupState();
}

class _StartupState extends State<_Startup> {
  @override
  void initState() {
    super.initState();
    widget.onStart();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
