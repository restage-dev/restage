import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:restage_store_bridge/src/in_app_purchase_controller.dart';

import 'support/fake_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Initialize the singleton on the test platform before installing our fakes.
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  InAppPurchase.instance;
  debugDefaultTargetPlatformOverride = null;

  late FakeStore store;
  late List<Object> errors;
  late List<String> calls;
  late List<InAppPurchaseController> controllers;

  InAppPurchaseController controller({
    Future<bool> Function(PurchaseDetails)? verify,
    Future<void> Function(PurchaseDetails)? deliver,
    FutureOr<void> Function(PurchaseDetails)? updated,
    PurchaseParam Function(ProductDetails)? builder,
    Set<String> consumables = const {},
    FutureOr<void> Function(Object, StackTrace)? errorCallback,
  }) {
    final result = InAppPurchaseController(
      verifyPurchase:
          verify ??
          (_) async {
            calls.add('verify');
            return true;
          },
      deliverPurchase:
          deliver ??
          (_) async {
            calls.add('deliver');
          },
      onError: (error, stack) {
        errors.add(error);
        return errorCallback?.call(error, stack);
      },
      onPurchaseUpdated: updated,
      purchaseParamBuilder: builder,
      consumableProductIds: consumables,
    );
    controllers.add(result);
    return result;
  }

  setUp(() {
    store = FakeStore();
    InAppPurchasePlatform.instance = store;
    errors = [];
    calls = [];
    controllers = [];
  });

  tearDown(() async {
    for (final item in controllers) {
      await item.dispose();
    }
    await store.updates.close();
  });

  void android() {
    store = FakeAndroidStore();
    InAppPurchasePlatform.instance = store;
    InAppPurchasePlatformAddition.instance = FakeAndroidAddition();
  }

  test(
    'subscribes at startup and handles external and restored purchases',
    () async {
      final owner = controller();
      expect(store.updates.hasListener, isTrue);
      store.onComplete = (_) async {
        calls.add('complete');
      };
      store.updates.add([
        apple(id: 'external'),
        apple1(id: 'restored', status: PurchaseStatus.restored),
      ]);
      await owner.retryPendingPurchases();
      expect(calls.where((call) => call == 'verify'), hasLength(2));
      expect(calls.where((call) => call == 'deliver'), hasLength(2));
      expect(store.completed, hasLength(2));
      expect(errors, isEmpty);
    },
  );

  test('pending and canceled states reach UI without verification', () async {
    final statuses = <PurchaseStatus>[];
    controller(
      updated: (purchase) {
        statuses.add(purchase.status);
      },
    );
    store.updates.add([
      apple(id: null, status: PurchaseStatus.pending),
      apple(id: null, status: PurchaseStatus.canceled),
    ]);
    await flushStore();
    expect(statuses, [PurchaseStatus.pending, PurchaseStatus.canceled]);
    expect(calls, isEmpty);
    expect(store.completed, isEmpty);
    expect(errors, isEmpty);
  });

  test('StoreKit 1 terminal states finish without a transaction ID', () async {
    final owner = controller();
    final canceled = apple1(id: null, status: PurchaseStatus.canceled);
    final failed = apple1(id: null, status: PurchaseStatus.error)
      ..error = IAPError(source: 'store', code: 'failed', message: 'failed');
    store.updates.add([canceled, failed]);
    await owner.retryPendingPurchases();
    expect(store.completed, [canceled, failed]);
    expect(calls, isEmpty);
    expect(errors, [failed.error]);
  });

  test(
    'UI callback failure and stream errors are reported independently',
    () async {
      final owner = controller(
        updated: (_) {
          throw StateError('UI');
        },
      );
      store.updates.add([apple()]);
      store.updates.addError(StateError('stream'), StackTrace.current);
      await owner.retryPendingPurchases();
      await flushStore();
      expect(calls, ['verify', 'deliver']);
      expect(store.completed, hasLength(1));
      expect(
        errors.map((error) => error.toString()),
        containsAll(['Bad state: UI', 'Bad state: stream']),
      );
    },
  );

  test(
    'unsupported and missing purchased identities fail before delivery',
    () async {
      final owner = controller();
      store.updates.add([
        apple(id: null),
        apple(id: ''),
        apple1(id: null),
        PurchaseDetails(
          productID: 'pro',
          verificationData: verification,
          transactionDate: null,
          status: PurchaseStatus.restored,
        ),
      ]);
      await owner.retryPendingPurchases();
      expect(errors, hasLength(4));
      expect(calls, isEmpty);
      expect(store.completed, isEmpty);
    },
  );

  test(
    'StoreKit 1 uses the native ID when common purchaseID is null',
    () async {
      final owner = controller();
      store.updates.add([apple1(), apple1()]);
      await owner.retryPendingPurchases();
      expect(calls, ['verify', 'deliver']);
      expect(store.completed, hasLength(1));
    },
  );

  test('verification false is terminal across retry and redelivery', () async {
    final owner = controller(
      verify: (_) async {
        calls.add('verify');
        return false;
      },
    );
    store.updates.add([apple()]);
    await owner.retryPendingPurchases();
    store.updates.add([apple()]);
    await owner.retryPendingPurchases();
    expect(calls, ['verify']);
    expect(store.completed, isEmpty);
    expect(errors, isEmpty);
  });

  for (final stage in ['verify', 'deliver']) {
    test('$stage failure retries only the failed and later stages', () async {
      var failed = false;
      final owner = controller(
        verify: (_) async {
          calls.add('verify');
          if (stage == 'verify' && !failed) {
            failed = true;
            throw StateError(stage);
          }
          return true;
        },
        deliver: (_) async {
          calls.add('deliver');
          if (stage == 'deliver' && !failed) {
            failed = true;
            throw StateError(stage);
          }
        },
      );
      store.onComplete = (_) async {
        calls.add('complete');
      };
      store.updates.add([apple()]);
      await flushStore();
      expect(store.completed, isEmpty);
      await owner.retryPendingPurchases();
      expect(
        calls,
        stage == 'verify'
            ? ['verify', 'verify', 'deliver', 'complete']
            : ['verify', 'deliver', 'deliver', 'complete'],
      );
      expect(errors, hasLength(1));
    });
  }

  for (final stage in ['verify', 'deliver', 'complete']) {
    test('error callback can await retry of thrown $stage stage', () async {
      final release = Completer<void>();
      var failed = false;
      var reportReturned = false;
      late InAppPurchaseController owner;
      void attempt(String current) {
        calls.add(current);
        if (stage == current && !failed) {
          failed = true;
          throw StateError(stage);
        }
      }

      owner = controller(
        verify: (_) async {
          attempt('verify');
          return true;
        },
        deliver: (_) async {
          attempt('deliver');
        },
        errorCallback: (_, __) async {
          await Future.any([owner.retryPendingPurchases(), release.future]);
          reportReturned = true;
        },
      );
      store.onComplete = (_) async {
        attempt('complete');
      };
      try {
        store.updates.add([apple()]);
        await flushStore();
        expect(reportReturned, isTrue);
        expect(calls, switch (stage) {
          'verify' => ['verify', 'verify', 'deliver', 'complete'],
          'deliver' => ['verify', 'deliver', 'deliver', 'complete'],
          _ => ['verify', 'deliver', 'complete', 'complete'],
        });
        expect(errors, hasLength(1));
        await owner.dispose();
      } finally {
        release.complete();
      }
    });
  }

  test(
    'error callback retry retains ownership during concurrent duplicates',
    () async {
      final delivery = Completer<void>();
      var verifies = 0;
      late InAppPurchaseController owner;
      owner = controller(
        verify: (_) async {
          calls.add('verify');
          if (++verifies == 1) throw StateError('verify');
          return true;
        },
        deliver: (_) async {
          calls.add('deliver');
          await delivery.future;
        },
        errorCallback: (_, __) {
          unawaited(owner.retryPendingPurchases());
        },
      );
      try {
        store.updates.add([apple()]);
        await flushStore();
        store.updates.add([apple(), apple()]);
        final joined = owner.retryPendingPurchases();
        await flushStore();
        expect(calls, ['verify', 'verify', 'deliver']);
        delivery.complete();
        await joined;
        expect(store.completed, hasLength(1));
      } finally {
        if (!delivery.isCompleted) delivery.complete();
      }
    },
  );

  test(
    'verification retry uses refreshed same-identity purchase details',
    () async {
      final seen = <PurchaseDetails>[];
      final delivered = <PurchaseDetails>[];
      final owner = controller(
        verify: (purchase) async {
          seen.add(purchase);
          if (purchase.verificationData.serverVerificationData == 'receipt') {
            throw StateError('refresh needed');
          }
          return true;
        },
        deliver: (purchase) async {
          delivered.add(purchase);
        },
      );
      final original = apple();
      final refreshed = apple(
        data: PurchaseVerificationData(
          localVerificationData: 'fresh',
          serverVerificationData: 'fresh',
          source: 'store',
        ),
      );
      store.updates.add([original]);
      await flushStore();
      store.updates.add([refreshed]);
      await owner.retryPendingPurchases();
      expect(seen, [same(original), same(refreshed)]);
      expect(delivered, [same(refreshed)]);
      expect(store.completed, [same(original)]);
      expect(errors, hasLength(1));
    },
  );

  test('successful delivery is retained after completion failure', () async {
    final owner = controller();
    var finishAttempts = 0;
    store.onComplete = (_) async {
      calls.add('complete');
      if (finishAttempts++ == 0) throw StateError('finish');
    };
    store.updates.add([apple()]);
    await flushStore();
    expect(calls, ['verify', 'deliver', 'complete']);
    await owner.retryPendingPurchases();
    expect(calls, ['verify', 'deliver', 'complete', 'complete']);
    expect(errors, hasLength(1));
  });

  test(
    'restored duplicate retains the original failed StoreKit 2 finish',
    () async {
      final owner = controller();
      final original = apple();
      var attempts = 0;
      store.onComplete = (_) async {
        if (attempts++ == 0) throw StateError('finish');
      };
      store.updates.add([original]);
      await flushStore();
      store.updates.add([apple(status: PurchaseStatus.restored)]);
      await owner.retryPendingPurchases();
      expect(calls, ['verify', 'deliver']);
      expect(store.completed, [same(original), same(original)]);
    },
  );

  test('retry and duplicate updates share a running transaction', () async {
    final gate = Completer<void>();
    final owner = controller(
      deliver: (_) async {
        calls.add('deliver');
        await gate.future;
      },
    );
    store.updates.add([apple(), apple()]);
    await flushStore();
    final retry = owner.retryPendingPurchases();
    store.updates.add([apple()]);
    expect(calls, ['verify', 'deliver']);
    gate.complete();
    await retry;
    expect(calls, ['verify', 'deliver']);
    expect(store.completed, hasLength(1));
  });

  test(
    'duplicate updates arriving during a failed completion retry join it',
    () async {
      final owner = controller();
      final gate = Completer<void>();
      var attempts = 0;
      store.onComplete = (_) async {
        calls.add('complete');
        if (attempts++ == 0) throw StateError('finish');
        await gate.future;
      };
      store.updates.add([apple()]);
      await flushStore();
      final retry = owner.retryPendingPurchases();
      await flushStore();
      store.updates.add([apple(), apple(status: PurchaseStatus.restored)]);
      final secondRetry = owner.retryPendingPurchases();
      expect(calls, ['verify', 'deliver', 'complete', 'complete']);
      gate.complete();
      await Future.wait([retry, secondRetry]);
      expect(store.completed, hasLength(2));
      expect(calls, ['verify', 'deliver', 'complete', 'complete']);
    },
  );

  test(
    'failed terminal StoreKit cleanup is retryable without delivery',
    () async {
      final owner = controller();
      var attempts = 0;
      store.onComplete = (_) async {
        if (attempts++ == 0) throw StateError('finish');
      };
      store.updates.add([apple1(id: null, status: PurchaseStatus.canceled)]);
      await flushStore();
      await owner.retryPendingPurchases();
      expect(calls, isEmpty);
      expect(store.completed, hasLength(2));
      expect(errors, hasLength(1));
    },
  );

  test(
    'distinct native transactions for the same product are delivered',
    () async {
      final owner = controller();
      store.updates.add([apple(id: 'one'), apple(id: 'two')]);
      await owner.retryPendingPurchases();
      expect(calls.where((call) => call == 'deliver'), hasLength(2));
    },
  );

  test(
    'exact selected product and app purchase parameters reach dispatch',
    () async {
      final selected = product();
      final param = PurchaseParam(
        productDetails: selected,
        applicationUserName: 'account',
      );
      final owner = controller(builder: (_) => param);
      expect(await owner.purchase(selected), isTrue);
      expect(store.params.single, same(param));
      expect(store.params.single.productDetails, same(selected));
    },
  );

  test('parameter builder cannot substitute an equivalent product', () async {
    final owner = controller(
      builder: (_) => PurchaseParam(productDetails: product()),
    );
    await expectLater(owner.purchase(product()), throwsArgumentError);
    expect(store.params, isEmpty);
  });

  test(
    'native acceptance false and dispatch errors retain their result',
    () async {
      final owner = controller();
      store.onBuy = () async => false;
      expect(await owner.purchase(product()), isFalse);
      store.onBuy = () async => throw StateError('dispatch');
      await expectLater(owner.purchase(product()), throwsStateError);
      store.onBuy = null;
      expect(await owner.purchase(product()), isTrue);
    },
  );

  test(
    'purchase and restore dispatch serialize only until native return',
    () async {
      final owner = controller();
      final native = Completer<bool>();
      store.onBuy = () => native.future;
      final first = owner.purchase(product());
      final restore = owner.restorePurchases();
      final second = owner.purchase(product());
      await flushStore();
      expect(store.calls, ['buy']);
      native.complete(true);
      await Future.wait([first, restore, second]);
      expect(store.calls, ['buy', 'restore', 'buy']);
      expect(calls, isEmpty);
    },
  );

  test('Apple consumable dispatch keeps normal auto consumption', () async {
    final owner = controller(consumables: {'coins'});
    await owner.purchase(product('coins'));
    expect(store.autoConsume, isTrue);
  });

  test(
    'disposal observes active dispatch and refuses queued and new calls',
    () async {
      final owner = controller();
      final native = Completer<bool>();
      store.onBuy = () => native.future;
      final first = owner.purchase(product());
      await flushStore();
      final queued = owner.restorePurchases();
      final refused = expectLater(queued, throwsStateError);
      var disposed = false;
      final disposal = owner.dispose().then((_) {
        disposed = true;
      });
      await expectLater(owner.purchase(product()), throwsStateError);
      await expectLater(owner.restorePurchases(), throwsStateError);
      await expectLater(owner.retryPendingPurchases(), throwsStateError);
      await flushStore();
      expect(disposed, isFalse);
      expect(store.updates.hasListener, isFalse);
      native.complete(false);
      expect(await first, isFalse);
      await refused;
      await disposal;
      expect(store.calls, ['buy']);
      expect(owner.dispose(), completes);
    },
  );

  test(
    'disposal waits for delivery and completion already in progress',
    () async {
      final gate = Completer<void>();
      final owner = controller(
        deliver: (_) async {
          calls.add('deliver');
          await gate.future;
        },
      );
      store.updates.add([apple()]);
      await flushStore();
      var disposed = false;
      final disposal = owner.dispose().then((_) {
        disposed = true;
      });
      await flushStore();
      expect(disposed, isFalse);
      store.updates.add([apple(id: 'ignored')]);
      gate.complete();
      await disposal;
      expect(calls, ['verify', 'deliver']);
      expect(store.completed, hasLength(1));
    },
  );

  test('Google native token works with nullable common purchaseID', () async {
    android();
    final owner = controller();
    store.updates.add([google(), google()]);
    await owner.retryPendingPurchases();
    expect(calls, ['verify', 'deliver']);
    expect(store.completed, hasLength(1));
    expect(errors, isEmpty);
  });

  test(
    'Google order enrichment and missing-order duplicates retain delivery',
    () async {
      android();
      final owner = controller();
      store.updates.add([google(order: '')]);
      await owner.retryPendingPurchases();
      store.updates.add([google(order: 'order.0'), google(order: '')]);
      await owner.retryPendingPurchases();
      expect(calls, ['verify', 'deliver']);
      expect(store.completed, hasLength(1));
      store.updates.add([google(order: 'order.1')]);
      await owner.retryPendingPurchases();
      store.updates.add([google(order: '')]);
      await owner.retryPendingPurchases();
      expect(calls.where((call) => call == 'deliver'), hasLength(2));
      expect(errors, hasLength(1));
    },
  );

  test(
    'Google renewal order IDs distinguish transactions sharing a token',
    () async {
      android();
      final owner = controller();
      store.updates.add([google(order: 'order.0'), google(order: 'order.1')]);
      await owner.retryPendingPurchases();
      expect(calls.where((call) => call == 'deliver'), hasLength(2));
      expect(store.completed, hasLength(2));
    },
  );

  test(
    'Google acknowledged nonconsumables verify and deliver without ack',
    () async {
      android();
      final owner = controller();
      store.updates.add([google(acknowledged: true)]);
      await owner.retryPendingPurchases();
      expect(calls, ['verify', 'deliver']);
      expect(store.completed, isEmpty);
    },
  );

  for (final status in [PurchaseStatus.restored, PurchaseStatus.purchased]) {
    test(
      'Google native pending with $status waits for purchased state',
      () async {
        android();
        final observed = <PurchaseDetails>[];
        final owner = controller(updated: observed.add);
        GooglePlayPurchaseDetails pending(String token) =>
            GooglePlayPurchaseDetails.fromPurchase(
              google(
                token: token,
                order: '',
                state: PurchaseStateWrapper.pending,
              ).billingClientPurchase,
            ).single..status = status;
        final original = pending('token');
        final unidentified = pending('');
        store.updates.add([original, unidentified]);
        await owner.retryPendingPurchases();
        expect(observed.map((update) => update.status), [
          PurchaseStatus.pending,
          PurchaseStatus.pending,
        ]);
        expect(observed.first, isNot(same(original)));
        expect(
          (observed.first as GooglePlayPurchaseDetails).billingClientPurchase,
          same(original.billingClientPurchase),
        );
        expect(original.status, status);
        expect(unidentified.status, status);
        expect(calls, isEmpty);
        expect(store.completed, isEmpty);
        expect(errors, isEmpty);
        expect(
          (InAppPurchasePlatformAddition.instance as FakeAndroidAddition)
              .consumed,
          isEmpty,
        );

        store.onComplete = (_) async {
          calls.add('complete');
        };
        store.updates.add([google(status: PurchaseStatus.restored), google()]);
        await owner.retryPendingPurchases();
        expect(calls, ['verify', 'deliver', 'complete']);
        expect(observed.map((update) => update.status), [
          PurchaseStatus.pending,
          PurchaseStatus.pending,
          PurchaseStatus.restored,
          PurchaseStatus.purchased,
        ]);
        expect(errors, isEmpty);
        expect(store.completed, hasLength(1));
      },
    );
  }

  test(
    'Google terminal updates retain their state even with native pending',
    () async {
      android();
      final observed = <PurchaseDetails>[];
      final owner = controller(updated: observed.add);
      final canceled = google(
        status: PurchaseStatus.canceled,
        state: PurchaseStateWrapper.pending,
        token: '',
      );
      final failed = google(
        status: PurchaseStatus.error,
        state: PurchaseStateWrapper.pending,
        token: '',
      )..error = IAPError(source: 'store', code: 'failed', message: 'failed');
      store.updates.add([canceled, failed]);
      await owner.retryPendingPurchases();
      expect(observed, [same(canceled), same(failed)]);
      expect(observed.map((update) => update.status), [
        PurchaseStatus.canceled,
        PurchaseStatus.error,
      ]);
      expect(errors, [same(failed.error)]);
      expect(calls, isEmpty);
      expect(store.completed, isEmpty);
    },
  );

  test(
    'Google refuses multiple products and invalid native purchase state',
    () async {
      android();
      final owner = controller(consumables: {'pro'});
      store.updates.add([
        google(products: ['pro', 'other']),
        google(token: ''),
        google(
          status: PurchaseStatus.restored,
          state: PurchaseStateWrapper.unspecified_state,
        ),
        google(products: ['different']),
      ]);
      await owner.retryPendingPurchases();
      expect(calls, isEmpty);
      expect(store.completed, isEmpty);
      expect(
        (InAppPurchasePlatformAddition.instance as FakeAndroidAddition)
            .consumed,
        isEmpty,
      );
      expect(errors, hasLength(4));
    },
  );

  test(
    'Google completion response failure resumes acknowledgment only',
    () async {
      android();
      final owner = controller();
      (store as FakeAndroidStore).completionCode = BillingResponse.error;
      store.updates.add([google()]);
      await flushStore();
      expect(calls, ['verify', 'deliver']);
      expect(errors, hasLength(1));
      (store as FakeAndroidStore).completionCode = BillingResponse.ok;
      await owner.retryPendingPurchases();
      expect(calls, ['verify', 'deliver']);
      expect(store.completed, hasLength(2));
    },
  );

  test(
    'Google consumption follows delivery and never acknowledges afterward',
    () async {
      android();
      final addition =
          InAppPurchasePlatformAddition.instance as FakeAndroidAddition;
      addition.onConsume = () async {
        calls.add('consume');
      };
      final owner = controller(consumables: {'coins'});
      await owner.purchase(product('coins'));
      expect(store.autoConsume, isFalse);
      store.updates.add([google(productId: 'coins', acknowledged: true)]);
      await owner.retryPendingPurchases();
      expect(calls, ['verify', 'deliver', 'consume']);
      expect(store.completed, isEmpty);
      store.updates.add([google(productId: 'coins')]);
      await owner.retryPendingPurchases();
      expect(addition.consumed, hasLength(1));
    },
  );

  test(
    'Google non-OK consumption remains unfinished and retries consumption',
    () async {
      android();
      final addition =
          InAppPurchasePlatformAddition.instance as FakeAndroidAddition;
      addition.response = BillingResponse.itemNotOwned;
      final owner = controller(consumables: {'coins'});
      store.updates.add([google(productId: 'coins')]);
      await flushStore();
      expect(errors, hasLength(1));
      addition.response = BillingResponse.ok;
      await owner.retryPendingPurchases();
      expect(calls, ['verify', 'deliver']);
      expect(addition.consumed, hasLength(2));
      expect(store.completed, isEmpty);
    },
  );
}
