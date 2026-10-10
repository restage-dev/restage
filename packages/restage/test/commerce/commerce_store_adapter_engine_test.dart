import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/commerce.dart';
import 'package:restage/restage.dart' show Restage;
import 'package:restage/src/analytics/analytics_identity.dart';
import 'package:restage/src/analytics/root_analytics_context.dart';
import 'package:restage/src/commerce/commerce_report_queue.dart';
import 'package:restage/src/commerce/commerce_report_queue_io.dart';
import 'package:restage/src/commerce/restage_commerce.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/commerce.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _applicationToken = 'c9ea7617-468c-4be9-9430-080703537a9c';
const _secondApplicationToken = '59eb1fa6-e556-46a4-9fb8-1f77244fe865';
const _appAccountToken = '65f81e99-48e0-4acf-a532-12a27b6b119c';

void main() {
  setUp(Restage.debugReset);
  tearDown(Restage.debugReset);

  test('maps an Apple transaction through a verified report before finishing',
      () async {
    final events = <String>[];
    final reports = <Map<String, dynamic>>[];
    final completion = Completer<void>();
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[
        _TestStoreProduct(
          store: CommerceStore.appStore,
          storeProductId: 'subscription.monthly',
        ),
      ],
      onComplete: (transaction) async {
        events.add('complete');
        if (!completion.isCompleted) completion.complete();
      },
    );
    addTearDown(adapter.close);
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      switch (request.url.path) {
        case '/sdk/v1/commerce/intents':
          return _jsonResponse(
            CommerceIntentResponse(
              intentId: body['intentId']! as String,
              status: 'ready',
              resolved: CommerceResolvedPurchasable(
                storeProductId: 'subscription.monthly',
                productKind: 'autoRenewableSubscription',
                appAccountToken: _appAccountToken,
              ),
            ).toJson(),
          );
        case '/sdk/v1/commerce/reports':
          reports.add(body);
          events.add('report');
          return _jsonResponse(_verifiedState().toJson());
        default:
          return http.Response('missing route', 404);
      }
    });

    _activate(
      adapter: adapter,
      client: client,
      journalPath: directory.path,
    );
    final states = <CommercePurchaserState>[];
    final subscription = Restage.commerce.states.listen(states.add);
    addTearDown(subscription.cancel);

    final result = await Restage.commerce.purchase(
      CommercePurchaseRequest(CommerceOfferId('offer.monthly')),
    );

    expect(result.status, CommerceActionStatusCode.pending);
    expect(adapter.queriedProductIds, <String>{'subscription.monthly'});
    expect(
        adapter.startedPurchasable?.applicationAccountToken, _appAccountToken);

    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.appStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'apple-transaction-1',
        storeVerificationData: 'signed.apple.transaction.jws',
        requiresDeviceCompletion: true,
      ),
    );

    await completion.future.timeout(_progressTimeout);

    expect(events, <String>['report', 'complete']);
    expect(reports, hasLength(1));
    expect(reports.single['store'], 'app_store');
    expect(reports.single['storeVerificationData'],
        'signed.apple.transaction.jws');
    expect(reports.single['storeTransactionId'], 'apple-transaction-1');
    expect(reports.single['appAnonymousToken'], _applicationToken);
    expect(reports.single.containsKey('intentId'), isFalse);
    expect(Restage.commerce.currentState.status,
        CommercePurchaserStateStatusCode.available);
    expect(Restage.commerce.currentState.entitlements.single.entitlementId,
        'subscription.monthly');
    expect(states.last, Restage.commerce.currentState);
  });

  for (final changeIdentity in <bool>[false, true]) {
    test(
        'retains successful Apple completion after ${changeIdentity ? 'identity change with independent owner callbacks' : 'acknowledgement write failure and duplicate callbacks'}',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('restage-engine-');
      addTearDown(() => _deleteAfterCommerceStops(directory));
      final clock = _HeldClock();
      final fileQueue = CommerceFileReportQueue(
        directoryPath: directory.path,
        clock: clock.now,
      );
      final CommerceReportQueue queue = changeIdentity
          ? fileQueue
          : _FailFirstAcknowledgementQueue(fileQueue);
      var token = _applicationToken;
      final reports = <Map<String, dynamic>>[];
      final adapter = _TestStoreAdapter(
        store: CommerceStore.appStore,
        products: const <CommerceStoreProduct>[],
        onComplete: (_) async {
          if (changeIdentity && reports.length == 1) {
            token = _secondApplicationToken;
            notifyRestageCommerceIdentityChanged();
          }
        },
      );
      addTearDown(adapter.close);
      _activate(
        adapter: adapter,
        client: MockClient((request) async {
          reports.add(jsonDecode(request.body) as Map<String, dynamic>);
          return _jsonResponse(_verifiedState().toJson());
        }),
        queueFactory: () async => queue,
        runtimeContextProvider: () => _context(
          fingerprint: 'completion-retry-scope',
          token: token,
        ),
        clock: clock.now,
      );
      adapter.emit(_applePendingTransaction);
      await _waitFor(() async {
        final retained = await queue.open();
        return retained.length == 1 && retained.single.retryAttempt == 1;
      }, label: 'finished transaction remains queued for local retry');
      expect(adapter.completionCalls, 1);
      expect(reports, hasLength(1));
      final retained = (await queue.open()).single;
      expect(retained.applicationAnonymousToken, _applicationToken);
      expect(retained.configurationFingerprint, 'completion-retry-scope');

      // Matching callbacks share the retained success. A changed anonymous
      // owner has its own report and completion obligation.
      adapter.emit(const _TestTransaction(
        store: CommerceStore.appStore,
        status: CommerceStoreTransactionStatus.restored,
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'apple-pending-transaction',
        storeVerificationData: 'pending.apple.transaction.jws',
        requiresDeviceCompletion: false,
      ));
      adapter.emit(_applePendingTransaction);
      if (changeIdentity) {
        await _waitFor(
          () async => reports.length == 2 && (await queue.open()).length == 1,
          label: 'independent owner reconciles during original report backoff',
        );
        expect(reports[1]['appAnonymousToken'], _secondApplicationToken);
        expect(
          Map<String, dynamic>.of(reports[1])
            ..remove('reportId')
            ..remove('appAnonymousToken'),
          Map<String, dynamic>.of(reports.first)
            ..remove('reportId')
            ..remove('appAnonymousToken'),
        );
        expect(reports[1]['reportId'], isNot(reports.first['reportId']));
        expect(adapter.completionCalls, 2);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(reports, hasLength(1));
      }
      // The retained report becomes due once its backoff has passed.
      clock.advance(commerceReportRetryDelay(1));
      await _waitFor(
        () async =>
            reports.length == (changeIdentity ? 3 : 2) &&
            (await queue.open()).isEmpty,
        label: 'local retry acknowledges the already-finished transaction',
      );
      expect(reports.last, reports.first);
      expect(adapter.completionCalls, changeIdentity ? 2 : 1);
    });
  }

  for (final variation in <String>[
    'same transaction',
    'observed before finish',
    'different owner',
    'different scope',
    'different product',
    'different proof',
    'different provider ID',
  ]) {
    test('Apple duplicate admission across acknowledgement: $variation',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('restage-engine-');
      addTearDown(() => _deleteAfterCommerceStops(directory));
      final temporary = _GatedAcknowledgementFile(
        File('${directory.path}/reports.json.tmp'),
      );
      final ready = File('${directory.path}/reports.json');
      final duplicateEnqueued = Completer<CommerceReportRecord>();
      final completionStarted = Completer<void>();
      final releaseCompletion = Completer<void>();
      final duplicateTokenStarted = Completer<void>();
      final duplicateToken = Completer<String>();
      var holdDuplicateToken = false;
      var token = _applicationToken;
      var fingerprint = 'ack-boundary-scope';
      final reports = <Map<String, dynamic>>[];
      final matching = variation == 'same transaction' ||
          variation == 'observed before finish';
      final adapter = _TestStoreAdapter(
        store: CommerceStore.appStore,
        products: const <CommerceStoreProduct>[],
        onComplete: (_) async {
          if (variation == 'observed before finish' && reports.length == 1) {
            completionStarted.complete();
            await releaseCompletion.future;
          }
        },
      );
      addTearDown(adapter.close);
      addTearDown(() {
        if (!temporary.release.isCompleted) temporary.release.complete();
        if (!releaseCompletion.isCompleted) releaseCompletion.complete();
        if (!duplicateToken.isCompleted) duplicateToken.complete(token);
      });
      await IOOverrides.runZoned(() async {
        final fileQueue =
            CommerceFileReportQueue(directoryPath: directory.path);
        final queue = _ObserveSecondEnqueueQueue(fileQueue, duplicateEnqueued);
        _activate(
          adapter: adapter,
          client: MockClient((request) async {
            reports.add(jsonDecode(request.body) as Map<String, dynamic>);
            return _jsonResponse(_verifiedState().toJson());
          }),
          queueFactory: () async => queue,
          runtimeContextProvider: () => CommerceRuntimeContext(
            configurationFingerprint: fingerprint,
            applicationAnonymousTokenProvider: () {
              if (!holdDuplicateToken) return Future<String>.value(token);
              if (!duplicateTokenStarted.isCompleted) {
                duplicateTokenStarted.complete();
              }
              return duplicateToken.future;
            },
          ),
        );
        adapter.emit(_applePendingTransaction);
        if (variation == 'observed before finish') {
          await completionStarted.future.timeout(_progressTimeout);
          holdDuplicateToken = true;
          adapter.emit(_applePendingTransaction);
          await duplicateTokenStarted.future.timeout(_progressTimeout);
          releaseCompletion.complete();
        }
        await temporary.acknowledgementStarted.future.timeout(_progressTimeout);
        expect(adapter.completionCalls, 1);
        final original = (await _publishedReports(directory.path)).single;
        expect(original.reportId, reports.single['reportId']);
        expect(original.applicationAnonymousToken, _applicationToken);
        expect(original.configurationFingerprint, 'ack-boundary-scope');
        if (variation == 'observed before finish') {
          duplicateToken.complete(_applicationToken);
        } else {
          if (variation == 'different owner') token = _secondApplicationToken;
          if (variation == 'different scope') fingerprint = 'independent-scope';
          adapter.emit(_TestTransaction(
            store: CommerceStore.appStore,
            status: CommerceStoreTransactionStatus.purchased,
            storeProductId: variation == 'different product'
                ? 'subscription.yearly'
                : _applePendingTransaction.storeProductId,
            storeTransactionId: variation == 'different provider ID'
                ? 'independent-apple-transaction'
                : _applePendingTransaction.storeTransactionId,
            storeVerificationData: variation == 'different proof'
                ? 'independent.apple.transaction.jws'
                : _applePendingTransaction.storeVerificationData,
            requiresDeviceCompletion: true,
          ));
        }
        // This observer delegates enqueue to the actual file queue before
        // signalling, proving it is queued behind the held atomic rename.
        final pending =
            await duplicateEnqueued.future.timeout(_progressTimeout);
        expect(pending.reportId, isNot(original.reportId));
        expect(
            (await _publishedReports(directory.path))
                .single
                .hasSameContents(original),
            isTrue);
        temporary.release.complete();
        await _waitFor(
          () async => reports.length == 2 && (await queue.open()).isEmpty,
          label: 'both actual journal admissions are reported and acknowledged',
        );
        expect(reports, hasLength(2));
        expect(reports[1]['reportId'], pending.reportId);
        expect(
            reports[1]['appAnonymousToken'], pending.applicationAnonymousToken);
        expect(reports[1]['storeProductId'], pending.storeProductId);
        expect(reports[1]['storeTransactionId'], pending.storeTransactionId);
        expect(
            reports[1]['storeVerificationData'], pending.storeVerificationData);
        expect(pending.configurationFingerprint, fingerprint);
        expect(adapter.completionCalls, matching ? 1 : 2,
            reason: matching
                ? 'an observed duplicate retains success across acknowledgement'
                : 'independent ownership, scope or evidence must not inherit success');
        expect(await _publishedReports(directory.path), isEmpty);
      }, createFile: (path) {
        if (path == temporary.inner.path) return temporary;
        if (path == ready.path) return ready;
        throw StateError('Unexpected journal file $path');
      });
    });
  }

  for (final variation in <String>[
    'same subject',
    'different owner',
    'different scope',
    'different product',
    'different proof',
    'different provider ID',
  ]) {
    test('Apple observation before first admission: $variation', () async {
      final directory =
          await Directory.systemTemp.createTemp('restage-engine-');
      addTearDown(() => _deleteAfterCommerceStops(directory));
      final queue = CommerceFileReportQueue(directoryPath: directory.path);
      var generation = 0;
      final heldToken = Completer<String>();
      final tokenStarted = Completer<void>();
      final reports = <Map<String, dynamic>>[];
      final adapter = _TestStoreAdapter(
        store: CommerceStore.appStore,
        products: const <CommerceStoreProduct>[],
      );
      addTearDown(adapter.close);
      addTearDown(() {
        if (!heldToken.isCompleted) heldToken.complete(_applicationToken);
      });
      final fresh = _TestTransaction(
        store: CommerceStore.appStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: variation == 'different product'
            ? 'subscription.yearly'
            : _applePendingTransaction.storeProductId,
        storeTransactionId: variation == 'different provider ID'
            ? 'other-apple-transaction'
            : _applePendingTransaction.storeTransactionId,
        storeVerificationData: variation == 'different proof'
            ? 'other.apple.transaction.jws'
            : _applePendingTransaction.storeVerificationData,
        requiresDeviceCompletion: true,
      );
      _activate(
        adapter: adapter,
        queueFactory: () async => queue,
        runtimeContextProvider: () {
          final savedGeneration = generation;
          return CommerceRuntimeContext(
            configurationFingerprint:
                variation == 'different scope' && savedGeneration == 1
                    ? 'fresh-scope'
                    : 'observed-scope',
            isCurrent: () => savedGeneration == generation,
            applicationAnonymousTokenProvider: () {
              if (savedGeneration == 0) {
                if (!tokenStarted.isCompleted) tokenStarted.complete();
                return heldToken.future;
              }
              return Future<String>.value(_applicationToken);
            },
          );
        },
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          // Observe through this queue's serialized operations: admission is
          // durable before any report can reach the transport.
          final durable = (await queue.open()).single;
          expect(durable.reportId, body['reportId']);
          expect(durable.applicationAnonymousToken, body['appAnonymousToken']);
          expect(durable.storeVerificationData, body['storeVerificationData']);
          expect(
            durable.configurationFingerprint,
            variation == 'different scope' && reports.isEmpty
                ? 'fresh-scope'
                : 'observed-scope',
          );
          reports.add(body);
          return _jsonResponse(_verifiedState().toJson());
        }),
      );
      adapter.emit(_applePendingTransaction);
      await tokenStarted.future.timeout(_progressTimeout);
      expect(await queue.open(), isEmpty);
      expect(adapter.completionCalls, isZero);
      generation += 1;
      notifyRestageCommerceConfigurationChanged();
      adapter.emit(fresh);
      await _waitFor(
        () async =>
            adapter.completionCalls == 1 && (await queue.open()).isEmpty,
        label: 'fresh owner admission finishes while original owner is held',
      );
      expect(reports, hasLength(1));
      final originalToken = variation == 'different owner'
          ? _secondApplicationToken
          : _applicationToken;
      if (variation == 'different scope') {
        generation += 1;
        notifyRestageCommerceConfigurationChanged();
      }
      heldToken.complete(originalToken);
      await _waitFor(
        () async => reports.length == 2 && (await queue.open()).isEmpty,
        label: 'reliable original owner admission settles after retirement',
      );
      expect(reports[0]['reportId'], isNot(reports[1]['reportId']));
      expect(reports[0]['appAnonymousToken'], _applicationToken);
      expect(reports[0]['storeProductId'], fresh.storeProductId);
      expect(reports[0]['storeTransactionId'], fresh.storeTransactionId);
      expect(reports[0]['storeVerificationData'], fresh.storeVerificationData);
      expect(reports[1]['appAnonymousToken'], originalToken);
      expect(reports[1]['storeProductId'],
          _applePendingTransaction.storeProductId);
      expect(reports[1]['storeTransactionId'],
          _applePendingTransaction.storeTransactionId);
      expect(reports[1]['storeVerificationData'],
          _applePendingTransaction.storeVerificationData);
      final matching = variation == 'same subject';
      expect(adapter.completionCalls, matching ? 1 : 2,
          reason: matching
              ? 'an already-observed admission shares subsequently created success'
              : 'independent saved subjects must not inherit completion');
      expect(await _publishedReports(directory.path), isEmpty);
      if (matching) {
        // Once both reports and their pending observations retire, a later
        // callback begins a new obligation rather than reading receipt history.
        adapter.emit(fresh);
        await _waitFor(
          () async => reports.length == 3 && (await queue.open()).isEmpty,
          label: 'later callback starts after all observations have retired',
        );
        expect(adapter.completionCalls, 2);
      }
    });
  }

  for (final originalOwner in <String>[
    _applicationToken,
    _secondApplicationToken,
  ]) {
    test(
        'unresolved Apple observation retains separate completion candidates for ${originalOwner == _applicationToken ? 'first' : 'second'} owner',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('restage-engine-');
      addTearDown(() => _deleteAfterCommerceStops(directory));
      final queue = CommerceFileReportQueue(directoryPath: directory.path);
      final heldToken = Completer<String>();
      final tokenStarted = Completer<void>();
      var generation = 0;
      var currentOwner = _applicationToken;
      final reports = <Map<String, dynamic>>[];
      final adapter = _TestStoreAdapter(
        store: CommerceStore.appStore,
        products: const <CommerceStoreProduct>[],
      );
      addTearDown(adapter.close);
      addTearDown(() {
        if (!heldToken.isCompleted) heldToken.complete(originalOwner);
      });
      _activate(
        adapter: adapter,
        queueFactory: () async => queue,
        runtimeContextProvider: () {
          final savedGeneration = generation;
          final savedOwner = currentOwner;
          return CommerceRuntimeContext(
            configurationFingerprint: 'owner-candidates-scope',
            isCurrent: () => generation == savedGeneration,
            applicationAnonymousTokenProvider: () {
              if (savedGeneration == 0) {
                if (!tokenStarted.isCompleted) tokenStarted.complete();
                return heldToken.future;
              }
              return Future<String>.value(savedOwner);
            },
          );
        },
        client: MockClient((request) async {
          reports.add(jsonDecode(request.body) as Map<String, dynamic>);
          return _jsonResponse(_verifiedState().toJson());
        }),
      );
      adapter.emit(_applePendingTransaction);
      await tokenStarted.future.timeout(_progressTimeout);
      expect(await queue.open(), isEmpty);
      for (final owner in <String>[
        _applicationToken,
        _secondApplicationToken,
      ]) {
        currentOwner = owner;
        generation += 1;
        notifyRestageCommerceConfigurationChanged();
        adapter.emit(_applePendingTransaction);
        await _waitFor(
          () async =>
              reports.length == generation && (await queue.open()).isEmpty,
          label:
              'independent saved owner finishes while original is unresolved',
        );
        expect(adapter.completionCalls, generation);
        expect(reports.last['appAnonymousToken'], owner);
      }
      heldToken.complete(originalOwner);
      await _waitFor(
        () async => reports.length == 3 && (await queue.open()).isEmpty,
        label: 'original owner selects its matching retained success',
      );
      expect(reports.map((report) => report['reportId']).toSet(), hasLength(3));
      expect(reports.last['appAnonymousToken'], originalOwner);
      for (final report in reports.skip(1)) {
        expect(
          Map<String, dynamic>.of(report)
            ..remove('reportId')
            ..remove('appAnonymousToken'),
          Map<String, dynamic>.of(reports.first)
            ..remove('reportId')
            ..remove('appAnonymousToken'),
        );
      }
      expect(adapter.completionCalls, 2,
          reason: 'unresolved ownership retains separate candidates without '
              'discarding either owner or merging their completion');
    });
  }

  test('live Apple observations share future completion after reconvergence',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final temporary = _GatedAcknowledgementFile(
      File('${directory.path}/reports.json.tmp'),
    );
    final ready = File('${directory.path}/reports.json');
    final firstToken = Completer<String>();
    final secondToken = Completer<String>();
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    final freshResponseStarted = Completer<void>();
    final releaseFreshResponse = Completer<void>();
    final converged = Completer<CommerceReportRecord>();
    var generation = 0;
    var holdFirst = false;
    final reports = <Map<String, dynamic>>[];
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    addTearDown(() {
      if (!temporary.release.isCompleted) temporary.release.complete();
      if (!firstToken.isCompleted) firstToken.complete(_applicationToken);
      if (!secondToken.isCompleted) secondToken.complete(_applicationToken);
      if (!releaseFreshResponse.isCompleted) releaseFreshResponse.complete();
    });
    await IOOverrides.runZoned(() async {
      final fileQueue = CommerceFileReportQueue(directoryPath: directory.path);
      final queue = _ObserveCompletedEnqueueQueue(fileQueue, 3, converged);
      _activate(
        adapter: adapter,
        queueFactory: () async => queue,
        runtimeContextProvider: () {
          final savedGeneration = generation;
          return CommerceRuntimeContext(
            configurationFingerprint: 'shared-completion-scope',
            isCurrent: () => savedGeneration == generation,
            applicationAnonymousTokenProvider: () {
              if (savedGeneration == 0 && holdFirst) {
                if (!firstStarted.isCompleted) firstStarted.complete();
                return firstToken.future;
              }
              if (savedGeneration == 1) {
                if (!secondStarted.isCompleted) secondStarted.complete();
                return secondToken.future;
              }
              return Future<String>.value(_applicationToken);
            },
          );
        },
        client: MockClient((request) async {
          reports.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (reports.length == 2) {
            freshResponseStarted.complete();
            await releaseFreshResponse.future;
          }
          return _jsonResponse(_verifiedState().toJson());
        }),
      );
      adapter.emit(const _TestTransaction(
        store: CommerceStore.appStore,
        status: CommerceStoreTransactionStatus.restored,
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'apple-pending-transaction',
        storeVerificationData: 'pending.apple.transaction.jws',
        requiresDeviceCompletion: false,
      ));
      await temporary.acknowledgementStarted.future.timeout(_progressTimeout);
      final original = (await _publishedReports(directory.path)).single;
      holdFirst = true;
      adapter.emit(_applePendingTransaction);
      await firstStarted.future.timeout(_progressTimeout);
      generation = 1;
      notifyRestageCommerceConfigurationChanged();
      adapter.emit(_applePendingTransaction);
      await secondStarted.future.timeout(_progressTimeout);
      temporary.release.complete();
      await _waitFor(() async => (await queue.open()).isEmpty,
          label: 'original unfulfilled row retires with two live observations');
      expect(adapter.completionCalls, isZero);
      generation = 2;
      notifyRestageCommerceConfigurationChanged();
      adapter.emit(_applePendingTransaction);
      await freshResponseStarted.future.timeout(_progressTimeout);
      firstToken.complete(_applicationToken);
      final deduplicated = await converged.future.timeout(_progressTimeout);
      expect(deduplicated.reportId, reports[1]['reportId']);
      expect((await queue.open()).single.hasSameContents(deduplicated), isTrue);
      // The completed enqueue and this queue observation let the engine finish
      // connecting the admission before its verified response is released.
      releaseFreshResponse.complete();
      await _waitFor(
        () async =>
            adapter.completionCalls == 1 && (await queue.open()).isEmpty,
        label: 'fresh row finishes after the first old observation converges',
      );
      secondToken.complete(_applicationToken);
      await _waitFor(
        () async => reports.length == 3 && (await queue.open()).isEmpty,
        label:
            'second old observation inherits future success after retirement',
      );
      expect(reports.map((report) => report['reportId']).toSet(), hasLength(3));
      for (final report in reports.skip(1)) {
        expect(Map<String, dynamic>.of(report)..remove('reportId'),
            Map<String, dynamic>.of(reports[0])..remove('reportId'));
      }
      expect(original.applicationAnonymousToken, _applicationToken);
      expect(original.configurationFingerprint, 'shared-completion-scope');
      expect(adapter.completionCalls, 1,
          reason: 'live observations share future success when their report '
              'entries converge before completion');
      expect(await _publishedReports(directory.path), isEmpty);
    }, createFile: (path) {
      if (path == temporary.inner.path) return temporary;
      if (path == ready.path) return ready;
      throw StateError('Unexpected journal file $path');
    });
  });

  for (final initiallyRequiresCompletion in <bool>[false, true]) {
    test(
        'detached Apple admission retains completion through ${initiallyRequiresCompletion ? 'unchanged native instance' : 'preferred native instance update'}',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('restage-engine-');
      addTearDown(() => _deleteAfterCommerceStops(directory));
      var now = DateTime.now().toUtc();
      final fileQueue = CommerceFileReportQueue(
        directoryPath: directory.path,
        clock: () => now,
      );
      final freshEnqueued = Completer<CommerceReportRecord>();
      final queue = _ObserveSecondEnqueueQueue(fileQueue, freshEnqueued);
      var generation = 0;
      var holdToken = false;
      final heldToken = Completer<String>();
      final tokenStarted = Completer<void>();
      final reports = <Map<String, dynamic>>[];
      final completedInstances = <CommerceStoreTransaction>[];
      final adapter = _TestStoreAdapter(
        store: CommerceStore.appStore,
        products: const <CommerceStoreProduct>[],
        onComplete: (transaction) async => completedInstances.add(transaction),
      );
      addTearDown(adapter.close);
      addTearDown(() {
        if (!heldToken.isCompleted) heldToken.complete(_applicationToken);
      });
      _activate(
        adapter: adapter,
        queueFactory: () async => queue,
        runtimeContextProvider: () {
          final savedGeneration = generation;
          return CommerceRuntimeContext(
            configurationFingerprint: 'shared-completion-scope',
            isCurrent: () => generation == savedGeneration,
            applicationAnonymousTokenProvider: () {
              if (holdToken) {
                if (!tokenStarted.isCompleted) tokenStarted.complete();
                return heldToken.future;
              }
              return Future<String>.value(_applicationToken);
            },
          );
        },
        client: MockClient((request) async {
          reports.add(jsonDecode(request.body) as Map<String, dynamic>);
          return _jsonResponse(
              (reports.length == 1 ? _pendingState() : _verifiedState())
                  .toJson());
        }),
      );
      final initial = _TestTransaction(
        store: CommerceStore.appStore,
        status: CommerceStoreTransactionStatus.restored,
        storeProductId: _applePendingTransaction.storeProductId,
        storeTransactionId: _applePendingTransaction.storeTransactionId,
        storeVerificationData: _applePendingTransaction.storeVerificationData,
        requiresDeviceCompletion: initiallyRequiresCompletion,
      );
      final waiting = _TestTransaction(
        store: CommerceStore.appStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: _applePendingTransaction.storeProductId,
        storeTransactionId: _applePendingTransaction.storeTransactionId,
        storeVerificationData: _applePendingTransaction.storeVerificationData,
        requiresDeviceCompletion: true,
      );
      final preferred = _TestTransaction(
        store: CommerceStore.appStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: _applePendingTransaction.storeProductId,
        storeTransactionId: _applePendingTransaction.storeTransactionId,
        storeVerificationData: _applePendingTransaction.storeVerificationData,
        requiresDeviceCompletion: true,
      );
      adapter.emit(initial);
      await _waitFor(() async {
        final retained = await queue.open();
        return retained.length == 1 && retained.single.retryAttempt == 1;
      }, label: 'initial pending report is retained');
      final original = (await queue.open()).single;
      expect(reports, hasLength(1));
      expect(adapter.completionCalls, isZero);

      holdToken = true;
      adapter.emit(waiting);
      await tokenStarted.future.timeout(_progressTimeout);
      generation += 1;
      holdToken = false;
      notifyRestageCommerceConfigurationChanged();
      adapter.emit(preferred);
      await freshEnqueued.future.timeout(_progressTimeout);
      // The same queue's serialized observation waits for the fresh enqueue;
      // it has deduplicated to the original owner, scope and provider evidence.
      expect((await queue.open()).single.hasSameContents(original), isTrue);
      expect(adapter.completionCalls, isZero);
      now = now.add(const Duration(minutes: 1));
      notifyRestageCommerceConfigurationChanged();
      await _waitFor(
        () async =>
            adapter.completionCalls == 1 && (await queue.open()).isEmpty,
        label:
            'preferred instance is finished and original report acknowledged',
      );
      expect(reports, hasLength(2));
      expect(reports[1], reports[0]);
      expect(completedInstances.single,
          same(initiallyRequiresCompletion ? initial : preferred));

      // The captured owner remains reliable after its admission detaches.
      // It still needs the shared success fact after the original row retires.
      heldToken.complete(_applicationToken);
      await _waitFor(
        () async => reports.length == 3 && (await queue.open()).isEmpty,
        label: 'detached original-owner admission reconciles after retirement',
      );
      expect(reports.map((report) => report['reportId']).toSet(), hasLength(2));
      expect(reports[2]['reportId'], isNot(original.reportId));
      expect(
        Map<String, dynamic>.of(reports[2])..remove('reportId'),
        Map<String, dynamic>.of(reports[0])..remove('reportId'),
      );
      expect(original.applicationAnonymousToken, _applicationToken);
      expect(original.configurationFingerprint, 'shared-completion-scope');
      expect(adapter.completionCalls, 1,
          reason: 'preferred-instance updates must preserve the shared success '
              'seen by an already-observed detached admission');
      expect(completedInstances, hasLength(1));
      expect(await _publishedReports(directory.path), isEmpty);
    });
  }

  test(
      'detached Apple admission shares an unfulfilled entry after acknowledgement',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final temporary = _GatedAcknowledgementFile(
      File('${directory.path}/reports.json.tmp'),
    );
    final ready = File('${directory.path}/reports.json');
    final freshEnqueued = Completer<CommerceReportRecord>();
    final heldToken = Completer<String>();
    final tokenStarted = Completer<void>();
    var generation = 0;
    var holdToken = false;
    final reports = <Map<String, dynamic>>[];
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    addTearDown(() {
      if (!temporary.release.isCompleted) temporary.release.complete();
      if (!heldToken.isCompleted) heldToken.complete(_applicationToken);
    });
    await IOOverrides.runZoned(() async {
      final fileQueue = CommerceFileReportQueue(directoryPath: directory.path);
      final queue = _ObserveSecondEnqueueQueue(fileQueue, freshEnqueued);
      _activate(
        adapter: adapter,
        queueFactory: () async => queue,
        runtimeContextProvider: () {
          final savedGeneration = generation;
          return CommerceRuntimeContext(
            configurationFingerprint: 'shared-completion-scope',
            isCurrent: () => generation == savedGeneration,
            applicationAnonymousTokenProvider: () {
              if (holdToken) {
                if (!tokenStarted.isCompleted) tokenStarted.complete();
                return heldToken.future;
              }
              return Future<String>.value(_applicationToken);
            },
          );
        },
        client: MockClient((request) async {
          reports.add(jsonDecode(request.body) as Map<String, dynamic>);
          return _jsonResponse(_verifiedState().toJson());
        }),
      );
      adapter.emit(const _TestTransaction(
        store: CommerceStore.appStore,
        status: CommerceStoreTransactionStatus.restored,
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'apple-pending-transaction',
        storeVerificationData: 'pending.apple.transaction.jws',
        requiresDeviceCompletion: false,
      ));
      await temporary.acknowledgementStarted.future.timeout(_progressTimeout);
      final original = (await _publishedReports(directory.path)).single;
      expect(adapter.completionCalls, isZero);
      holdToken = true;
      adapter.emit(_applePendingTransaction);
      await tokenStarted.future.timeout(_progressTimeout);
      generation += 1;
      holdToken = false;
      notifyRestageCommerceConfigurationChanged();
      adapter.emit(_applePendingTransaction);
      final fresh = await freshEnqueued.future.timeout(_progressTimeout);
      expect(
          (await _publishedReports(directory.path))
              .single
              .hasSameContents(original),
          isTrue);
      temporary.release.complete();
      await _waitFor(
        () async => reports.length == 2 && (await queue.open()).isEmpty,
        label: 'fresh report fulfills the shared obligation after retirement',
      );
      expect(reports[1]['reportId'], fresh.reportId);
      expect(adapter.completionCalls, 1);
      heldToken.complete(_applicationToken);
      await _waitFor(
        () async => reports.length == 3 && (await queue.open()).isEmpty,
        label: 'old pending owner sees success through the new report entry',
      );
      expect(reports.map((report) => report['reportId']).toSet(), hasLength(3));
      for (final report in reports.skip(1)) {
        expect(Map<String, dynamic>.of(report)..remove('reportId'),
            Map<String, dynamic>.of(reports[0])..remove('reportId'));
      }
      expect(original.applicationAnonymousToken, _applicationToken);
      expect(original.configurationFingerprint, 'shared-completion-scope');
      expect(adapter.completionCalls, 1,
          reason: 'new report entries must preserve shared unfulfilled facts '
              'until already-observed admissions settle');
      expect(await _publishedReports(directory.path), isEmpty);
    }, createFile: (path) {
      if (path == temporary.inner.path) return temporary;
      if (path == ready.path) return ready;
      throw StateError('Unexpected journal file $path');
    });
  });

  test('retries a genuine Apple device completion exception', () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    var completionAttempts = 0;
    var successfulCompletions = 0;
    final reports = <Map<String, dynamic>>[];
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
      onComplete: (_) async {
        completionAttempts += 1;
        if (completionAttempts == 1) throw StateError('provider finish failed');
        successfulCompletions += 1;
      },
    );
    addTearDown(adapter.close);
    _activate(
      adapter: adapter,
      client: MockClient((request) async {
        reports.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _jsonResponse(_verifiedState().toJson());
      }),
      queueFactory: () async => queue,
    );
    adapter.emit(_applePendingTransaction);
    await _waitFor(
      () async => reports.length == 2 && (await queue.open()).isEmpty,
      label: 'provider finish is retried before acknowledgement',
    );
    expect(reports[1], reports[0]);
    expect(adapter.completionCalls, 2);
    expect(successfulCompletions, 1);
  });

  test('honors effective report backoff when retry persistence fails',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final obstruction = Directory('${directory.path}/reports.json.tmp');
    final reports = <Map<String, dynamic>>[];
    final secondReport = Completer<void>();
    final thirdReport = Completer<void>();
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    _activate(
      adapter: adapter,
      client: MockClient((request) async {
        reports.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (reports.length == 1) await obstruction.create();
        if (reports.length == 2) secondReport.complete();
        if (reports.length == 3) thirdReport.complete();
        return _jsonResponse(
            (reports.length < 3 ? _pendingState() : _verifiedState()).toJson());
      }),
      queueFactory: () async => queue,
    );
    adapter.emit(_applePendingTransaction);
    await _waitFor(() async {
      final retained = await queue.open();
      return retained.length == 1 && retained.single.retryAttempt == 1;
    }, label: 'failed schedule write retains effective first backoff');
    final firstRetry = (await queue.open()).single;
    expect(await queue.due(), isEmpty);
    expect((await _publishedReports(directory.path)).single.retryAttempt, 0);
    notifyRestageCommerceConfigurationChanged();
    notifyRestageCommerceForegrounded();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(reports, hasLength(1));
    expect(adapter.completionCalls, isZero);
    expect((await queue.open()).single.hasSameContents(firstRetry), isTrue);

    await obstruction.delete();
    await secondReport.future.timeout(_progressTimeout);
    await _waitFor(() async {
      final published = await _publishedReports(directory.path);
      return published.length == 1 && published.single.retryAttempt == 2;
    }, label: 'recovered storage persists the accumulated retry attempt');
    final secondRetry = (await queue.open()).single;
    expect(
        secondRetry
            .hasSameContents(firstRetry.retryAt(secondRetry.nextRetryAt)),
        isTrue);
    expect(secondRetry.nextRetryAt.difference(firstRetry.nextRetryAt),
        greaterThanOrEqualTo(const Duration(seconds: 2)));
    notifyRestageCommerceConfigurationChanged();
    notifyRestageCommerceForegrounded();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(reports, hasLength(2));
    expect(await queue.due(), isEmpty);

    await thirdReport.future.timeout(_progressTimeout);
    await _waitFor(() async => (await queue.open()).isEmpty,
        label: 'recovered storage acknowledges the verified report');
    expect(reports, hasLength(3));
    expect(reports[1], reports[0]);
    expect(reports[2], reports[0]);
    expect(await _publishedReports(directory.path), isEmpty);
    expect(adapter.completionCalls, 1);
  });

  test('never completes a Google transaction on the device', () async {
    final reportSeen = Completer<void>();
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
      onComplete: (_) async => fail('Google completion must stay server-owned'),
    );
    addTearDown(adapter.close);
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final client = MockClient((request) async {
      if (request.url.path == '/sdk/v1/commerce/reports') {
        if (!reportSeen.isCompleted) reportSeen.complete();
        return _jsonResponse(_verifiedState().toJson());
      }
      return http.Response('missing route', 404);
    });

    _activate(
      adapter: adapter,
      client: client,
      journalPath: directory.path,
    );
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.playStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'order-1',
        storeVerificationData: 'google-purchase-token',
        requiresDeviceCompletion: true,
      ),
    );

    await reportSeen.future.timeout(_progressTimeout);
    await Future<void>.delayed(Duration.zero);

    expect(adapter.completionCalls, isZero);
    expect(Restage.commerce.currentState.status,
        CommercePurchaserStateStatusCode.available);
  });

  test(
      'declines a non-subscription server resolution before querying the store',
      () async {
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _jsonResponse(
        CommerceIntentResponse(
          intentId: body['intentId']! as String,
          status: 'ready',
          resolved: CommerceResolvedPurchasable(
            storeProductId: 'one-time.product',
            productKind: 'nonConsumable',
            appAccountToken: _appAccountToken,
          ),
        ).toJson(),
      );
    });

    _activate(
      adapter: adapter,
      client: client,
      journalPath: directory.path,
    );
    final result = await Restage.commerce.purchase(
      CommercePurchaseRequest(CommerceOfferId('offer.one-time')),
    );

    expect(result.status, CommerceActionStatusCode.failed);
    expect(result.failureCode, CommerceFailureCode.unsupportedCapability);
    expect(adapter.queryCalls, isZero);
    expect(adapter.startCalls, isZero);
  });

  test('declines an offer signature the SPI cannot transport', () async {
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _jsonResponse(
        CommerceIntentResponse(
          intentId: body['intentId']! as String,
          status: 'ready',
          resolved: CommerceResolvedPurchasable(
            storeProductId: 'subscription.monthly',
            productKind: 'autoRenewableSubscription',
            appAccountToken: _appAccountToken,
            offerSignature: const OfferSignatureResponse(
              scheme: OfferSignatureScheme.legacy,
              keyIdentifier: 'key',
              nonce: 'nonce',
              timestampMs: 1,
              signatureBase64: 'signature',
            ),
          ),
        ).toJson(),
      );
    });

    _activate(
      adapter: adapter,
      client: client,
      journalPath: directory.path,
    );
    final result = await Restage.commerce.purchase(
      CommercePurchaseRequest(CommerceOfferId('offer.signed')),
    );

    expect(result.status, CommerceActionStatusCode.failed);
    expect(result.failureCode, CommerceFailureCode.unsupportedCapability);
    expect(adapter.queryCalls, isZero);
    expect(adapter.startCalls, isZero);
  });

  test('does not send or complete when the journal write fails', () async {
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
      onComplete: (_) async => fail('completion requires a durable report'),
    );
    addTearDown(adapter.close);
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    await queue.open();
    await Directory('${directory.path}/reports.json.tmp').create();
    var reportRequests = 0;
    final client = MockClient((request) async {
      reportRequests += 1;
      return _jsonResponse(_verifiedState().toJson());
    });

    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => queue,
    );
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.appStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'apple-transaction-2',
        storeVerificationData: 'signed.apple.transaction.jws',
        requiresDeviceCompletion: true,
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(reportRequests, isZero);
    expect(adapter.completionCalls, isZero);
    expect(await queue.due(), isEmpty);
  });

  test('retains Apple evidence when a non-2xx response claims verification',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    final reportSeen = Completer<void>();
    _activate(
      adapter: adapter,
      client: MockClient((request) async {
        expect(request.url.path, '/sdk/v1/commerce/reports');
        expect(request.headers['Authorization'], 'Bearer rs_pk_test');
        if (!reportSeen.isCompleted) reportSeen.complete();
        return _jsonResponse(_verifiedState().toJson(), statusCode: 409);
      }),
      queueFactory: () async => queue,
    );
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.appStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'non-success-order',
        storeVerificationData: 'non-success-jws',
        requiresDeviceCompletion: true,
      ),
    );
    await reportSeen.future.timeout(_progressTimeout);
    await _waitFor(
      () async {
        final records = await queue.open();
        return records.length == 1 && records.single.retryAttempt >= 1;
      },
      label: 'non-success report remains durable and retryable',
    );
    expect(adapter.completionCalls, isZero);
    expect(Restage.commerce.currentState.entitlements, isEmpty);
  });

  test('retries an HTTP 409 pending report after restart with its report id',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final firstAdapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(firstAdapter.close);
    final firstQueue = CommerceFileReportQueue(directoryPath: directory.path);
    final firstReport = Completer<Map<String, dynamic>>();
    final firstClient = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (!firstReport.isCompleted) firstReport.complete(body);
      return _jsonResponse(_pendingState().toJson(), statusCode: 409);
    });

    _activate(
      adapter: firstAdapter,
      client: firstClient,
      queueFactory: () async => firstQueue,
    );
    firstAdapter.emit(
      const _TestTransaction(
        store: CommerceStore.playStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'order-2',
        storeVerificationData: 'restart-token',
        requiresDeviceCompletion: false,
      ),
    );
    final firstBody = await firstReport.future.timeout(_progressTimeout);
    await _waitFor(
      () async {
        final records = await firstQueue.open();
        return records.length == 1 && records.single.retryAttempt >= 1;
      },
      label: 'HTTP 409 report is retained for retry',
    );

    Restage.debugReset();

    final secondAdapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(secondAdapter.close);
    final secondQueue = CommerceFileReportQueue(directoryPath: directory.path);
    final secondReport = Completer<Map<String, dynamic>>();
    final secondClient = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (!secondReport.isCompleted) secondReport.complete(body);
      return _jsonResponse(_verifiedState().toJson());
    });
    _activate(
      adapter: secondAdapter,
      client: secondClient,
      queueFactory: () async => secondQueue,
    );

    final secondBody = await secondReport.future.timeout(_progressTimeout);

    expect(secondBody['reportId'], firstBody['reportId']);
    await _waitFor(
      () async => (await secondQueue.open()).isEmpty,
      label: 'HTTP 409 report is acknowledged after verification',
    );
    expect(Restage.commerce.currentState.status,
        CommercePurchaserStateStatusCode.available);
  });

  test('keeps a pending Apple report through restart until verified finish',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final firstAdapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
      onComplete: (_) async => fail('a pending report must not finish Apple'),
    );
    addTearDown(firstAdapter.close);
    final firstQueue = CommerceFileReportQueue(directoryPath: directory.path);
    final firstReport = Completer<Map<String, dynamic>>();
    final firstClient = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (!firstReport.isCompleted) firstReport.complete(body);
      return _jsonResponse(_pendingState().toJson());
    });

    _activate(
      adapter: firstAdapter,
      client: firstClient,
      queueFactory: () async => firstQueue,
    );
    firstAdapter.emit(_applePendingTransaction);
    final firstBody = await firstReport.future.timeout(_progressTimeout);
    await _waitFor(() async {
      final records = await firstQueue.open();
      return records.length == 1 && records.single.retryAttempt >= 1;
    }, label: 'pending report is retained');
    expect(firstAdapter.completionCalls, isZero);

    Restage.debugReset();

    final verified = Completer<void>();
    final secondAdapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
      onComplete: (_) async {
        if (!verified.isCompleted) verified.complete();
      },
    );
    addTearDown(secondAdapter.close);
    final secondQueue = CommerceFileReportQueue(directoryPath: directory.path);
    final secondReport = Completer<Map<String, dynamic>>();
    final secondClient = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (!secondReport.isCompleted) secondReport.complete(body);
      return _jsonResponse(_verifiedState().toJson());
    });
    _activate(
      adapter: secondAdapter,
      client: secondClient,
      queueFactory: () async => secondQueue,
    );
    secondAdapter.emit(_applePendingTransaction);

    final secondBody = await secondReport.future.timeout(_progressTimeout);
    await verified.future.timeout(_progressTimeout);

    expect(secondBody['reportId'], firstBody['reportId']);
    expect(secondAdapter.completionCalls, 1);
    await _waitFor(
      () async => (await secondQueue.open()).isEmpty,
      label: 'verified report is acknowledged',
    );
  });

  test('projects a refreshed purchaser state and emits it', () async {
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    Map<String, dynamic>? requestBody;
    final client = MockClient((request) async {
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return _jsonResponse(
        CommercePurchaserStateResponse(
          status: 'stale',
          entitlements: <EntitlementSummary>[
            EntitlementSummary(
              entitlementId: 'subscription.monthly',
              status: 'active',
              productId: 'subscription.monthly',
              source: 'clientReport',
            ),
          ],
          retrievedAt: DateTime.utc(2026, 9, 5),
        ).toJson(),
      );
    });
    _activate(
      adapter: adapter,
      client: client,
      journalPath: directory.path,
      usesPurchaserStateHandler: true,
    );
    final states = <CommercePurchaserState>[];
    final subscription = Restage.commerce.states.listen(states.add);
    addTearDown(subscription.cancel);

    final state = await Restage.commerce.refresh();

    expect(requestBody?['appAnonymousToken'], _applicationToken);
    expect(requestBody?['knownStoreTransactionIds'], isEmpty);
    expect(state.status, CommercePurchaserStateStatusCode.stale);
    expect(state.entitlements.single.status, 'active');
    expect(states.last, state);
  });
  test('admits later provider evidence while report HTTP is stalled', () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    final firstRequest = Completer<void>();
    final release = Completer<http.Response>();
    final client = MockClient((request) async {
      if (!firstRequest.isCompleted) firstRequest.complete();
      return release.future;
    });

    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => queue,
    );
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.playStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.first',
        storeTransactionId: 'order-first',
        storeVerificationData: 'token-first',
        requiresDeviceCompletion: false,
      ),
    );
    await firstRequest.future.timeout(_progressTimeout);
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.playStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.second',
        storeTransactionId: 'order-second',
        storeVerificationData: 'token-second',
        requiresDeviceCompletion: false,
      ),
    );

    await _waitFor(
      () async => (await queue.open()).length == 2,
      label: 'both reports durable while the first HTTP attempt is held',
    );
    expect(await queue.open(), hasLength(2));

    Restage.debugReset();
    release.complete(http.Response('unavailable', 503));
  });

  test('admits provider evidence while a native presentation is unresolved',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final presentation = Completer<bool>();
    final reportRelease = Completer<http.Response>();
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[
        _TestStoreProduct(
          store: CommerceStore.appStore,
          storeProductId: 'subscription.monthly',
        ),
      ],
      onStartPurchase: (_) => presentation.future,
    );
    addTearDown(adapter.close);
    final client = MockClient((request) async {
      switch (request.url.path) {
        case '/sdk/v1/commerce/intents':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return _jsonResponse(
            CommerceIntentResponse(
              intentId: body['intentId']! as String,
              status: 'ready',
              resolved: CommerceResolvedPurchasable(
                storeProductId: 'subscription.monthly',
                productKind: 'autoRenewableSubscription',
                appAccountToken: _appAccountToken,
              ),
            ).toJson(),
          );
        case '/sdk/v1/commerce/reports':
          return reportRelease.future;
        default:
          return http.Response('missing route', 404);
      }
    });

    _activate(
        adapter: adapter, client: client, queueFactory: () async => queue);
    final purchase = Restage.commerce.purchase(
      CommercePurchaseRequest(CommerceOfferId('offer.monthly')),
    );
    await _waitFor(() async => adapter.startCalls == 1);
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.appStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'apple-presentation-transaction',
        storeVerificationData: 'presentation.transaction.jws',
        requiresDeviceCompletion: false,
      ),
    );

    await _waitFor(
      () async => (await queue.open()).length == 1,
      label: 'report durable while native purchase is unresolved',
    );
    presentation.complete(false);
    expect(
      (await purchase).status,
      CommerceActionStatusCode.notPresented,
    );

    Restage.debugReset();
    reportRelease.complete(http.Response('unavailable', 503));
  });

  test('times out a report attempt and retries the durable report unchanged',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final firstAttempt = Completer<http.Response>();
    final reports = <Map<String, dynamic>>[];
    final completed = Completer<void>();
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
      onComplete: (_) async {
        if (!completed.isCompleted) completed.complete();
      },
    );
    addTearDown(adapter.close);
    final client = MockClient((request) async {
      reports.add(jsonDecode(request.body) as Map<String, dynamic>);
      return reports.length == 1
          ? firstAttempt.future
          : _jsonResponse(_verifiedState().toJson());
    });

    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => queue,
      networkAttemptTimeout: const Duration(milliseconds: 25),
    );
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.appStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'apple-timeout-transaction',
        storeVerificationData: 'timeout.transaction.jws',
        requiresDeviceCompletion: true,
      ),
    );

    await _waitFor(
      () async {
        final records = await queue.open();
        return records.length == 1 && records.single.retryAttempt == 1;
      },
      label: 'timed out report remains durable',
    );
    expect(adapter.completionCalls, isZero);
    await completed.future.timeout(_progressTimeout);

    expect(reports, hasLength(2));
    expect(reports[1]['reportId'], reports[0]['reportId']);
    expect(reports[1]['appAnonymousToken'], reports[0]['appAnonymousToken']);
    await _waitFor(
      () async => (await queue.open()).isEmpty,
      label: 'verified retry is acknowledged',
    );
    firstAttempt.complete(http.Response('unavailable', 503));
  });

  test('retries a failed journal write without another store event', () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    await queue.open();
    final obstruction = Directory('${directory.path}/reports.json.tmp');
    await obstruction.create();
    final completed = Completer<void>();
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
      onComplete: (_) async {
        if (!completed.isCompleted) completed.complete();
      },
    );
    addTearDown(adapter.close);
    var reports = 0;
    final client = MockClient((request) async {
      reports += 1;
      return _jsonResponse(_verifiedState().toJson());
    });

    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => queue,
    );
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.appStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'apple-retry-write',
        storeVerificationData: 'retry.write.transaction.jws',
        requiresDeviceCompletion: true,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(reports, isZero);
    expect(adapter.completionCalls, isZero);

    await obstruction.delete();
    await completed.future.timeout(_progressTimeout);

    expect(reports, 1);
    expect(adapter.completionCalls, 1);
    await _waitFor(
      () async => (await queue.open()).isEmpty,
      label: 'verified report is acknowledged after recovered write',
    );
  });

  test('reopens a failed queue initialization without store redelivery',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    var queueAvailable = false;
    var queueFactoryCalls = 0;
    final reportSeen = Completer<void>();
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    final client = MockClient((request) async {
      if (!reportSeen.isCompleted) reportSeen.complete();
      return _jsonResponse(_verifiedState().toJson());
    });

    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async {
        queueFactoryCalls += 1;
        if (!queueAvailable) throw StateError('journal unavailable');
        return queue;
      },
    );
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.playStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'queue-init-order',
        storeVerificationData: 'queue-init-token',
        requiresDeviceCompletion: false,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(queueFactoryCalls, greaterThanOrEqualTo(1));

    queueAvailable = true;
    await reportSeen.future.timeout(_progressTimeout);

    expect(queueFactoryCalls, greaterThanOrEqualTo(2));
    await _waitFor(
      () async => (await queue.open()).isEmpty,
      label: 'report from reopened journal is acknowledged',
    );
  });

  test(
      'retries a transient anonymous-token resolution without store redelivery',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    var tokenAvailable = false;
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final reportSeen = Completer<Map<String, dynamic>>();
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (!reportSeen.isCompleted) reportSeen.complete(body);
      return _jsonResponse(_verifiedState().toJson());
    });

    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => queue,
      runtimeContextProvider: () => CommerceRuntimeContext(
        configurationFingerprint: 'token-retry-scope',
        applicationAnonymousTokenProvider: () async =>
            tokenAvailable ? _applicationToken : null,
      ),
    );
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.playStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'token-retry-order',
        storeVerificationData: 'token-retry-provider-token',
        requiresDeviceCompletion: false,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(reportSeen.isCompleted, isFalse);

    tokenAvailable = true;
    final body = await reportSeen.future.timeout(_progressTimeout);

    expect(body['appAnonymousToken'], _applicationToken);
    await _waitFor(
      () async => (await queue.open()).isEmpty,
      label: 'token-retry report is acknowledged',
    );
  });

  test('keeps retained evidence in its configured transport scope', () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    var generation = 0;
    var fingerprint = 'scope-a';
    CommerceRuntimeContext? contextProvider() {
      final capturedGeneration = generation;
      final capturedFingerprint = fingerprint;
      return _context(
        fingerprint: capturedFingerprint,
        token: _applicationToken,
        isCurrent: () => generation == capturedGeneration,
      );
    }

    var firstScopeCalls = 0;
    var acknowledgeFirstScope = false;
    var wrongScopeCalls = 0;
    final firstClient = RestageRpcClient(
      baseUrl: 'https://app-a.example.com',
      apiKey: 'app-a-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/purchaser-state')) {
          return _jsonResponse(
            _purchaserState(entitlements: const <EntitlementSummary>[])
                .toJson(),
          );
        }
        firstScopeCalls += 1;
        return acknowledgeFirstScope
            ? _jsonResponse(_verifiedState().toJson())
            : http.Response('retry', 503);
      }),
    );
    final secondClient = RestageRpcClient(
      baseUrl: 'https://app-b.example.com',
      apiKey: 'app-b-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/purchaser-state')) {
          return _jsonResponse(
            _purchaserState(entitlements: const <EntitlementSummary>[])
                .toJson(),
          );
        }
        wrongScopeCalls += 1;
        return _jsonResponse(_verifiedState().toJson());
      }),
    );
    var activeClient = firstClient;
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);

    _activate(
      adapter: adapter,
      client: MockClient((_) async => http.Response('', 500)),
      queueFactory: () async => queue,
      runtimeContextProvider: contextProvider,
      rpcClientProvider: () => activeClient,
    );
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.playStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'scope-order',
        storeVerificationData: 'scope-token',
        requiresDeviceCompletion: false,
      ),
    );
    await _waitFor(
      () async {
        final records = await queue.open();
        return records.length == 1 && records.single.retryAttempt == 1;
      },
      label: 'first scope report retained for retry',
    );
    expect((await queue.open()).single.configurationFingerprint, 'scope-a');

    generation += 1;
    fingerprint = 'scope-b';
    activeClient = secondClient;
    notifyRestageCommerceConfigurationChanged();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    notifyRestageCommerceConfigurationChanged();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(wrongScopeCalls, isZero);
    expect(await queue.open(), hasLength(1));

    Restage.debugReset();
    final restartedAdapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(restartedAdapter.close);
    final restartedQueue =
        CommerceFileReportQueue(directoryPath: directory.path);
    _activate(
      adapter: restartedAdapter,
      client: MockClient((_) async => http.Response('', 500)),
      queueFactory: () async => restartedQueue,
      runtimeContextProvider: contextProvider,
      rpcClientProvider: () => activeClient,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(wrongScopeCalls, isZero);
    expect(await restartedQueue.open(), hasLength(1));

    generation += 1;
    fingerprint = 'scope-a';
    activeClient = firstClient;
    acknowledgeFirstScope = true;
    notifyRestageCommerceConfigurationChanged();
    await _waitFor(
      () async => (await restartedQueue.open()).isEmpty,
      label: 'original scope resumes retained evidence after restart',
    );
    expect(firstScopeCalls, greaterThanOrEqualTo(2));
  });

  test('rechecks the captured configuration after the queue yield', () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final fileQueue = CommerceFileReportQueue(directoryPath: directory.path);
    await fileQueue.enqueue(
      CommerceReportRecord(
        reportId: '8ba77254-6ab0-4ec8-ae50-f12273ac1f51',
        store: CommerceStore.playStore,
        storeVerificationData: 'queued-proof',
        storeProductId: 'subscription.queued',
        storeTransactionId: 'queued-order',
        applicationAnonymousToken: _applicationToken,
        configurationFingerprint: 'same-scope',
      ),
    );
    var generation = 0;
    var switched = false;
    late RestageRpcClient activeClient;
    late final RestageRpcClient secondClient;
    final queue = _FaultingCommerceReportQueue(
      fileQueue,
      onDueCompleted: () {
        if (switched) return;
        switched = true;
        generation += 1;
        activeClient = secondClient;
      },
    );
    CommerceRuntimeContext? contextProvider() {
      final capturedGeneration = generation;
      return _context(
        fingerprint: 'same-scope',
        token: _applicationToken,
        isCurrent: () => generation == capturedGeneration,
      );
    }

    var firstTransportReports = 0;
    final firstClient = RestageRpcClient(
      baseUrl: 'https://same.example.com',
      apiKey: 'same-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/purchaser-state')) {
          return _jsonResponse(
              _purchaserState(entitlements: const []).toJson());
        }
        firstTransportReports += 1;
        return _jsonResponse(_verifiedState().toJson());
      }),
    );
    var secondTransportReports = 0;
    secondClient = RestageRpcClient(
      baseUrl: 'https://same.example.com',
      apiKey: 'same-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/purchaser-state')) {
          return _jsonResponse(
              _purchaserState(entitlements: const []).toJson());
        }
        secondTransportReports += 1;
        return _jsonResponse(_verifiedState().toJson());
      }),
    );
    activeClient = firstClient;
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);

    _activate(
      adapter: adapter,
      client: MockClient((_) async => http.Response('', 500)),
      queueFactory: () async => queue,
      runtimeContextProvider: contextProvider,
      rpcClientProvider: () => activeClient,
    );

    await _waitFor(
      () async {
        final records = await fileQueue.open();
        return records.length == 1 && records.single.retryAttempt == 1;
      },
      label: 'stale queued attempt is retained without transport dispatch',
    );
    expect(switched, isTrue);
    expect(firstTransportReports, isZero);
    expect(secondTransportReports, isZero);
  });

  test('keeps independently observed scope-bound admissions through restart',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    var generation = 0;
    var fingerprint = 'scope-a';
    final firstTokenStarted = Completer<void>();
    final firstToken = Completer<String?>();
    CommerceRuntimeContext? contextProvider() {
      final capturedGeneration = generation;
      final capturedFingerprint = fingerprint;
      return CommerceRuntimeContext(
        configurationFingerprint: capturedFingerprint,
        applicationAnonymousTokenProvider: () async {
          if (capturedGeneration == 0 && capturedFingerprint == 'scope-a') {
            if (!firstTokenStarted.isCompleted) firstTokenStarted.complete();
            return firstToken.future;
          }
          return capturedFingerprint == 'scope-a'
              ? _applicationToken
              : _secondApplicationToken;
        },
        isCurrent: () => generation == capturedGeneration,
      );
    }

    final scopeAReport = Completer<Map<String, dynamic>>();
    final scopeBReport = Completer<Map<String, dynamic>>();
    var scopeBReportCalls = 0;
    final scopeAClient = RestageRpcClient(
      baseUrl: 'https://scope-a.example.com',
      apiKey: 'scope-a-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/purchaser-state')) {
          return _jsonResponse(
            _purchaserState(entitlements: const <EntitlementSummary>[])
                .toJson(),
          );
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (!scopeAReport.isCompleted) scopeAReport.complete(body);
        return _jsonResponse(_verifiedState().toJson());
      }),
    );
    final scopeBClient = RestageRpcClient(
      baseUrl: 'https://scope-b.example.com',
      apiKey: 'scope-b-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/purchaser-state')) {
          return _jsonResponse(
            _purchaserState(entitlements: const <EntitlementSummary>[])
                .toJson(),
          );
        }
        scopeBReportCalls += 1;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (!scopeBReport.isCompleted) scopeBReport.complete(body);
        return _jsonResponse(_verifiedState().toJson());
      }),
    );
    var activeClient = scopeAClient;
    const transaction = _TestTransaction(
      store: CommerceStore.playStore,
      status: CommerceStoreTransactionStatus.purchased,
      storeProductId: 'subscription.monthly',
      storeTransactionId: 'scope-replay-order',
      storeVerificationData: 'scope-replay-token',
      requiresDeviceCompletion: false,
    );
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);

    _activate(
      adapter: adapter,
      client: MockClient((_) async => http.Response('', 500)),
      queueFactory: () async => queue,
      runtimeContextProvider: contextProvider,
      rpcClientProvider: () => activeClient,
    );
    adapter.emit(transaction);
    await firstTokenStarted.future.timeout(_progressTimeout);

    generation += 1;
    fingerprint = 'scope-b';
    activeClient = scopeBClient;
    notifyRestageCommerceConfigurationChanged();
    adapter.emit(transaction);
    final deliveredToB = await scopeBReport.future.timeout(_progressTimeout);
    expect(deliveredToB['appAnonymousToken'], _secondApplicationToken);

    firstToken.complete(_applicationToken);
    await _waitFor(
      () async {
        final records = await queue.open();
        return records.length == 1 &&
            records.single.configurationFingerprint == 'scope-a';
      },
      label: 'scope-a admission persists without relabeling it to scope-b',
    );
    final original = (await queue.open()).single;
    expect(original.applicationAnonymousToken, _applicationToken);
    expect(deliveredToB['reportId'], isNot(original.reportId));

    Restage.debugReset();
    final reopenedAdapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(reopenedAdapter.close);
    final reopenedQueue =
        CommerceFileReportQueue(directoryPath: directory.path);
    _activate(
      adapter: reopenedAdapter,
      client: MockClient((_) async => http.Response('', 500)),
      queueFactory: () async => reopenedQueue,
      runtimeContextProvider: contextProvider,
      rpcClientProvider: () => activeClient,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(scopeBReport.isCompleted, isTrue);
    expect(scopeBReportCalls, 1);
    expect(await reopenedQueue.open(), hasLength(1));

    generation += 1;
    fingerprint = 'scope-a';
    activeClient = scopeAClient;
    notifyRestageCommerceConfigurationChanged();
    final deliveredToA = await scopeAReport.future.timeout(_progressTimeout);
    expect(deliveredToA['reportId'], original.reportId);
    expect(deliveredToA['appAnonymousToken'], _applicationToken);
    await _waitFor(
      () async => (await reopenedQueue.open()).isEmpty,
      label: 'original scope report is acknowledged after restart',
    );
  });

  test('retains an observed owner across configuration and identity changes',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    var generation = 0;
    var fingerprint = 'scope-a';
    final originalTokenStarted = Completer<void>();
    final originalToken = Completer<String?>();
    CommerceRuntimeContext? contextProvider() {
      final capturedGeneration = generation;
      final capturedFingerprint = fingerprint;
      return CommerceRuntimeContext(
        configurationFingerprint: capturedFingerprint,
        applicationAnonymousTokenProvider: () async {
          if (capturedGeneration == 0) {
            if (!originalTokenStarted.isCompleted) {
              originalTokenStarted.complete();
            }
            return originalToken.future;
          }
          return _secondApplicationToken;
        },
        isCurrent: () => generation == capturedGeneration,
      );
    }

    final reportSeen = Completer<Map<String, dynamic>>();
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    final queueClient = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (!reportSeen.isCompleted) reportSeen.complete(body);
      return _jsonResponse(_verifiedState().toJson());
    });

    _activate(
      adapter: adapter,
      client: queueClient,
      queueFactory: () async => queue,
      runtimeContextProvider: contextProvider,
    );
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.playStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'held-owner-order',
        storeVerificationData: 'held-owner-token',
        requiresDeviceCompletion: false,
      ),
    );
    await originalTokenStarted.future.timeout(_progressTimeout);

    generation += 1;
    fingerprint = 'scope-b';
    notifyRestageCommerceConfigurationChanged();
    generation += 1;
    notifyRestageCommerceIdentityChanged();
    originalToken.complete(_applicationToken);

    await _waitFor(
      () async {
        final records = await queue.open();
        return records.length == 1 &&
            records.single.configurationFingerprint == 'scope-a';
      },
      label: 'old owner is durable under the observed scope',
    );
    expect((await queue.open()).single.applicationAnonymousToken,
        _applicationToken);
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'new owner completes a fresh empty query',
    );
    expect(Restage.commerce.currentState.entitlements, isEmpty);

    generation += 1;
    fingerprint = 'scope-a';
    notifyRestageCommerceConfigurationChanged();
    final report = await reportSeen.future.timeout(_progressTimeout);
    expect(report['appAnonymousToken'], _applicationToken);
    await _waitFor(
      () async => (await queue.open()).isEmpty,
      label: 'old owner report is acknowledged without adopting it',
    );
    expect(Restage.commerce.currentState.status,
        CommercePurchaserStateStatusCode.available);
    expect(Restage.commerce.currentState.entitlements, isEmpty);
  });

  test('retains a root owner whose lookup crosses configuration and reset',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'restage.analytics.anonymous_id': _applicationToken,
    });
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
      if (call.method == 'getApplicationSupportDirectory') {
        return directory.path;
      }
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null),
    );
    final preferences = Completer<SharedPreferences>();
    final preferenceReadStarted = Completer<void>();
    RootAnalyticsRuntime.debugIdentityFactory = () => AnalyticsIdentity(
          prefsProvider: () {
            if (!preferenceReadStarted.isCompleted) {
              preferenceReadStarted.complete();
            }
            return preferences.future;
          },
          newId: () => _secondApplicationToken,
        );
    final reportSeen = Completer<Map<String, dynamic>>();
    final client = RestageRpcClient(
      baseUrl: 'https://scope-a.example.com',
      apiKey: 'scope-a-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/reports')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['storeTransactionId'] == 'root-owner-race-order' &&
              !reportSeen.isCompleted) {
            reportSeen.complete(body);
          }
          return _jsonResponse(_verifiedState().toJson());
        }
        return _jsonResponse(
          CommercePurchaserStateResponse(
            status: 'current',
            entitlements: const <EntitlementSummary>[],
            retrievedAt: DateTime.utc(2026, 9, 7),
          ).toJson(),
        );
      }),
    );
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    addTearDown(() async {
      await Restage.debugResetAndWait();
      await directory.delete(recursive: true);
    });

    Restage.configure(
      apiKey: 'scope-a-key',
      baseUrl: 'https://scope-a.example.com',
      analyticsEnabled: false,
    );
    Restage.debugRestageRpcClient = client;
    Restage.activateCommerce(adapter);
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.appStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'root-owner-race-order',
        storeVerificationData: 'root-owner-race-jws',
        requiresDeviceCompletion: false,
      ),
    );
    await preferenceReadStarted.future.timeout(_progressTimeout);

    Restage.configure(
      apiKey: 'scope-b-key',
      baseUrl: 'https://scope-b.example.com',
      analyticsEnabled: false,
    );
    Restage.debugRestageRpcClient = client;
    Restage.reset();
    preferences.complete(await SharedPreferences.getInstance());

    Restage.configure(
      apiKey: 'scope-a-key',
      baseUrl: 'https://scope-a.example.com',
      analyticsEnabled: false,
    );
    Restage.debugRestageRpcClient = client;
    final report = await reportSeen.future.timeout(_progressTimeout);
    expect(report['appAnonymousToken'], _applicationToken);
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'restored scope completes a fresh empty query',
    );
    expect(Restage.commerce.currentState.entitlements, isEmpty);
  });

  test('drops unrecoverable stale ownership before a fresh provider replay',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    var generation = 0;
    var originalTokenReads = 0;
    final originalTokenStarted = Completer<void>();
    final originalToken = Completer<String?>();
    CommerceRuntimeContext? contextProvider() {
      final capturedGeneration = generation;
      return CommerceRuntimeContext(
        configurationFingerprint: 'same-scope',
        applicationAnonymousTokenProvider: () async {
          if (capturedGeneration == 0) {
            originalTokenReads += 1;
            if (!originalTokenStarted.isCompleted) {
              originalTokenStarted.complete();
            }
            return originalToken.future;
          }
          return _secondApplicationToken;
        },
        isCurrent: () => generation == capturedGeneration,
      );
    }

    final reports = <Map<String, dynamic>>[];
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    _activate(
      adapter: adapter,
      client: MockClient((request) async {
        reports.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _jsonResponse(_verifiedState().toJson());
      }),
      queueFactory: () async => queue,
      runtimeContextProvider: contextProvider,
    );
    const replay = _TestTransaction(
      store: CommerceStore.playStore,
      status: CommerceStoreTransactionStatus.restored,
      storeProductId: 'subscription.monthly',
      storeTransactionId: 'unresolved-owner-order',
      storeVerificationData: 'unresolved-owner-token',
      requiresDeviceCompletion: false,
    );
    adapter.emit(replay);
    await originalTokenStarted.future.timeout(_progressTimeout);

    generation += 1;
    notifyRestageCommerceIdentityChanged();
    adapter.emit(replay);
    await _waitFor(
      () async => reports.length == 1,
      label: 'fresh provider replay is admitted',
    );
    expect(reports.single['appAnonymousToken'], _secondApplicationToken);

    originalToken.complete(null);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(originalTokenReads, 2);
    expect(reports, hasLength(1));
    expect(await queue.open(), isEmpty);
  });

  test('does not publish an older verified report after a newer refresh',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final reportStarted = Completer<void>();
    final reportResponse = Completer<http.Response>();
    final completed = Completer<void>();
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
      onComplete: (_) async {
        if (!completed.isCompleted) completed.complete();
      },
    );
    addTearDown(adapter.close);
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/reports')) {
        if (!reportStarted.isCompleted) reportStarted.complete();
        return reportResponse.future;
      }
      return _jsonResponse(
        CommercePurchaserStateResponse(
          status: 'current',
          entitlements: const <EntitlementSummary>[],
          retrievedAt: DateTime.utc(2026, 9, 7),
        ).toJson(),
      );
    });

    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => queue,
      usesPurchaserStateHandler: true,
    );
    final states = <CommercePurchaserState>[];
    final subscription = Restage.commerce.states.listen(states.add);
    addTearDown(subscription.cancel);
    adapter.emit(_applePendingTransaction);
    await reportStarted.future.timeout(_progressTimeout);

    final refreshed = await Restage.commerce.refresh();
    expect(refreshed.entitlements, isEmpty);
    reportResponse.complete(_jsonResponse(_verifiedState().toJson()));

    await completed.future.timeout(_progressTimeout);
    await _waitFor(
      () async => (await queue.open()).isEmpty,
      label: 'older verified report is reconciled and acknowledged',
    );
    expect(Restage.commerce.currentState.entitlements, isEmpty);
    expect(
      states.where((state) => state.entitlements.isNotEmpty),
      isEmpty,
    );
  });

  test('does not publish an older refresh after a newer verified report',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final refreshStarted = Completer<void>();
    final refreshResponse = Completer<http.Response>();
    var purchaserStateCalls = 0;
    var ordinaryReportCalls = 0;
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/purchaser-state')) {
        purchaserStateCalls += 1;
        if (purchaserStateCalls == 1) {
          return _jsonResponse(
            _purchaserState(
              entitlements: const <EntitlementSummary>[],
              retrievedAt: DateTime.utc(2026, 9, 7),
            ).toJson(),
          );
        }
        if (!refreshStarted.isCompleted) refreshStarted.complete();
        return refreshResponse.future;
      }
      ordinaryReportCalls += 1;
      return _jsonResponse(
        CommerceReportResponse(
          outcome: 'verified',
          purchaserState: CommercePurchaserStateResponse(
            status: 'current',
            entitlements: <EntitlementSummary>[
              EntitlementSummary(
                entitlementId: 'subscription.monthly',
                status: 'active',
                productId: 'subscription.monthly',
                source: 'clientReport',
              ),
            ],
            retrievedAt: DateTime.utc(2026, 9, 7),
          ),
        ).toJson(),
      );
    });

    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => queue,
      usesPurchaserStateHandler: true,
    );
    final states = <CommercePurchaserState>[];
    final subscription = Restage.commerce.states.listen(states.add);
    addTearDown(subscription.cancel);
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'initial complete query',
    );
    final refresh = Restage.commerce.refresh();
    await refreshStarted.future.timeout(_progressTimeout);
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.playStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'newer-report-order',
        storeVerificationData: 'newer-report-token',
        requiresDeviceCompletion: false,
      ),
    );
    await _waitFor(
      () async => ordinaryReportCalls == 1 && (await queue.open()).isEmpty,
      label: 'newer ordinary report is reconciled during the query',
    );
    expect(
      Restage.commerce.currentState.status,
      CommercePurchaserStateStatusCode.stale,
    );
    expect(Restage.commerce.currentState.entitlements, isEmpty);
    refreshResponse.complete(
      _jsonResponse(
        CommercePurchaserStateResponse(
          status: 'current',
          entitlements: const <EntitlementSummary>[],
          retrievedAt: DateTime.utc(2026, 9, 5),
        ).toJson(),
      ),
    );

    final refreshed = await refresh.timeout(_progressTimeout);
    expect(refreshed.status, CommercePurchaserStateStatusCode.stale);
    expect(refreshed.entitlements, isEmpty);
    expect(Restage.commerce.currentState.entitlements, isEmpty);
    expect(
      states.where(
        (state) =>
            state.status == CommercePurchaserStateStatusCode.available &&
            state.entitlements.isNotEmpty,
      ),
      isEmpty,
    );
  });

  test('failed query stays non-current after ordinary report reconciliation',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final refreshStarted = Completer<void>();
    final refreshResponse = Completer<http.Response>();
    var purchaserStateCalls = 0;
    var ordinaryReportCalls = 0;
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/purchaser-state')) {
        purchaserStateCalls += 1;
        if (purchaserStateCalls == 1) {
          return _jsonResponse(
            _purchaserState(
              entitlements: const <EntitlementSummary>[],
              retrievedAt: DateTime.utc(2026, 9),
            ).toJson(),
          );
        }
        if (purchaserStateCalls > 2) {
          return _jsonResponse(
            _purchaserState(
              entitlements: const <EntitlementSummary>[],
              retrievedAt: DateTime.utc(2026, 9, 9),
            ).toJson(),
          );
        }
        if (!refreshStarted.isCompleted) refreshStarted.complete();
        return refreshResponse.future;
      }
      ordinaryReportCalls += 1;
      return _jsonResponse(_verifiedState().toJson());
    });

    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => queue,
      usesPurchaserStateHandler: true,
    );
    final states = <CommercePurchaserState>[];
    final subscription = Restage.commerce.states.listen(states.add);
    addTearDown(subscription.cancel);
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'initial complete query',
    );
    final refresh = Restage.commerce.refresh();
    await refreshStarted.future.timeout(_progressTimeout);
    adapter.emit(_applePendingTransaction);
    await _waitFor(
      () async => ordinaryReportCalls == 1 && (await queue.open()).isEmpty,
      label: 'ordinary verified report reconciles while query is held',
    );
    expect(Restage.commerce.currentState.status,
        CommercePurchaserStateStatusCode.stale);
    expect(Restage.commerce.currentState.entitlements, isEmpty);

    refreshResponse.complete(http.Response('', 503));
    final result = await refresh.timeout(_progressTimeout);

    expect(result, same(Restage.commerce.currentState));
    expect(result.status, CommercePurchaserStateStatusCode.stale);
    expect(result.entitlements, isEmpty);
    expect(states.last, same(result));
    final recovered = await Restage.commerce.refresh();
    expect(recovered.status, CommercePurchaserStateStatusCode.available);
    expect(recovered.entitlements, isEmpty);
  });

  test('timed-out query stays non-current after ordinary report reconciliation',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final refreshStarted = Completer<void>();
    final refreshResponse = Completer<http.Response>();
    var purchaserStateCalls = 0;
    var ordinaryReportCalls = 0;
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/purchaser-state')) {
        purchaserStateCalls += 1;
        if (purchaserStateCalls == 1) {
          return _jsonResponse(
            _purchaserState(
              entitlements: const <EntitlementSummary>[],
              retrievedAt: DateTime.utc(2026, 9),
            ).toJson(),
          );
        }
        if (purchaserStateCalls > 2) {
          return _jsonResponse(
            _purchaserState(
              entitlements: const <EntitlementSummary>[],
              retrievedAt: DateTime.utc(2026, 9, 9),
            ).toJson(),
          );
        }
        if (!refreshStarted.isCompleted) refreshStarted.complete();
        return refreshResponse.future;
      }
      ordinaryReportCalls += 1;
      return _jsonResponse(_verifiedState().toJson());
    });

    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => queue,
      networkAttemptTimeout: const Duration(milliseconds: 250),
      usesPurchaserStateHandler: true,
    );
    final states = <CommercePurchaserState>[];
    final subscription = Restage.commerce.states.listen(states.add);
    addTearDown(subscription.cancel);
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'initial complete query',
    );
    final refresh = Restage.commerce.refresh();
    await refreshStarted.future.timeout(_progressTimeout);
    adapter.emit(_applePendingTransaction);
    await _waitFor(
      () async => ordinaryReportCalls == 1 && (await queue.open()).isEmpty,
      label: 'ordinary verified report reconciles before query timeout',
    );
    expect(Restage.commerce.currentState.status,
        CommercePurchaserStateStatusCode.stale);
    expect(Restage.commerce.currentState.entitlements, isEmpty);

    final result = await refresh.timeout(_progressTimeout);

    expect(result, same(Restage.commerce.currentState));
    expect(result.status, CommercePurchaserStateStatusCode.stale);
    expect(result.entitlements, isEmpty);
    expect(states.last, same(result));
    refreshResponse.complete(http.Response('', 503));
    final recovered = await Restage.commerce.refresh();
    expect(recovered.status, CommercePurchaserStateStatusCode.available);
    expect(recovered.entitlements, isEmpty);
  });

  test('publishes stale state for a latest failed refresh', () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    var purchaserStateCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/purchaser-state')) {
        purchaserStateCalls += 1;
        if (purchaserStateCalls == 1) {
          return _jsonResponse(
            _purchaserState(
              entitlements: const <EntitlementSummary>[],
              retrievedAt: DateTime.utc(2026, 9),
            ).toJson(),
          );
        }
        return http.Response('', 503);
      }
      return _jsonResponse(_verifiedState().toJson());
    });

    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => queue,
      usesPurchaserStateHandler: true,
    );
    final states = <CommercePurchaserState>[];
    final subscription = Restage.commerce.states.listen(states.add);
    addTearDown(subscription.cancel);
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'initial complete query',
    );
    adapter.emit(_applePendingTransaction);
    await _waitFor(
      () => Restage.commerce.currentState.entitlements.isNotEmpty,
      label: 'initial verified report publishes',
    );

    final result = await Restage.commerce.refresh();

    expect(result, same(Restage.commerce.currentState));
    expect(result.status, CommercePurchaserStateStatusCode.stale);
    expect(result.entitlements, isEmpty);
    expect(states.last, same(result));
  });

  test('keeps stale state when a later refresh response is older', () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    var refreshCalls = 0;
    var ordinaryReportCalls = 0;
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/purchaser-state')) {
        refreshCalls += 1;
        return switch (refreshCalls) {
          1 => _jsonResponse(
              _purchaserState(
                entitlements: const <EntitlementSummary>[],
                retrievedAt: DateTime.utc(2026, 9),
              ).toJson(),
            ),
          2 => http.Response('', 503),
          _ => _jsonResponse(
              CommercePurchaserStateResponse(
                status: 'current',
                entitlements: <EntitlementSummary>[
                  EntitlementSummary(
                    entitlementId: 'subscription.monthly',
                    status: 'active',
                    productId: 'subscription.monthly',
                    source: 'clientReport',
                  ),
                ],
                retrievedAt: DateTime.utc(2026, 9, 4),
              ).toJson(),
            ),
        };
      }
      ordinaryReportCalls += 1;
      return _jsonResponse(_verifiedState().toJson());
    });

    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => queue,
      usesPurchaserStateHandler: true,
    );
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'initial complete query',
    );
    adapter.emit(_applePendingTransaction);
    await _waitFor(
      () => Restage.commerce.currentState.entitlements.isNotEmpty,
      label: 'initial verified report publishes',
    );
    final failed = await Restage.commerce.refresh();
    expect(failed.status, CommercePurchaserStateStatusCode.stale);

    final older = await Restage.commerce.refresh();

    expect(older, same(Restage.commerce.currentState));
    expect(older.status, CommercePurchaserStateStatusCode.stale);
    expect(older.entitlements, isEmpty);
    adapter.emit(_applePendingTransaction);
    await _waitFor(
      () async => ordinaryReportCalls == 2 && (await queue.open()).isEmpty,
      label: 'ordinary report reconciles after older canonical response',
    );
    expect(
      Restage.commerce.currentState.status,
      CommercePurchaserStateStatusCode.stale,
    );
    expect(Restage.commerce.currentState.entitlements, isEmpty);
  });

  test('a configuration change fences a held report response', () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    var generation = 0;
    var fingerprint = 'scope-a';
    CommerceRuntimeContext? contextProvider() {
      final capturedGeneration = generation;
      final capturedFingerprint = fingerprint;
      return _context(
        fingerprint: capturedFingerprint,
        token: _applicationToken,
        isCurrent: () => generation == capturedGeneration,
      );
    }

    final requestStarted = Completer<void>();
    final release = Completer<http.Response>();
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    final client = MockClient((request) async {
      if (!requestStarted.isCompleted) requestStarted.complete();
      return release.future;
    });

    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => queue,
      runtimeContextProvider: contextProvider,
    );
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.playStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'configuration-fence-order',
        storeVerificationData: 'configuration-fence-token',
        requiresDeviceCompletion: false,
      ),
    );
    await requestStarted.future.timeout(_progressTimeout);

    generation += 1;
    fingerprint = 'scope-b';
    notifyRestageCommerceConfigurationChanged();
    release.complete(_jsonResponse(_verifiedState().toJson()));

    await _waitFor(
      () async {
        final records = await queue.open();
        return records.length == 1 && records.single.retryAttempt == 1;
      },
      label: 'held response leaves scope-a report retained',
    );
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'reset owner completes a fresh empty query',
    );
    expect(Restage.commerce.currentState.entitlements, isEmpty);
  });

  test('same-fingerprint reconfiguration invalidates the captured snapshot',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    var generation = 0;
    CommerceRuntimeContext? contextProvider() {
      final capturedGeneration = generation;
      return _context(
        fingerprint: 'same-scope',
        token: _applicationToken,
        isCurrent: () => generation == capturedGeneration,
      );
    }

    final reconfiguredQuery = Completer<List<CommerceStoreTransaction>>();
    var ordinaryReportCalls = 0;
    late final _TestStoreAdapter adapter;
    adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
      onQueryOwnedTransactions: () => adapter.ownedQueryCalls == 1
          ? Future<List<CommerceStoreTransaction>>.value(
              const <CommerceStoreTransaction>[],
            )
          : reconfiguredQuery.future,
    );
    addTearDown(adapter.close);
    _activate(
      adapter: adapter,
      client: MockClient((_) async {
        ordinaryReportCalls += 1;
        return _jsonResponse(_verifiedState().toJson());
      }),
      queueFactory: () async => queue,
      runtimeContextProvider: contextProvider,
    );
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'initial snapshot is current',
    );

    generation += 1;
    notifyRestageCommerceConfigurationChanged();
    await _waitFor(
      () => adapter.ownedQueryCalls == 2,
      label: 'same fingerprint still starts a new owned query',
    );
    expect(
      Restage.commerce.currentState.status,
      CommercePurchaserStateStatusCode.stale,
    );
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.playStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.ordinary',
        storeTransactionId: 'ordinary-after-config-order',
        storeVerificationData: 'ordinary-after-config-proof',
        requiresDeviceCompletion: false,
      ),
    );
    await _waitFor(
      () async => ordinaryReportCalls == 1 && (await queue.open()).isEmpty,
      label: 'ordinary report is reconciled under the new configuration',
    );
    expect(
      Restage.commerce.currentState.status,
      CommercePurchaserStateStatusCode.stale,
    );

    reconfiguredQuery.complete(const <CommerceStoreTransaction>[]);
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'new complete query publishes current state',
    );
  });

  test('retained old-token reports reconcile without publishing into new state',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    var now = DateTime.utc(2026, 9, 6);
    final queue = CommerceFileReportQueue(
      directoryPath: directory.path,
      clock: () => now,
    );
    await queue.enqueue(
      CommerceReportRecord(
        reportId: '8ba77254-6ab0-4ec8-ae50-f12273ac1f51',
        store: CommerceStore.playStore,
        storeVerificationData: 'old-provider-token',
        storeProductId: 'subscription.monthly',
        storeTransactionId: 'old-order',
        applicationAnonymousToken: _applicationToken,
        configurationFingerprint: 'same-scope',
        nextRetryAt: now.add(const Duration(hours: 1)),
      ),
    );
    const newToken = '50f2ca4b-7e04-4b3e-9d0f-899cb83ce1d5';
    final reports = <Map<String, dynamic>>[];
    final purchaserStateRequests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('purchaser-state')) {
        purchaserStateRequests.add(
          jsonDecode(request.body) as Map<String, dynamic>,
        );
        return _jsonResponse(
          CommercePurchaserStateResponse(
            status: 'current',
            entitlements: const <EntitlementSummary>[],
            retrievedAt: now,
          ).toJson(),
        );
      }
      reports.add(jsonDecode(request.body) as Map<String, dynamic>);
      return _jsonResponse(_verifiedState().toJson());
    });
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);

    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => queue,
      runtimeContextProvider: () => _context(
        fingerprint: 'same-scope',
        token: newToken,
      ),
      usesPurchaserStateHandler: true,
    );
    final refreshed = await Restage.commerce.refresh();
    expect(refreshed.entitlements, isEmpty);
    expect(purchaserStateRequests, isNotEmpty);
    for (final request in purchaserStateRequests) {
      expect(request['appAnonymousToken'], newToken);
      expect(request['knownStoreTransactionIds'], isEmpty);
    }

    now = now.add(const Duration(hours: 2));
    notifyRestageCommerceConfigurationChanged();
    await _waitFor(
      () async => (await queue.open()).isEmpty,
      label: 'old-token report reconciles',
    );

    expect(reports.single['appAnonymousToken'], _applicationToken);
    expect(Restage.commerce.currentState.entitlements, isEmpty);
  });

  test('an identity reset fence rejects a held purchaser-state response',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final requestStarted = Completer<void>();
    final release = Completer<http.Response>();
    var purchaserStateCalls = 0;
    final client = MockClient((request) async {
      purchaserStateCalls += 1;
      if (purchaserStateCalls == 1) {
        return _jsonResponse(
          _purchaserState(
            entitlements: const <EntitlementSummary>[],
            retrievedAt: DateTime.utc(2026, 9),
          ).toJson(),
        );
      }
      if (purchaserStateCalls == 2) {
        if (!requestStarted.isCompleted) requestStarted.complete();
        return release.future;
      }
      return _jsonResponse(
        _purchaserState(
          entitlements: const <EntitlementSummary>[],
          retrievedAt: DateTime.utc(2026, 9, 7),
        ).toJson(),
      );
    });
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);

    var generation = 0;
    CommerceRuntimeContext? contextProvider() {
      final capturedGeneration = generation;
      return _context(
        fingerprint: 'reset-scope',
        token: _applicationToken,
        isCurrent: () => generation == capturedGeneration,
      );
    }

    _activate(
      adapter: adapter,
      client: client,
      journalPath: directory.path,
      runtimeContextProvider: contextProvider,
      usesPurchaserStateHandler: true,
    );
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'initial query completes before held refresh',
    );
    final refresh = Restage.commerce.refresh();
    await requestStarted.future.timeout(_progressTimeout);
    generation += 1;
    notifyRestageCommerceIdentityChanged();
    release.complete(
      _jsonResponse(
        CommercePurchaserStateResponse(
          status: 'current',
          entitlements: <EntitlementSummary>[
            EntitlementSummary(
              entitlementId: 'subscription.monthly',
              status: 'active',
              productId: 'subscription.monthly',
              source: 'clientReport',
            ),
          ],
          retrievedAt: DateTime.utc(2026, 9, 6),
        ).toJson(),
      ),
    );

    final result = await refresh.timeout(_progressTimeout);
    expect(result.status, CommercePurchaserStateStatusCode.stale);
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'new identity publishes only after its complete query',
    );
    expect(Restage.commerce.currentState.entitlements, isEmpty);
  });

  test('recovers Google purchases on activation, retry, and foreground',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final reportSeen = Completer<void>();
    late final _TestStoreAdapter adapter;
    adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
      onQueryOwnedTransactions: () async {
        if (adapter.ownedQueryCalls == 1) {
          throw StateError('temporary query error');
        }
        return const <CommerceStoreTransaction>[
          _TestTransaction(
            store: CommerceStore.playStore,
            status: CommerceStoreTransactionStatus.purchased,
            storeProductId: 'subscription.monthly',
            storeTransactionId: 'restore-order',
            storeVerificationData: 'restore-token',
            requiresDeviceCompletion: false,
          ),
        ];
      },
    );
    addTearDown(adapter.close);
    final client = MockClient((request) async {
      if (!reportSeen.isCompleted) reportSeen.complete();
      return _jsonResponse(
        _scopedReport(
          scopedEntitlements: [_entitlement('subscription.monthly')],
        ).toJson(),
      );
    });

    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => queue,
    );
    await reportSeen.future.timeout(_progressTimeout);
    expect(adapter.ownedQueryCalls, 2);
    expect(adapter.completionCalls, isZero);

    final beforeForeground = adapter.ownedQueryCalls;
    notifyRestageCommerceForegrounded();
    await _waitFor(
      () async => adapter.ownedQueryCalls > beforeForeground,
      label: 'foreground runs the Play owned-purchase query',
    );
    expect(adapter.ownedQueryCalls, 3);
    expect(adapter.completionCalls, isZero);
    await _waitFor(
      () async => (await queue.open()).isEmpty,
      label: 'foreground recovery report is acknowledged',
    );
  });

  test('waits for configuration before startup Google recovery', () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    var configured = false;
    final reportSeen = Completer<void>();
    late final _TestStoreAdapter adapter;
    adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
      onQueryOwnedTransactions: () async => const <CommerceStoreTransaction>[
        _TestTransaction(
          store: CommerceStore.playStore,
          status: CommerceStoreTransactionStatus.restored,
          storeProductId: 'subscription.monthly',
          storeTransactionId: 'delayed-startup-order',
          storeVerificationData: 'delayed-startup-token',
          requiresDeviceCompletion: false,
        ),
      ],
    );
    addTearDown(adapter.close);
    _activate(
      adapter: adapter,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/reports') && !reportSeen.isCompleted) {
          reportSeen.complete();
        }
        return _jsonResponse(
          _scopedReport(
            scopedEntitlements: [_entitlement('subscription.monthly')],
          ).toJson(),
        );
      }),
      queueFactory: () async => queue,
      runtimeContextProvider: () => configured
          ? _context(fingerprint: 'startup-scope', token: _applicationToken)
          : null,
    );

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(adapter.ownedQueryCalls, isZero);

    configured = true;
    notifyRestageCommerceConfigurationChanged();
    await reportSeen.future.timeout(_progressTimeout);
    expect(adapter.ownedQueryCalls, 1);
    expect(adapter.completionCalls, isZero);
    await _waitFor(
      () async => (await queue.open()).isEmpty,
      label: 'configured startup recovery report is acknowledged',
    );
    // The report is acknowledged before recovery publishes its snapshot.
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'configured startup recovery publishes current state',
    );

    notifyRestageCommerceConfigurationChanged();
    notifyRestageCommerceConfigurationChanged();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(adapter.ownedQueryCalls, 1);
  });

  test('runs configured startup Google recovery once', () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final reportSeen = Completer<void>();
    late final _TestStoreAdapter adapter;
    adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
      onQueryOwnedTransactions: () async => const <CommerceStoreTransaction>[
        _TestTransaction(
          store: CommerceStore.playStore,
          status: CommerceStoreTransactionStatus.restored,
          storeProductId: 'subscription.monthly',
          storeTransactionId: 'configured-startup-order',
          storeVerificationData: 'configured-startup-token',
          requiresDeviceCompletion: false,
        ),
      ],
    );
    addTearDown(adapter.close);
    _activate(
      adapter: adapter,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/reports') && !reportSeen.isCompleted) {
          reportSeen.complete();
        }
        return _jsonResponse(
          _scopedReport(
            scopedEntitlements: [_entitlement('subscription.monthly')],
          ).toJson(),
        );
      }),
      queueFactory: () async => queue,
    );

    await reportSeen.future.timeout(_progressTimeout);
    expect(adapter.ownedQueryCalls, 1);
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'configured startup query publishes current state',
    );
    notifyRestageCommerceConfigurationChanged();
    notifyRestageCommerceConfigurationChanged();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(adapter.ownedQueryCalls, 1);
    expect(adapter.completionCalls, isZero);
  });

  test('starts Google recovery through installed-catalog configuration',
      () async {
    final directory = await _rootCommerceStorage();
    final journalPath = '${directory.path}/restage/commerce/reports-v1';
    final reportSeen = Completer<Map<String, dynamic>>();
    final client = RestageRpcClient(
      baseUrl: 'https://scope-a.example.com',
      apiKey: 'scope-a-key',
      httpClient: MockClient((request) async {
        expect(request.url.host, 'scope-a.example.com');
        if (request.url.path.endsWith('/purchaser-state')) {
          return _jsonResponse(
            _purchaserState(entitlements: const <EntitlementSummary>[])
                .toJson(),
          );
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final saved = await _publishedReports(journalPath);
        expect(saved.single.reportId, body['reportId']);
        expect(saved.single.applicationAnonymousToken, _applicationToken);
        if (!reportSeen.isCompleted) reportSeen.complete(body);
        return _jsonResponse(
          _scopedReport(scopedEntitlements: const <EntitlementSummary>[])
              .toJson(),
        );
      }),
    );
    late final _TestStoreAdapter adapter;
    adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
      onQueryOwnedTransactions: () async {
        if (adapter.ownedQueryCalls > 1) {
          return const <CommerceStoreTransaction>[];
        }
        return const <CommerceStoreTransaction>[
          _TestTransaction(
            store: CommerceStore.playStore,
            status: CommerceStoreTransactionStatus.restored,
            storeProductId: 'subscription.monthly',
            storeTransactionId: 'installed-catalog-startup-order',
            storeVerificationData: 'installed-catalog-startup-token',
            requiresDeviceCompletion: false,
          ),
        ];
      },
    );
    addTearDown(adapter.close);
    Restage.activateCommerce(adapter);
    await Future<void>.delayed(Duration.zero);
    expect(adapter.ownedQueryCalls, isZero);

    Restage.configureWithInstalledCatalog(
      apiKey: '  ',
      baseUrl: 'https://scope-a.example.com',
      analyticsEnabled: false,
      measurementEnabled: false,
    );
    await Future<void>.delayed(Duration.zero);
    expect(adapter.ownedQueryCalls, isZero);

    Restage.configureWithInstalledCatalog(
      apiKey: '  scope-a-key  ',
      baseUrl: 'https://scope-a.example.com',
      analyticsEnabled: false,
      measurementEnabled: false,
    );
    Restage.debugRestageRpcClient = client;
    final report = await reportSeen.future.timeout(_progressTimeout);
    expect(report['appAnonymousToken'], _applicationToken);
    expect(adapter.ownedQueryCalls, 1);
    expect(adapter.completionCalls, isZero);
    await _waitFor(
      () async =>
          (await _publishedReports(journalPath)).isEmpty &&
          Restage.commerce.currentState.status ==
              CommercePurchaserStateStatusCode.available,
      label: 'startup report is acknowledged',
    );

    Restage.configureWithInstalledCatalog(
      apiKey: 'scope-b-key',
      baseUrl: 'https://scope-b.example.com',
      analyticsEnabled: false,
      measurementEnabled: false,
    );
    Restage.debugRestageRpcClient = RestageRpcClient(
      baseUrl: 'https://scope-b.example.com',
      apiKey: 'scope-b-key',
      httpClient: MockClient((request) async {
        expect(request.url.host, 'scope-b.example.com');
        expect(request.url.path, endsWith('/purchaser-state'));
        return _jsonResponse(
          _purchaserState(entitlements: const <EntitlementSummary>[]).toJson(),
        );
      }),
    );
    await _waitFor(
      () =>
          adapter.ownedQueryCalls >= 2 &&
          Restage.commerce.currentState.status ==
              CommercePurchaserStateStatusCode.available,
      label: 'new configuration performs a complete startup query',
    );
    expect(adapter.restoreCalls, isZero);
  });

  test('root reset invalidates commerce before a held refresh returns',
      () async {
    await _rootCommerceStorage();
    final heldRefresh = Completer<http.Response>();
    addTearDown(() {
      if (!heldRefresh.isCompleted) {
        heldRefresh
            .complete(_jsonResponse(_verifiedState().purchaserState.toJson()));
      }
    });
    final refreshStarted = Completer<void>();
    final tokens = <String>[];
    final client = RestageRpcClient(
      baseUrl: 'https://scope-a.example.com',
      apiKey: 'scope-a-key',
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        tokens.add(body['appAnonymousToken'] as String);
        if (tokens.length == 2) {
          refreshStarted.complete();
          return heldRefresh.future;
        }
        return _jsonResponse((tokens.length == 1
                ? _verifiedState().purchaserState
                : _emptyVerifiedState().purchaserState)
            .toJson());
      }),
    );
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    Restage.configureWithInstalledCatalog(
      apiKey: 'scope-a-key',
      baseUrl: 'https://scope-a.example.com',
      analyticsEnabled: false,
      measurementEnabled: false,
    );
    Restage.debugRestageRpcClient = client;
    Restage.activateCommerce(adapter);
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
              CommercePurchaserStateStatusCode.available &&
          Restage.commerce.currentState.entitlements.isNotEmpty,
      label: 'startup complete query publishes the original owner',
    );
    expect(Restage.commerce.currentState.entitlements.single.entitlementId,
        'subscription.monthly');

    final pending = Restage.commerce.refresh();
    await refreshStarted.future.timeout(_progressTimeout);
    Restage.reset();
    expect(Restage.commerce.currentState.status,
        CommercePurchaserStateStatusCode.stale);
    expect(Restage.commerce.currentState.entitlements, isEmpty);
    heldRefresh
        .complete(_jsonResponse(_verifiedState().purchaserState.toJson()));
    final stale = await pending.timeout(_progressTimeout);
    expect(stale.status, CommercePurchaserStateStatusCode.stale);
    expect(Restage.commerce.currentState.entitlements, isEmpty);

    final current = await Restage.commerce.refresh();
    expect(current.status, CommercePurchaserStateStatusCode.available);
    expect(current.entitlements, isEmpty);
    expect(tokens.take(2), everyElement(_applicationToken));
    expect(tokens.last, isNot(_applicationToken));
  });

  test('retains an unfinished Apple purchase across a restored duplicate',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final reportStarted = Completer<void>();
    final reportResponse = Completer<http.Response>();
    final completion = Completer<CommerceStoreTransaction>();
    var reportCalls = 0;
    final purchased = _TestTransaction(
      store: CommerceStore.appStore,
      status: CommerceStoreTransactionStatus.purchased,
      storeProductId: 'subscription.monthly',
      storeTransactionId: 'duplicate-apple-order',
      storeVerificationData: 'duplicate-apple-jws',
      requiresDeviceCompletion: true,
    );
    final restored = _TestTransaction(
      store: CommerceStore.appStore,
      status: CommerceStoreTransactionStatus.restored,
      storeProductId: 'subscription.monthly',
      storeTransactionId: 'duplicate-apple-order',
      storeVerificationData: 'duplicate-apple-jws',
      requiresDeviceCompletion: false,
    );
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
      onComplete: (transaction) async {
        if (!completion.isCompleted) completion.complete(transaction);
      },
    );
    addTearDown(adapter.close);
    _activate(
      adapter: adapter,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/purchaser-state')) {
          return _jsonResponse(
              _purchaserState(entitlements: const []).toJson());
        }
        reportCalls += 1;
        if (reportCalls == 1) {
          if (!reportStarted.isCompleted) reportStarted.complete();
          return reportResponse.future;
        }
        return _jsonResponse(
          _scopedReport(scopedEntitlements: const <EntitlementSummary>[])
              .toJson(),
        );
      }),
      queueFactory: () async => queue,
      usesPurchaserStateHandler: true,
    );

    adapter.emit(purchased);
    await reportStarted.future.timeout(_progressTimeout);
    adapter.ownedTransactions = <CommerceStoreTransaction>[restored];
    final restore = Restage.commerce.restore();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(adapter.completionCalls, isZero);

    reportResponse.complete(_jsonResponse(_emptyVerifiedState().toJson()));
    expect(
      await completion.future.timeout(_progressTimeout),
      same(purchased),
    );
    expect(
      (await restore).status,
      CommerceActionStatusCode.submittedForReconciliation,
    );
    expect(reportCalls, 2);
    expect(adapter.completionCalls, 1);
    await _waitFor(
      () async => (await queue.open()).isEmpty,
      label: 'verified Apple report is acknowledged after completion',
    );
  });

  test('keeps a purchased Apple instance through held duplicate admission',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final token = Completer<String?>();
    final queueRequested = Completer<void>();
    final queueReady = Completer<CommerceReportQueue>();
    final firstReport = Completer<void>();
    final completion = Completer<CommerceStoreTransaction>();
    var reportCalls = 0;
    final restored = _TestTransaction(
      store: CommerceStore.appStore,
      status: CommerceStoreTransactionStatus.restored,
      storeProductId: 'subscription.monthly',
      storeTransactionId: 'held-duplicate-apple-order',
      storeVerificationData: 'held-duplicate-apple-jws',
      requiresDeviceCompletion: false,
    );
    final purchased = _TestTransaction(
      store: CommerceStore.appStore,
      status: CommerceStoreTransactionStatus.purchased,
      storeProductId: 'subscription.monthly',
      storeTransactionId: 'held-duplicate-apple-order',
      storeVerificationData: 'held-duplicate-apple-jws',
      requiresDeviceCompletion: true,
    );
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
      onComplete: (transaction) async {
        if (!completion.isCompleted) completion.complete(transaction);
      },
    );
    addTearDown(adapter.close);
    _activate(
      adapter: adapter,
      client: MockClient((request) async {
        reportCalls += 1;
        if (reportCalls == 1) {
          if (!firstReport.isCompleted) firstReport.complete();
          return _jsonResponse(_pendingState().toJson());
        }
        return _jsonResponse(_emptyVerifiedState().toJson());
      }),
      runtimeContextProvider: () => CommerceRuntimeContext(
        configurationFingerprint: 'held-apple-scope',
        applicationAnonymousTokenProvider: () => token.future,
      ),
      queueFactory: () {
        if (!queueRequested.isCompleted) queueRequested.complete();
        return queueReady.future;
      },
    );

    adapter
      ..emit(restored)
      ..emit(purchased);
    await Future<void>.delayed(Duration.zero);
    token.complete(_applicationToken);
    await queueRequested.future.timeout(_progressTimeout);
    adapter.emit(restored);
    await Future<void>.delayed(Duration.zero);
    queueReady.complete(queue);

    await firstReport.future.timeout(_progressTimeout);
    await _waitFor(
      () async {
        final records = await queue.open();
        return records.length == 1 && records.single.retryAttempt == 1;
      },
      label: 'pending report retains the Apple completion obligation',
    );
    expect(adapter.completionCalls, isZero);

    expect(
      await completion.future.timeout(_progressTimeout),
      same(purchased),
    );
    expect(reportCalls, 2);
    expect(adapter.completionCalls, 1);
    await _waitFor(
      () async => (await queue.open()).isEmpty,
      label: 'empty verified report is acknowledged after Apple completion',
    );
  });

  test('does not replay Google owned-purchase recovery for a held report',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final reportStarted = Completer<void>();
    final reportResponse = Completer<http.Response>();
    late final _TestStoreAdapter adapter;
    adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
      onQueryOwnedTransactions: () async => const <CommerceStoreTransaction>[
        _TestTransaction(
          store: CommerceStore.playStore,
          status: CommerceStoreTransactionStatus.restored,
          storeProductId: 'subscription.monthly',
          storeTransactionId: 'held-owned-order',
          storeVerificationData: 'held-owned-token',
          requiresDeviceCompletion: false,
        ),
      ],
    );
    addTearDown(adapter.close);
    _activate(
      adapter: adapter,
      client: MockClient((request) async {
        if (!reportStarted.isCompleted) reportStarted.complete();
        return reportResponse.future;
      }),
      queueFactory: () async => queue,
    );

    await reportStarted.future.timeout(_progressTimeout);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(adapter.ownedQueryCalls, 1);
    expect(adapter.completionCalls, isZero);

    reportResponse.complete(http.Response('retry', 503));
    await _waitFor(
      () async {
        final records = await queue.open();
        return records.length == 1 && records.single.retryAttempt == 1;
      },
      label: 'held report receives its ordinary retry delay',
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(adapter.ownedQueryCalls, 1);
  });

  test('reconstructs exact X and Z purchases under Y without unrelated grants',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    const purchaseX = _TestTransaction(
      store: CommerceStore.playStore,
      status: CommerceStoreTransactionStatus.restored,
      storeProductId: 'subscription.x',
      storeTransactionId: 'order-x',
      storeVerificationData: 'token-x',
      requiresDeviceCompletion: false,
    );
    const purchaseZ = _TestTransaction(
      store: CommerceStore.playStore,
      status: CommerceStoreTransactionStatus.purchased,
      storeProductId: 'subscription.z',
      storeTransactionId: 'order-z',
      storeVerificationData: 'token-z',
      requiresDeviceCompletion: false,
    );
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
      ownedTransactions: const <CommerceStoreTransaction>[
        purchaseZ,
        purchaseX,
        purchaseZ,
      ],
    );
    addTearDown(adapter.close);
    final reports = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/purchaser-state')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['appAnonymousToken'], _secondApplicationToken);
        return _jsonResponse(
          _purchaserState(
            entitlements: [
              _entitlement('entitlement.y'),
              _entitlement(
                'entitlement.shared',
                productId: 'subscription.canonical-expired',
                status: 'expired',
              ),
            ],
          ).toJson(),
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      reports.add(body);
      final proof = body['storeVerificationData'];
      return _jsonResponse(
        _scopedReport(
          scopedEntitlements: [
            _entitlement(
              proof == 'token-x' ? 'entitlement.x' : 'entitlement.z',
            ),
            _entitlement(
              'entitlement.shared',
              productId: proof == 'token-x'
                  ? 'subscription.bounded'
                  : 'subscription.unbounded',
              expiresAtMs: proof == 'token-x' ? 100 : null,
            ),
          ],
          ordinaryEntitlements: [
            _entitlement('entitlement.unrelated-old-owner'),
          ],
        ).toJson(),
      );
    });

    _activate(
      adapter: adapter,
      client: client,
      journalPath: directory.path,
      runtimeContextProvider: () => _context(
        fingerprint: 'restore-scope',
        token: _secondApplicationToken,
      ),
      usesPurchaserStateHandler: true,
    );
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'startup owned query publishes current reconstructed state',
    );

    expect(adapter.ownedQueryCalls, 1);
    expect(reports, hasLength(2));
    expect(
      reports.map((report) => report['storeVerificationData']).toSet(),
      {'token-x', 'token-z'},
    );
    expect(
      reports.map((report) => report['appAnonymousToken']).toSet(),
      {_secondApplicationToken},
    );
    expect(
      Restage.commerce.currentState.entitlements
          .map((entitlement) => entitlement.entitlementId)
          .toList(),
      [
        'entitlement.shared',
        'entitlement.x',
        'entitlement.y',
        'entitlement.z',
      ],
    );
    expect(
      Restage.commerce.currentState.entitlements
          .singleWhere(
            (entitlement) => entitlement.entitlementId == 'entitlement.shared',
          )
          .productId,
      'subscription.unbounded',
    );
  });

  test(
      'empty refresh removes restored membership and failure stays non-current',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    var queryFails = false;
    late final _TestStoreAdapter adapter;
    adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
      ownedTransactions: const <CommerceStoreTransaction>[
        _TestTransaction(
          store: CommerceStore.playStore,
          status: CommerceStoreTransactionStatus.restored,
          storeProductId: 'subscription.restored',
          storeTransactionId: 'restored-order',
          storeVerificationData: 'restored-token',
          requiresDeviceCompletion: false,
        ),
        _TestTransaction(
          store: CommerceStore.playStore,
          status: CommerceStoreTransactionStatus.restored,
          storeProductId: 'subscription.expiring',
          storeTransactionId: 'expiring-order',
          storeVerificationData: 'expiring-token',
          requiresDeviceCompletion: false,
        ),
      ],
      onQueryOwnedTransactions: () async {
        if (queryFails) throw StateError('native query failed');
        return adapter.ownedTransactions;
      },
    );
    addTearDown(adapter.close);
    var reportCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/purchaser-state')) {
        return _jsonResponse(_purchaserState(entitlements: const []).toJson());
      }
      reportCalls += 1;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final proof = body['storeVerificationData'];
      return _jsonResponse(
        _scopedReport(
          scopedEntitlements: switch (proof) {
            'restored-token' => [_entitlement('entitlement.restored')],
            'expiring-token' => [
                _entitlement(
                  'entitlement.expiring',
                  status: adapter.ownedTransactions.length == 1
                      ? 'expired'
                      : 'active',
                ),
              ],
            _ => [_entitlement('entitlement.ordinary')],
          },
        ).toJson(),
      );
    });
    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => queue,
      usesPurchaserStateHandler: true,
    );
    await _waitFor(
      () => Restage.commerce.currentState.entitlements
          .any((value) => value.entitlementId == 'entitlement.restored'),
      label: 'startup restores purchase-scoped membership',
    );

    adapter.ownedTransactions = const <CommerceStoreTransaction>[
      _TestTransaction(
        store: CommerceStore.playStore,
        status: CommerceStoreTransactionStatus.restored,
        storeProductId: 'subscription.expiring',
        storeTransactionId: 'expiring-order',
        storeVerificationData: 'expiring-token',
        requiresDeviceCompletion: false,
      ),
    ];
    final reduced = await Restage.commerce.refresh();
    expect(
      reduced.entitlements
          .any((value) => value.entitlementId == 'entitlement.restored'),
      isFalse,
    );
    expect(
      reduced.entitlements
          .singleWhere(
            (value) => value.entitlementId == 'entitlement.expiring',
          )
          .isEntitled,
      isFalse,
    );

    adapter.ownedTransactions = const <CommerceStoreTransaction>[];
    final empty = await Restage.commerce.refresh();
    expect(empty.status, CommercePurchaserStateStatusCode.available);
    expect(empty.entitlements, isEmpty);

    queryFails = true;
    final failed = await Restage.commerce.refresh();
    expect(failed.status, CommercePurchaserStateStatusCode.stale);
    final reportsBeforeOrdinary = reportCalls;
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.playStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.ordinary',
        storeTransactionId: 'ordinary-order',
        storeVerificationData: 'ordinary-token',
        requiresDeviceCompletion: false,
      ),
    );
    await _waitFor(
      () async =>
          reportCalls == reportsBeforeOrdinary + 1 &&
          (await queue.open()).isEmpty,
      label: 'ordinary report reconciles after failed query',
    );
    expect(
      Restage.commerce.currentState.status,
      CommercePurchaserStateStatusCode.stale,
    );
    expect(Restage.commerce.currentState.entitlements, isEmpty);
  });

  test('same-Y in-flight collision is re-admitted before its fresh attempt',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    final firstStarted = Completer<Map<String, dynamic>>();
    final firstRelease = Completer<http.Response>();
    final secondStarted = Completer<Map<String, dynamic>>();
    final secondRelease = Completer<http.Response>();
    var reportCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/purchaser-state')) {
        return _jsonResponse(_purchaserState(entitlements: const []).toJson());
      }
      reportCalls += 1;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (reportCalls == 1) {
        firstStarted.complete(body);
        return firstRelease.future;
      }
      secondStarted.complete(body);
      return secondRelease.future;
    });
    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => queue,
      usesPurchaserStateHandler: true,
    );
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'initial empty snapshot is current',
    );
    const transaction = _TestTransaction(
      store: CommerceStore.playStore,
      status: CommerceStoreTransactionStatus.purchased,
      storeProductId: 'subscription.collision',
      storeTransactionId: 'collision-order',
      storeVerificationData: 'collision-token',
      requiresDeviceCompletion: false,
    );
    adapter.emit(transaction);
    final first = await firstStarted.future.timeout(_progressTimeout);
    adapter.ownedTransactions = const <CommerceStoreTransaction>[transaction];
    final refresh = Restage.commerce.refresh();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(reportCalls, 1);

    firstRelease.complete(
      _jsonResponse(
        _scopedReport(
          scopedEntitlements: [_entitlement('entitlement.collision')],
        ).toJson(),
      ),
    );
    final second = await secondStarted.future.timeout(_progressTimeout);
    final durableDuringFreshAttempt = await queue.open();
    expect(durableDuringFreshAttempt, hasLength(1));
    expect(durableDuringFreshAttempt.single.reportId, second['reportId']);
    expect(second['reportId'], isNot(first['reportId']));
    secondRelease.complete(
      _jsonResponse(
        _scopedReport(
          scopedEntitlements: [_entitlement('entitlement.collision')],
        ).toJson(),
      ),
    );

    final state = await refresh.timeout(_progressTimeout);
    expect(state.status, CommercePurchaserStateStatusCode.available);
    expect(state.entitlements.single.entitlementId, 'entitlement.collision');
  });

  test(
      'Apple query collision retains completion after successful acknowledgement',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('restage-query-collision-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final fileQueue = CommerceFileReportQueue(directoryPath: directory.path);
    final admitted = Completer<CommerceReportRecord>();
    final queue = _ObserveCompletedEnqueueQueue(fileQueue, 2, admitted);
    final finishStarted = Completer<void>();
    final releaseFinish = Completer<void>();
    final reports = <Map<String, dynamic>>[];
    late final _TestStoreAdapter adapter;
    adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
      onComplete: (transaction) async {
        expect(transaction, same(_applePendingTransaction));
        if (adapter.completionCalls == 1) {
          finishStarted.complete();
          await releaseFinish.future;
        }
      },
    );
    addTearDown(adapter.close);
    addTearDown(() {
      if (!releaseFinish.isCompleted) releaseFinish.complete();
    });
    _activate(
      adapter: adapter,
      queueFactory: () async => queue,
      runtimeContextProvider: () => _context(
        fingerprint: 'query-collision-retention',
        token: _applicationToken,
      ),
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final saved = (await queue.open()).singleWhere(
          (record) => record.reportId == body['reportId'],
        );
        expect(saved.configurationFingerprint, 'query-collision-retention');
        expect(saved.applicationAnonymousToken, _applicationToken);
        expect(saved.store, _applePendingTransaction.store);
        expect(saved.storeTransactionId,
            _applePendingTransaction.storeTransactionId);
        expect(saved.storeProductId, _applePendingTransaction.storeProductId);
        expect(saved.storeVerificationData,
            _applePendingTransaction.storeVerificationData);
        expect(body['appAnonymousToken'], saved.applicationAnonymousToken);
        expect(body['storeVerificationData'], saved.storeVerificationData);
        reports.add(body);
        return _jsonResponse(
          _scopedReport(
            scopedEntitlements: const <EntitlementSummary>[],
            retrievedAt: DateTime.utc(2026, 9),
          ).toJson(),
        );
      }),
    );
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'initial complete empty snapshot',
    );
    adapter.emit(_applePendingTransaction);
    await finishStarted.future.timeout(_progressTimeout);
    adapter.ownedTransactions = const <CommerceStoreTransaction>[
      _applePendingTransaction,
    ];
    final refresh = Restage.commerce.refresh();
    final collisionRow = await admitted.future.timeout(_progressTimeout);
    expect(collisionRow.reportId, reports.single['reportId']);
    expect(adapter.completionCalls, 1);
    releaseFinish.complete();

    final result = await refresh.timeout(_progressTimeout);
    expect(result.status, CommercePurchaserStateStatusCode.available);
    expect(reports, hasLength(2));
    expect(reports.last['reportId'], isNot(reports.first['reportId']));
    expect(
      {...reports.last}..remove('reportId'),
      {...reports.first}..remove('reportId'),
    );
    expect(await queue.open(), isEmpty);
    expect(adapter.completionCalls, 1);
  });

  test('old-X backlog cannot supply or block a fresh Y query attempt',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    await queue.enqueue(
      CommerceReportRecord(
        reportId: '8ba77254-6ab0-4ec8-ae50-f12273ac1f51',
        store: CommerceStore.playStore,
        storeVerificationData: 'shared-proof',
        storeProductId: 'subscription.shared',
        storeTransactionId: 'shared-order',
        applicationAnonymousToken: _applicationToken,
        configurationFingerprint: 'same-scope',
      ),
    );
    const transaction = _TestTransaction(
      store: CommerceStore.playStore,
      status: CommerceStoreTransactionStatus.restored,
      storeProductId: 'subscription.shared',
      storeTransactionId: 'shared-order',
      storeVerificationData: 'shared-proof',
      requiresDeviceCompletion: false,
    );
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
      ownedTransactions: const <CommerceStoreTransaction>[transaction],
    );
    addTearDown(adapter.close);
    final oldStarted = Completer<void>();
    final oldRelease = Completer<http.Response>();
    final reports = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/purchaser-state')) {
        return _jsonResponse(_purchaserState(entitlements: const []).toJson());
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      reports.add(body);
      if (body['appAnonymousToken'] == _applicationToken) {
        oldStarted.complete();
        return oldRelease.future;
      }
      return _jsonResponse(
        _scopedReport(
          scopedEntitlements: [_entitlement('entitlement.shared')],
        ).toJson(),
      );
    });

    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => queue,
      runtimeContextProvider: () => _context(
        fingerprint: 'same-scope',
        token: _secondApplicationToken,
      ),
      usesPurchaserStateHandler: true,
    );
    await oldStarted.future.timeout(_progressTimeout);
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'Y query completes without waiting for old X backlog',
    );
    expect(
      reports.map((report) => report['appAnonymousToken']),
      containsAll({_applicationToken, _secondApplicationToken}),
    );
    expect(
      Restage.commerce.currentState.entitlements.single.entitlementId,
      'entitlement.shared',
    );
    oldRelease.complete(http.Response('', 503));
  });

  test('changed proof stays distinct from a pending provider report', () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    final reports = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/purchaser-state')) {
        return _jsonResponse(
          _purchaserState(
            entitlements: const <EntitlementSummary>[],
            retrievedAt: DateTime.utc(2026, 9, 9),
          ).toJson(),
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      reports.add(body);
      if (body['storeVerificationData'] == 'old-proof') {
        return _jsonResponse(_pendingState().toJson());
      }
      return _jsonResponse(
        _scopedReport(
          scopedEntitlements: [_entitlement('entitlement.new-proof')],
        ).toJson(),
      );
    });
    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => queue,
      usesPurchaserStateHandler: true,
    );
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'initial complete empty snapshot',
    );
    const oldProof = _TestTransaction(
      store: CommerceStore.playStore,
      status: CommerceStoreTransactionStatus.purchased,
      storeProductId: 'subscription.proof',
      storeTransactionId: 'same-provider-order',
      storeVerificationData: 'old-proof',
      requiresDeviceCompletion: false,
    );
    adapter.emit(oldProof);
    await _waitFor(
      () async {
        final records = await queue.open();
        return records.length == 1 && records.single.retryAttempt == 1;
      },
      label: 'old exact proof stays pending',
    );
    adapter.ownedTransactions = const <CommerceStoreTransaction>[
      _TestTransaction(
        store: CommerceStore.playStore,
        status: CommerceStoreTransactionStatus.restored,
        storeProductId: 'subscription.proof',
        storeTransactionId: 'same-provider-order',
        storeVerificationData: 'new-proof',
        requiresDeviceCompletion: false,
      ),
    ];

    final state = await Restage.commerce.refresh();

    expect(state.status, CommercePurchaserStateStatusCode.available);
    expect(state.entitlements.single.entitlementId, 'entitlement.new-proof');
    expect(
      reports.map((report) => report['storeVerificationData']),
      containsAll(<String>['old-proof', 'new-proof']),
    );
    final remaining = await queue.open();
    expect(remaining, hasLength(1));
    expect(remaining.single.storeVerificationData, 'old-proof');
  });

  test('failed admission preserves old and new captured owners', () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final fileQueue = CommerceFileReportQueue(directoryPath: directory.path);
    final queue = _FaultingCommerceReportQueue(
      fileQueue,
      enqueueFailures: 1,
    );
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
    );
    addTearDown(adapter.close);
    var generation = 0;
    var token = _applicationToken;
    CommerceRuntimeContext contextProvider() {
      final capturedGeneration = generation;
      return _context(
        fingerprint: 'owner-scope',
        token: token,
        isCurrent: () => generation == capturedGeneration,
      );
    }

    final heldReports = <Completer<http.Response>>[];
    _activate(
      adapter: adapter,
      client: MockClient((request) async {
        final held = Completer<http.Response>();
        heldReports.add(held);
        return held.future;
      }),
      queueFactory: () async => queue,
      runtimeContextProvider: contextProvider,
    );
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'initial complete empty snapshot',
    );
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.playStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.owner',
        storeTransactionId: 'owner-order',
        storeVerificationData: 'old-owner-proof',
        requiresDeviceCompletion: false,
      ),
    );
    await _waitFor(
      () => queue.enqueueAttempts == 1,
      label: 'old captured owner reaches failed durable admission',
    );

    generation += 1;
    token = _secondApplicationToken;
    notifyRestageCommerceIdentityChanged();
    adapter.emit(
      const _TestTransaction(
        store: CommerceStore.playStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: 'subscription.owner',
        storeTransactionId: 'owner-order',
        storeVerificationData: 'new-owner-proof',
        requiresDeviceCompletion: false,
      ),
    );

    await _waitFor(
      () async => (await fileQueue.open()).length == 2,
      label: 'both independently captured owners become durable',
    );
    final records = await fileQueue.open();
    expect(
      records.map((record) => record.applicationAnonymousToken).toSet(),
      {_applicationToken, _secondApplicationToken},
    );
    expect(
      records.map((record) => record.storeVerificationData).toSet(),
      {'old-owner-proof', 'new-owner-proof'},
    );
    expect(records.map((record) => record.reportId).toSet(), hasLength(2));
    Restage.debugReset();
    for (final held in heldReports) {
      if (!held.isCompleted) held.complete(http.Response('', 503));
    }
  });

  test('native owned-query timeout bounds restore and leaves state non-current',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final heldQuery = Completer<List<CommerceStoreTransaction>>();
    late final _TestStoreAdapter adapter;
    adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
      onQueryOwnedTransactions: () => adapter.ownedQueryCalls == 1
          ? Future<List<CommerceStoreTransaction>>.value(
              const <CommerceStoreTransaction>[],
            )
          : heldQuery.future,
    );
    addTearDown(adapter.close);
    _activate(
      adapter: adapter,
      client: MockClient(
        (_) async => _jsonResponse(_verifiedState().toJson()),
      ),
      journalPath: directory.path,
      networkAttemptTimeout: const Duration(milliseconds: 25),
    );
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'initial complete query',
    );

    final stopwatch = Stopwatch()..start();
    final result = await Restage.commerce.restore();
    stopwatch.stop();

    expect(result.status, CommerceActionStatusCode.failed);
    expect(
      Restage.commerce.currentState.status,
      CommercePurchaserStateStatusCode.stale,
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    heldQuery.complete(const <CommerceStoreTransaction>[]);
  });

  test('restart rebuilds current membership from a new owned-query attempt',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    const transaction = _TestTransaction(
      store: CommerceStore.playStore,
      status: CommerceStoreTransactionStatus.restored,
      storeProductId: 'subscription.restart',
      storeTransactionId: 'restart-order',
      storeVerificationData: 'restart-proof',
      requiresDeviceCompletion: false,
    );
    final reportIds = <String>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/purchaser-state')) {
        return _jsonResponse(_purchaserState(entitlements: const []).toJson());
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      reportIds.add(body['reportId']! as String);
      return _jsonResponse(
        _scopedReport(
          scopedEntitlements: [_entitlement('entitlement.restart')],
        ).toJson(),
      );
    });
    final firstAdapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
      ownedTransactions: const <CommerceStoreTransaction>[transaction],
    );
    addTearDown(firstAdapter.close);
    _activate(
      adapter: firstAdapter,
      client: client,
      journalPath: directory.path,
      usesPurchaserStateHandler: true,
    );
    await _waitFor(
      () => Restage.commerce.currentState.entitlements
          .any((value) => value.entitlementId == 'entitlement.restart'),
      label: 'first engine publishes restored membership',
    );
    await _waitFor(
      () async =>
          (await CommerceFileReportQueue(directoryPath: directory.path).open())
              .isEmpty,
      label: 'first query report is acknowledged',
    );

    Restage.debugReset();
    final restartedAdapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
      ownedTransactions: const <CommerceStoreTransaction>[transaction],
    );
    addTearDown(restartedAdapter.close);
    _activate(
      adapter: restartedAdapter,
      client: client,
      journalPath: directory.path,
      usesPurchaserStateHandler: true,
    );
    await _waitFor(
      () =>
          reportIds.length == 2 &&
          Restage.commerce.currentState.entitlements.any(
            (value) => value.entitlementId == 'entitlement.restart',
          ),
      label: 'restart re-queries and re-verifies restored membership',
    );

    expect(reportIds.toSet(), hasLength(2));
    expect(restartedAdapter.completionCalls, isZero);
  });

  test('ordinary backlog does not resend an acknowledged query member',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    await queue.enqueue(
      CommerceReportRecord(
        reportId: '8ba77254-6ab0-4ec8-ae50-f12273ac1f51',
        store: CommerceStore.playStore,
        storeVerificationData: 'unrelated-proof',
        storeProductId: 'subscription.unrelated',
        storeTransactionId: 'unrelated-order',
        applicationAnonymousToken: _applicationToken,
        configurationFingerprint: 'same-scope',
      ),
    );
    await queue.enqueue(
      CommerceReportRecord(
        reportId: 'fa8e6f40-1bc5-4924-9d3b-bd0b5ec3ed29',
        store: CommerceStore.playStore,
        storeVerificationData: 'owned-proof',
        storeProductId: 'subscription.owned',
        storeTransactionId: 'owned-order',
        applicationAnonymousToken: _applicationToken,
        configurationFingerprint: 'same-scope',
      ),
    );
    final native = Completer<List<CommerceStoreTransaction>>();
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
      onQueryOwnedTransactions: () => native.future,
    );
    addTearDown(adapter.close);
    final unrelatedStarted = Completer<void>();
    final unrelatedRelease = Completer<http.Response>();
    var ownedCalls = 0;
    final durableAtOwnedSend = <bool>[];
    _activate(
      adapter: adapter,
      queueFactory: () async => queue,
      runtimeContextProvider: () => _context(
        fingerprint: 'same-scope',
        token: _applicationToken,
      ),
      usesPurchaserStateHandler: true,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/purchaser-state')) {
          return _jsonResponse(
            _purchaserState(entitlements: const <EntitlementSummary>[])
                .toJson(),
          );
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['storeTransactionId'] == 'unrelated-order') {
          if (!unrelatedStarted.isCompleted) unrelatedStarted.complete();
          return unrelatedRelease.future;
        }
        ownedCalls += 1;
        durableAtOwnedSend.add(
          (await queue.open()).any(
            (record) => record.reportId == body['reportId'],
          ),
        );
        return _jsonResponse(
          _scopedReport(
            scopedEntitlements: [_entitlement('entitlement.owned')],
          ).toJson(),
        );
      }),
    );

    await unrelatedStarted.future.timeout(_progressTimeout);
    native.complete(
      const <CommerceStoreTransaction>[
        _TestTransaction(
          store: CommerceStore.playStore,
          status: CommerceStoreTransactionStatus.restored,
          storeProductId: 'subscription.owned',
          storeTransactionId: 'owned-order',
          storeVerificationData: 'owned-proof',
          requiresDeviceCompletion: false,
        ),
      ],
    );
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'query member is verified and acknowledged',
    );
    expect(ownedCalls, 1);
    expect(
      (await queue.open()).map((record) => record.storeTransactionId),
      ['unrelated-order'],
    );

    unrelatedRelease.complete(_jsonResponse(_emptyVerifiedState().toJson()));
    await _waitFor(
      () async => (await queue.open()).isEmpty,
      label: 'unrelated backlog report is acknowledged',
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(ownedCalls, 1);
    expect(durableAtOwnedSend, everyElement(isTrue));
  });

  test('ordinary backlog respects a query-advanced retry time', () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    await queue.enqueue(
      CommerceReportRecord(
        reportId: '9f34be90-98d1-4ec8-a01c-d1006a9ca36e',
        store: CommerceStore.playStore,
        storeVerificationData: 'unrelated-proof',
        storeProductId: 'subscription.unrelated',
        storeTransactionId: 'unrelated-order',
        applicationAnonymousToken: _applicationToken,
        configurationFingerprint: 'same-scope',
      ),
    );
    await queue.enqueue(
      CommerceReportRecord(
        reportId: 'e2261547-787d-4b83-8874-a1ab8e602179',
        store: CommerceStore.playStore,
        storeVerificationData: 'owned-proof',
        storeProductId: 'subscription.owned',
        storeTransactionId: 'owned-order',
        applicationAnonymousToken: _applicationToken,
        configurationFingerprint: 'same-scope',
      ),
    );
    final native = Completer<List<CommerceStoreTransaction>>();
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
      onQueryOwnedTransactions: () => native.future,
    );
    addTearDown(adapter.close);
    final unrelatedStarted = Completer<void>();
    final unrelatedRelease = Completer<http.Response>();
    var ownedCalls = 0;
    _activate(
      adapter: adapter,
      queueFactory: () async => queue,
      runtimeContextProvider: () => _context(
        fingerprint: 'same-scope',
        token: _applicationToken,
      ),
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['storeTransactionId'] == 'unrelated-order') {
          if (!unrelatedStarted.isCompleted) unrelatedStarted.complete();
          return unrelatedRelease.future;
        }
        ownedCalls += 1;
        return _jsonResponse(_pendingState().toJson());
      }),
    );

    await unrelatedStarted.future.timeout(_progressTimeout);
    native.complete(
      const <CommerceStoreTransaction>[
        _TestTransaction(
          store: CommerceStore.playStore,
          status: CommerceStoreTransactionStatus.restored,
          storeProductId: 'subscription.owned',
          storeTransactionId: 'owned-order',
          storeVerificationData: 'owned-proof',
          requiresDeviceCompletion: false,
        ),
      ],
    );
    await _waitFor(
      () async {
        final owned = (await queue.open()).where(
          (record) => record.storeTransactionId == 'owned-order',
        );
        return owned.length == 1 && owned.single.retryAttempt == 1;
      },
      label: 'query attempt advances the owned row retry time',
    );

    unrelatedRelease.complete(_jsonResponse(_emptyVerifiedState().toJson()));
    await _waitFor(
      () async => (await queue.open()).every(
        (record) => record.storeTransactionId == 'owned-order',
      ),
      label: 'unrelated backlog report is acknowledged',
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final retained = (await queue.open()).single;
    expect(ownedCalls, 1);
    expect(retained.storeTransactionId, 'owned-order');
    expect(retained.retryAttempt, 1);
    expect(retained.nextRetryAt.isAfter(DateTime.now().toUtc()), isTrue);
  });

  test('context change during publication token wait fences Apple finish',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    final finished = Completer<void>();
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
      onComplete: (_) async {
        if (!finished.isCompleted) finished.complete();
      },
    );
    addTearDown(adapter.close);
    var generation = 0;
    var holdOldToken = false;
    final tokenStarted = Completer<void>();
    final tokenRelease = Completer<String?>();

    CommerceRuntimeContext contextProvider() {
      final captured = generation;
      return CommerceRuntimeContext(
        configurationFingerprint: 'same-scope',
        isCurrent: () => captured == generation,
        applicationAnonymousTokenProvider: () async {
          if (captured == 0 && holdOldToken) {
            if (!tokenStarted.isCompleted) tokenStarted.complete();
            return tokenRelease.future;
          }
          return _applicationToken;
        },
      );
    }

    String? reportId;
    _activate(
      adapter: adapter,
      queueFactory: () async => queue,
      runtimeContextProvider: contextProvider,
      client: MockClient((request) async {
        reportId = (jsonDecode(request.body)
            as Map<String, dynamic>)['reportId'] as String;
        holdOldToken = true;
        return _jsonResponse(_verifiedState().toJson());
      }),
    );
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'startup empty query establishes a current snapshot',
    );

    adapter.emit(_applePendingTransaction);
    await tokenStarted.future.timeout(_progressTimeout);
    generation += 1;
    notifyRestageCommerceConfigurationChanged();
    tokenRelease.complete(_applicationToken);
    await expectLater(
      finished.future.timeout(const Duration(milliseconds: 150)),
      throwsA(isA<TimeoutException>()),
    );
    await _waitFor(
      () async {
        final reports = await queue.open();
        return reports.length == 1 && reports.single.retryAttempt == 1;
      },
      label: 'invalidated Apple report remains durable for retry',
    );
    expect(adapter.completionCalls, isZero);
    expect((await queue.open()).single.reportId, reportId);
  });

  test('query-owned acknowledgement failure wakes its retained report retry',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final clock = _HeldClock();
    final fileQueue = CommerceFileReportQueue(
      directoryPath: directory.path,
      clock: clock.now,
    );
    final queue = _FaultingCommerceReportQueue(
      fileQueue,
      acknowledgeFailures: 1,
    );
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
      ownedTransactions: const <CommerceStoreTransaction>[
        _applePendingTransaction,
      ],
    );
    addTearDown(adapter.close);
    final firstStarted = Completer<void>();
    final firstRelease = Completer<http.Response>();
    var reportCalls = 0;
    _activate(
      adapter: adapter,
      queueFactory: () async => queue,
      clock: clock.now,
      client: MockClient((request) async {
        reportCalls += 1;
        if (reportCalls == 1) {
          firstStarted.complete();
          return firstRelease.future;
        }
        return _jsonResponse(
          _scopedReport(
            scopedEntitlements: [_entitlement('entitlement.verified')],
          ).toJson(),
        );
      }),
    );

    await firstStarted.future.timeout(_progressTimeout);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    firstRelease.complete(
      _jsonResponse(
        _scopedReport(
          scopedEntitlements: [_entitlement('entitlement.verified')],
        ).toJson(),
      ),
    );
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'first verified query attempt publishes current access',
    );
    expect((await fileQueue.open()).single.retryAttempt, 1);
    clock.advance(commerceReportRetryDelay(1));
    await _waitFor(
      () async => reportCalls == 2 && (await fileQueue.open()).isEmpty,
      label: 'retained query report retries without an external event',
      timeout: _progressTimeout,
    );
    expect(adapter.completionCalls, 1);
  });

  test('incomplete native and report evidence stays non-current', () async {
    const pending = _TestTransaction(
      store: CommerceStore.playStore,
      status: CommerceStoreTransactionStatus.pending,
      storeProductId: 'subscription.incomplete',
      storeTransactionId: 'incomplete-order',
      storeVerificationData: 'incomplete-proof',
      requiresDeviceCompletion: false,
    );
    const purchased = _TestTransaction(
      store: CommerceStore.playStore,
      status: CommerceStoreTransactionStatus.purchased,
      storeProductId: 'subscription.incomplete',
      storeTransactionId: 'incomplete-order',
      storeVerificationData: 'incomplete-proof',
      requiresDeviceCompletion: false,
    );
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    // Held time keeps a retained report from retrying between refreshes.
    final clock = _HeldClock();
    final adapter = _TestStoreAdapter(
      store: CommerceStore.playStore,
      products: const <CommerceStoreProduct>[],
      ownedTransactions: const <CommerceStoreTransaction>[pending],
    );
    addTearDown(adapter.close);
    var responseKind = 'pending';
    var reportCalls = 0;
    final client = MockClient((request) async {
      reportCalls += 1;
      return _jsonResponse(
        switch (responseKind) {
          'pending' => _pendingState().toJson(),
          'missing' => _scopedReport(
              scopedEntitlements: const <EntitlementSummary>[],
              includeScopedState: false,
            ).toJson(),
          'rejected' => _scopedReport(
              scopedEntitlements: const <EntitlementSummary>[],
              outcome: 'rejected',
            ).toJson(),
          _ => _scopedReport(
              scopedEntitlements: [_entitlement('entitlement.complete')],
            ).toJson(),
        },
      );
    });
    _activate(
      adapter: adapter,
      client: client,
      queueFactory: () async => CommerceFileReportQueue(
        directoryPath: directory.path,
        clock: clock.now,
      ),
      clock: clock.now,
    );
    await _waitFor(
      () => adapter.ownedQueryCalls == 1,
      label: 'startup native query completes',
    );
    expect(reportCalls, isZero);
    expect(
      Restage.commerce.currentState.status,
      CommercePurchaserStateStatusCode.stale,
    );

    adapter.ownedTransactions = const <CommerceStoreTransaction>[purchased];
    expect(
      (await Restage.commerce.refresh()).status,
      CommercePurchaserStateStatusCode.stale,
    );
    responseKind = 'missing';
    expect(
      (await Restage.commerce.refresh()).status,
      CommercePurchaserStateStatusCode.stale,
    );
    responseKind = 'rejected';
    expect(
      (await Restage.commerce.refresh()).status,
      CommercePurchaserStateStatusCode.stale,
    );
    responseKind = 'verified';
    final current = await Restage.commerce.refresh();
    expect(current.status, CommercePurchaserStateStatusCode.available);
    expect(current.entitlements.single.entitlementId, 'entitlement.complete');
    expect(reportCalls, 4);
  });

  test('verified proof grants while local acknowledgement retries', () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    // The clock holds the retry backoff, so the report stays retained.
    final clock = _HeldClock();
    final fileQueue = CommerceFileReportQueue(
      directoryPath: directory.path,
      clock: clock.now,
    );
    final queue = _FaultingCommerceReportQueue(
      fileQueue,
      acknowledgeFailures: 1,
    );
    const transaction = _TestTransaction(
      store: CommerceStore.appStore,
      status: CommerceStoreTransactionStatus.purchased,
      storeProductId: 'subscription.ack',
      storeTransactionId: 'ack-order',
      storeVerificationData: 'ack-jws',
      requiresDeviceCompletion: true,
    );
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
      ownedTransactions: const <CommerceStoreTransaction>[transaction],
    );
    addTearDown(adapter.close);
    _activate(
      adapter: adapter,
      client: MockClient(
        (_) async => _jsonResponse(
          _scopedReport(
            scopedEntitlements: [_entitlement('entitlement.ack')],
          ).toJson(),
        ),
      ),
      queueFactory: () async => queue,
      clock: clock.now,
    );

    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'verified scoped proof publishes despite local ack failure',
    );
    expect(Restage.commerce.currentState.entitlements, hasLength(1));
    expect(adapter.completionCalls, 1);
    final retained = await fileQueue.open();
    expect(retained, hasLength(1));
    expect(retained.single.retryAttempt, 1);
  });

  test('Apple verified empty scope still finishes the purchased duplicate once',
      () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    const restored = _TestTransaction(
      store: CommerceStore.appStore,
      status: CommerceStoreTransactionStatus.restored,
      storeProductId: 'subscription.apple',
      storeTransactionId: 'apple-owned-order',
      storeVerificationData: 'apple-owned-jws',
      requiresDeviceCompletion: false,
    );
    const purchased = _TestTransaction(
      store: CommerceStore.appStore,
      status: CommerceStoreTransactionStatus.purchased,
      storeProductId: 'subscription.apple',
      storeTransactionId: 'apple-owned-order',
      storeVerificationData: 'apple-owned-jws',
      requiresDeviceCompletion: true,
    );
    final completed = Completer<CommerceStoreTransaction>();
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[],
      ownedTransactions: const <CommerceStoreTransaction>[
        restored,
        purchased,
      ],
      onComplete: (transaction) async => completed.complete(transaction),
    );
    addTearDown(adapter.close);
    final client = MockClient(
        (request) async => request.url.path.endsWith('/purchaser-state')
            ? _jsonResponse(_purchaserState(entitlements: const []).toJson())
            : _jsonResponse(
                _scopedReport(scopedEntitlements: const []).toJson(),
              ));

    _activate(
      adapter: adapter,
      client: client,
      journalPath: directory.path,
      usesPurchaserStateHandler: true,
    );
    expect(
      await completed.future.timeout(_progressTimeout),
      same(purchased),
    );
    await _waitFor(
      () =>
          Restage.commerce.currentState.status ==
          CommercePurchaserStateStatusCode.available,
      label: 'verified empty Apple scope publishes current canonical state',
    );
    expect(adapter.completionCalls, 1);
    expect(Restage.commerce.currentState.entitlements, isEmpty);
  });

  for (final variation in <String>[
    'same subject',
    'context change',
    'different owner',
    'different proof',
  ]) {
    test('Apple owned-query deadline retains native finish: $variation',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('restage-native-deadline-');
      addTearDown(() => _deleteAfterCommerceStops(directory));
      final fileQueue = CommerceFileReportQueue(directoryPath: directory.path);
      final matching =
          variation == 'same subject' || variation == 'context change';
      final CommerceReportQueue queue = variation == 'same subject'
          ? _FailFirstAcknowledgementQueue(fileQueue)
          : fileQueue;
      final finishStarted = Completer<void>();
      final releaseFinish = Completer<void>();
      final reports = <Map<String, dynamic>>[];
      var owner = _applicationToken;
      late final _TestStoreAdapter adapter;
      adapter = _TestStoreAdapter(
        store: CommerceStore.appStore,
        products: const <CommerceStoreProduct>[],
        onComplete: (_) async {
          if (adapter.completionCalls == 1) {
            finishStarted.complete();
            await releaseFinish.future;
          }
        },
      );
      addTearDown(adapter.close);
      addTearDown(() {
        if (!releaseFinish.isCompleted) releaseFinish.complete();
      });
      final deadline = _ControlledAttemptDeadline();
      _activate(
        adapter: adapter,
        queueFactory: () async => queue,
        runtimeContextProvider: () => _context(
          fingerprint: 'native-deadline-scope',
          token: owner,
        ),
        attemptDeadline: deadline,
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final saved = (await queue.open()).singleWhere(
            (record) => record.reportId == body['reportId'],
          );
          expect(saved.applicationAnonymousToken, body['appAnonymousToken']);
          expect(saved.storeVerificationData, body['storeVerificationData']);
          reports.add(body);
          return _jsonResponse(
            _scopedReport(scopedEntitlements: const <EntitlementSummary>[])
                .toJson(),
          );
        }),
      );
      await _waitFor(
        () =>
            Restage.commerce.currentState.status ==
            CommercePurchaserStateStatusCode.available,
        label: 'initial complete empty snapshot',
      );
      adapter.ownedTransactions = const <CommerceStoreTransaction>[
        _applePendingTransaction,
      ];
      final restore = Restage.commerce.restore();
      await finishStarted.future.timeout(_progressTimeout);
      // The native finish is held, so the restore attempt expires.
      deadline.expirePending();
      expect((await restore).status, CommerceActionStatusCode.failed);
      expect(Restage.commerce.currentState.status,
          CommercePurchaserStateStatusCode.stale);
      expect(adapter.completionCalls, 1);
      expect(reports, hasLength(1));
      final original = (await queue.open()).single;

      if (variation == 'different owner') owner = _secondApplicationToken;
      final queried = _TestTransaction(
        store: CommerceStore.appStore,
        status: CommerceStoreTransactionStatus.purchased,
        storeProductId: _applePendingTransaction.storeProductId,
        storeTransactionId: _applePendingTransaction.storeTransactionId,
        storeVerificationData: variation == 'different proof'
            ? 'renewed.apple.transaction.jws'
            : _applePendingTransaction.storeVerificationData,
        requiresDeviceCompletion: true,
      );
      adapter.ownedTransactions = <CommerceStoreTransaction>[queried];
      // A new caller has a deadline, while the original native finish remains
      // live. Exact-subject collisions keep its owner; other subjects proceed.
      final retrying = Restage.commerce.refresh();
      if (matching) {
        // Expire the caller once it waits on the live native finish.
        await _waitFor(
          () => deadline.pending >= 2,
          label: 'retry waits on the live native finish',
        );
        deadline.expirePending();
      }
      final retried = await retrying.timeout(_progressTimeout);
      expect(adapter.completionCalls, matching ? 1 : 2);
      expect(
        retried.status,
        matching
            ? CommercePurchaserStateStatusCode.stale
            : CommercePurchaserStateStatusCode.available,
      );
      expect(reports, hasLength(matching ? 1 : 2));
      final retained = (await queue.open()).single;
      expect(retained.hasSameContents(original), isTrue);
      expect(retained.applicationAnonymousToken, _applicationToken);
      if (!matching) {
        expect(reports.last['reportId'], isNot(original.reportId));
        expect(reports.last['appAnonymousToken'], owner);
        expect(reports.last['storeVerificationData'],
            queried.storeVerificationData);
      }

      if (variation == 'context change') {
        notifyRestageCommerceIdentityChanged();
        await _waitFor(
          () => adapter.ownedQueryCalls >= 4,
          label: 'new context queries while original native finish is live',
        );
      }
      releaseFinish.complete();
      if (variation == 'same subject') {
        await _waitFor(
          () async => (await queue.open()).single.retryAttempt == 1,
          label: 'late native success survives failed acknowledgement',
        );
        final fresh = await Restage.commerce.refresh();
        expect(fresh.status, CommercePurchaserStateStatusCode.available);
        expect(reports, hasLength(2));
        expect(reports.last, reports.first);
      }
      await _waitFor(
        () async => (await queue.open()).isEmpty,
        label: 'original native completion eventually acknowledges',
      );
      if (variation == 'context change') {
        await _waitFor(
          () =>
              Restage.commerce.currentState.status ==
              CommercePurchaserStateStatusCode.available,
          label: 'fresh context publishes after late native completion',
        );
        expect(reports, hasLength(2));
        expect(reports.last, reports.first);
        expect(Restage.commerce.currentState.status,
            CommercePurchaserStateStatusCode.available);
      }
      expect(adapter.completionCalls, matching ? 1 : 2);
    });
  }

  test('declines an unknown intent status before any store call', () async {
    final directory = await Directory.systemTemp.createTemp('restage-engine-');
    addTearDown(() => _deleteAfterCommerceStops(directory));
    final adapter = _TestStoreAdapter(
      store: CommerceStore.appStore,
      products: const <CommerceStoreProduct>[
        _TestStoreProduct(
          store: CommerceStore.appStore,
          storeProductId: 'subscription.monthly',
        ),
      ],
    );
    addTearDown(adapter.close);
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _jsonResponse(
        CommerceIntentResponse(
          intentId: body['intentId']! as String,
          status: 'future_hold',
          resolved: CommerceResolvedPurchasable(
            storeProductId: 'subscription.monthly',
            productKind: 'autoRenewableSubscription',
            appAccountToken: _appAccountToken,
          ),
        ).toJson(),
      );
    });

    _activate(adapter: adapter, client: client, journalPath: directory.path);
    final result = await Restage.commerce.purchase(
      CommercePurchaseRequest(CommerceOfferId('offer.monthly')),
    );

    expect(result.status, CommerceActionStatusCode.failed);
    expect(result.failureCode, CommerceFailureCode.unsupportedResponse);
    expect(adapter.queryCalls, isZero);
    expect(adapter.startCalls, isZero);
  });
}

void _activate({
  required _TestStoreAdapter adapter,
  required http.Client client,
  String? journalPath,
  Future<CommerceReportQueue> Function()? queueFactory,
  CommerceRuntimeContext? Function()? runtimeContextProvider,
  RestageRpcClient? Function()? rpcClientProvider,
  Duration networkAttemptTimeout = const Duration(seconds: 15),
  CommerceAttemptDeadline? attemptDeadline,
  DateTime Function() clock = DateTime.now,
  bool usesPurchaserStateHandler = false,
}) {
  final routedClient = _TestCommerceClient(
    client,
    usesPurchaserStateHandler: usesPurchaserStateHandler,
  );
  activateRestageCommerce(
    adapter,
    rpcClientProvider: rpcClientProvider ??
        (() => RestageRpcClient(
              baseUrl: 'https://api.example.com',
              apiKey: 'rs_pk_test',
              httpClient: routedClient,
            )),
    applicationAnonymousTokenProvider: () async => _applicationToken,
    runtimeContextProvider: runtimeContextProvider,
    reportQueueFactory: queueFactory ??
        () async => CommerceFileReportQueue(directoryPath: journalPath!),
    attemptDeadline:
        attemptDeadline ?? CommerceAttemptDeadline(networkAttemptTimeout),
    clock: clock,
  );
}

/// Time that moves only when the test advances it, so retry backoff is held.
final class _HeldClock {
  DateTime _now = DateTime.now().toUtc();

  DateTime now() => _now;

  void advance(Duration duration) => _now = _now.add(duration);
}

/// Attempts expire only when the test calls [expirePending].
final class _ControlledAttemptDeadline extends CommerceAttemptDeadline {
  final Set<void Function()> _pending = <void Function()>{};

  /// How many attempts are still running.
  int get pending => _pending.length;

  @override
  Future<T> bound<T>(Future<T> attempt) {
    final result = Completer<T>();
    late final void Function() expire;
    expire = () {
      _pending.remove(expire);
      if (!result.isCompleted) {
        result.completeError(TimeoutException('commerce attempt expired'));
      }
    };
    _pending.add(expire);
    attempt.then(
      (value) {
        _pending.remove(expire);
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        _pending.remove(expire);
        if (!result.isCompleted) result.completeError(error, stackTrace);
      },
    );
    return result.future;
  }

  void expirePending() {
    for (final expire in List<void Function()>.of(_pending)) {
      expire();
    }
  }
}

final class _TestCommerceClient extends http.BaseClient {
  _TestCommerceClient(
    this._delegate, {
    required this.usesPurchaserStateHandler,
  });

  final http.Client _delegate;
  final bool usesPurchaserStateHandler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!usesPurchaserStateHandler &&
        request.url.path.endsWith('/purchaser-state')) {
      final response = _purchaserState(
        entitlements: const <EntitlementSummary>[],
        retrievedAt: DateTime.utc(2026, 9),
      );
      return Future<http.StreamedResponse>.value(
        http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(jsonEncode(response.toJson()))),
          200,
          headers: const <String, String>{
            'content-type': 'application/json',
          },
        ),
      );
    }
    return _delegate.send(request);
  }
}

CommerceRuntimeContext _context({
  required String fingerprint,
  required String token,
  bool Function()? isCurrent,
}) =>
    CommerceRuntimeContext(
      configurationFingerprint: fingerprint,
      applicationAnonymousTokenProvider: () async => token,
      isCurrent: isCurrent,
    );

CommerceReportResponse _verifiedState() => CommerceReportResponse(
      outcome: 'verified',
      purchaserState: CommercePurchaserStateResponse(
        status: 'current',
        entitlements: <EntitlementSummary>[
          EntitlementSummary(
            entitlementId: 'subscription.monthly',
            status: 'active',
            productId: 'subscription.monthly',
            source: 'clientReport',
          ),
        ],
        retrievedAt: DateTime.utc(2026, 9, 5),
      ),
    );

CommerceReportResponse _emptyVerifiedState() => CommerceReportResponse(
      outcome: 'verified',
      purchaserState: CommercePurchaserStateResponse(
        status: 'current',
        entitlements: const <EntitlementSummary>[],
        retrievedAt: DateTime.utc(2026, 9, 6),
      ),
    );

CommerceReportResponse _pendingState() => CommerceReportResponse(
      outcome: 'pending',
      purchaserState: CommercePurchaserStateResponse(
        status: 'unknown',
        entitlements: const <EntitlementSummary>[],
        retrievedAt: DateTime.utc(2026, 9, 5),
      ),
    );

CommercePurchaserStateResponse _purchaserState({
  required List<EntitlementSummary> entitlements,
  DateTime? retrievedAt,
  String status = 'current',
}) =>
    CommercePurchaserStateResponse(
      status: status,
      entitlements: entitlements,
      retrievedAt: retrievedAt ?? DateTime.utc(2026, 9, 8),
    );

CommerceReportResponse _scopedReport({
  required List<EntitlementSummary> scopedEntitlements,
  List<EntitlementSummary> ordinaryEntitlements = const <EntitlementSummary>[],
  String outcome = 'verified',
  bool includeScopedState = true,
  DateTime? retrievedAt,
}) =>
    CommerceReportResponse(
      outcome: outcome,
      purchaserState: _purchaserState(
        entitlements: ordinaryEntitlements,
        retrievedAt: retrievedAt,
      ),
      verifiedPurchaseState: includeScopedState
          ? _purchaserState(
              entitlements: scopedEntitlements,
              retrievedAt: retrievedAt,
            )
          : null,
    );

EntitlementSummary _entitlement(
  String entitlementId, {
  String? productId,
  String status = 'active',
  int? expiresAtMs,
}) =>
    EntitlementSummary(
      entitlementId: entitlementId,
      status: status,
      expiresAtMs: expiresAtMs,
      productId: productId ?? entitlementId,
      source: 'clientReport',
    );

const _TestTransaction _applePendingTransaction = _TestTransaction(
  store: CommerceStore.appStore,
  status: CommerceStoreTransactionStatus.purchased,
  storeProductId: 'subscription.monthly',
  storeTransactionId: 'apple-pending-transaction',
  storeVerificationData: 'pending.apple.transaction.jws',
  requiresDeviceCompletion: true,
);

http.Response _jsonResponse(
  Map<String, dynamic> body, {
  int statusCode = 200,
}) =>
    http.Response(jsonEncode(body), statusCode, headers: const <String, String>{
      'content-type': 'application/json',
    });

/// Stops commerce before deleting its journal, so no write lands mid-delete.
Future<void> _deleteAfterCommerceStops(Directory directory) async {
  await debugResetRestageCommerce().timeout(_progressTimeout);
  await directory.delete(recursive: true);
}

// A hang guard for progress the test expects. Real file and stream work
// behind it takes longer on a loaded machine.
const _progressTimeout = Duration(seconds: 10);

Future<void> _waitFor(
  FutureOr<bool> Function() condition, {
  String? label,
  Duration timeout = _progressTimeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(label ?? 'Condition did not become true');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

// Observe only the atomically published journal. Opening a competing queue
// would run startup cleanup against the engine's in-progress temporary file.
Future<List<CommerceReportRecord>> _publishedReports(String journalPath) async {
  final json =
      jsonDecode(await File('$journalPath/reports.json').readAsString())
          as Map<String, dynamic>;
  return (json['records'] as List<dynamic>)
      .map((record) => CommerceReportRecord.fromJson(
            (record as Map<String, dynamic>).cast<String, Object?>(),
          ))
      .toList(growable: false);
}

Future<Directory> _rootCommerceStorage() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{
    'restage.analytics.anonymous_id': _applicationToken,
  });
  final directory =
      await Directory.systemTemp.createTemp('restage-root-commerce-');
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          pathProvider,
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? directory.path
              : null);
  addTearDown(() async {
    await Restage.debugResetAndWait();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await directory.delete(recursive: true);
  });
  return directory;
}

// Hold only the first acknowledgement's atomic rename. All file operations
// and queue admission/dedup/serialization otherwise use the real file journal.
final class _GatedAcknowledgementFile implements File {
  _GatedAcknowledgementFile(this.inner);

  final File inner;
  final acknowledgementStarted = Completer<void>();
  final release = Completer<void>();
  int _renames = 0;

  @override
  Future<File> rename(String path) async {
    _renames += 1;
    if (_renames == 2) {
      acknowledgementStarted.complete();
      await release.future;
    }
    return inner.rename(path);
  }

  @override
  Future<bool> exists() => inner.exists();

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      inner.delete(recursive: recursive);

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      inner.open(mode: mode);

  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      inner.readAsString(encoding: encoding);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ObserveSecondEnqueueQueue implements CommerceReportQueue {
  _ObserveSecondEnqueueQueue(this.inner, this.secondEnqueue);

  final CommerceFileReportQueue inner;
  final Completer<CommerceReportRecord> secondEnqueue;
  int _enqueues = 0;

  @override
  Future<CommerceReportRecord> enqueue(CommerceReportRecord record) {
    final result = inner.enqueue(record);
    _enqueues += 1;
    if (_enqueues == 2) secondEnqueue.complete(record);
    return result;
  }

  @override
  Future<void> acknowledge(String reportId) => inner.acknowledge(reportId);

  @override
  Future<List<CommerceReportRecord>> open() => inner.open();

  @override
  Future<List<CommerceReportRecord>> due() => inner.due();

  @override
  Future<CommerceReportRecord?> scheduleRetry(String reportId) =>
      inner.scheduleRetry(reportId);
}

final class _ObserveCompletedEnqueueQueue implements CommerceReportQueue {
  _ObserveCompletedEnqueueQueue(
      this.inner, this.observedEnqueue, this.completed);

  final CommerceFileReportQueue inner;
  final int observedEnqueue;
  final Completer<CommerceReportRecord> completed;
  int _enqueues = 0;

  @override
  Future<CommerceReportRecord> enqueue(CommerceReportRecord record) async {
    final result = await inner.enqueue(record);
    _enqueues += 1;
    if (_enqueues == observedEnqueue) completed.complete(result);
    return result;
  }

  @override
  Future<void> acknowledge(String reportId) => inner.acknowledge(reportId);

  @override
  Future<List<CommerceReportRecord>> open() => inner.open();

  @override
  Future<List<CommerceReportRecord>> due() => inner.due();

  @override
  Future<CommerceReportRecord?> scheduleRetry(String reportId) =>
      inner.scheduleRetry(reportId);
}

final class _FailFirstAcknowledgementQueue implements CommerceReportQueue {
  _FailFirstAcknowledgementQueue(this.inner);

  final CommerceFileReportQueue inner;
  bool _failFirstAcknowledgement = true;

  @override
  Future<void> acknowledge(String reportId) async {
    if (!_failFirstAcknowledgement) return inner.acknowledge(reportId);
    _failFirstAcknowledgement = false;
    final obstruction = Directory('${inner.directoryPath}/reports.json.tmp');
    await obstruction.create();
    try {
      await inner.acknowledge(reportId);
    } finally {
      await obstruction.delete();
    }
  }

  @override
  Future<List<CommerceReportRecord>> open() => inner.open();

  @override
  Future<List<CommerceReportRecord>> due() => inner.due();

  @override
  Future<CommerceReportRecord> enqueue(CommerceReportRecord record) =>
      inner.enqueue(record);

  @override
  Future<CommerceReportRecord?> scheduleRetry(String reportId) =>
      inner.scheduleRetry(reportId);
}

final class _TestStoreAdapter implements CommerceStoreAdapter {
  _TestStoreAdapter({
    required this.store,
    required this.products,
    this.onComplete,
    this.onQueryOwnedTransactions,
    this.onStartPurchase,
    List<CommerceStoreTransaction>? ownedTransactions,
  }) : ownedTransactions =
            ownedTransactions ?? const <CommerceStoreTransaction>[];

  @override
  final CommerceStore store;
  final List<CommerceStoreProduct> products;
  final Future<void> Function(CommerceStoreTransaction transaction)? onComplete;
  final Future<List<CommerceStoreTransaction>> Function()?
      onQueryOwnedTransactions;
  final Future<bool> Function(CommerceStorePurchasable purchasable)?
      onStartPurchase;
  final StreamController<CommerceStoreTransaction> _transactions =
      StreamController<CommerceStoreTransaction>.broadcast();
  List<CommerceStoreTransaction> ownedTransactions;
  Set<String>? queriedProductIds;
  CommerceStorePurchasable? startedPurchasable;
  int queryCalls = 0;
  int startCalls = 0;
  int completionCalls = 0;
  int restoreCalls = 0;
  int ownedQueryCalls = 0;

  @override
  Stream<CommerceStoreTransaction> get transactions => _transactions.stream;

  @override
  Future<void> completeTransaction(CommerceStoreTransaction transaction) async {
    completionCalls += 1;
    await onComplete?.call(transaction);
  }

  @override
  Future<List<CommerceStoreProduct>> queryProducts(
    Set<String> storeProductIds,
  ) async {
    queryCalls += 1;
    queriedProductIds = storeProductIds;
    return products;
  }

  @override
  Future<List<CommerceStoreTransaction>> queryOwnedTransactions() async {
    ownedQueryCalls += 1;
    return onQueryOwnedTransactions?.call() ?? ownedTransactions;
  }

  @override
  Future<void> restore() async {
    restoreCalls += 1;
  }

  @override
  Future<bool> startPurchase(CommerceStorePurchasable purchasable) async {
    startCalls += 1;
    startedPurchasable = purchasable;
    return onStartPurchase?.call(purchasable) ?? Future<bool>.value(true);
  }

  void emit(CommerceStoreTransaction transaction) =>
      _transactions.add(transaction);

  Future<void> close() => _transactions.close();
}

final class _FaultingCommerceReportQueue implements CommerceReportQueue {
  _FaultingCommerceReportQueue(
    this.delegate, {
    this.enqueueFailures = 0,
    this.acknowledgeFailures = 0,
    this.onDueCompleted,
  });

  final CommerceReportQueue delegate;
  int enqueueFailures;
  int acknowledgeFailures;
  int enqueueAttempts = 0;
  final void Function()? onDueCompleted;

  @override
  Future<List<CommerceReportRecord>> open() => delegate.open();

  @override
  Future<CommerceReportRecord> enqueue(CommerceReportRecord record) {
    enqueueAttempts += 1;
    if (enqueueFailures > 0) {
      enqueueFailures -= 1;
      throw StateError('injected enqueue failure');
    }
    return delegate.enqueue(record);
  }

  @override
  Future<List<CommerceReportRecord>> due() {
    final callback = onDueCompleted;
    if (callback == null) return delegate.due();
    final result = Completer<List<CommerceReportRecord>>();
    unawaited(
      delegate.due().then(
        (records) {
          result.complete(records);
          scheduleMicrotask(callback);
        },
        onError: result.completeError,
      ),
    );
    return result.future;
  }

  @override
  Future<CommerceReportRecord?> scheduleRetry(String reportId) =>
      delegate.scheduleRetry(reportId);

  @override
  Future<void> acknowledge(String reportId) {
    if (acknowledgeFailures > 0) {
      acknowledgeFailures -= 1;
      throw StateError('injected acknowledgement failure');
    }
    return delegate.acknowledge(reportId);
  }
}

final class _TestStoreProduct implements CommerceStoreProduct {
  const _TestStoreProduct({
    required this.store,
    required this.storeProductId,
  });

  @override
  final CommerceStore store;
  @override
  final String storeProductId;
  @override
  String? get basePlanId => null;
  @override
  String? get storeOfferIdentifier => null;
  @override
  CommerceStoreProductKind get kind => CommerceStoreProductKind.subscription;
}

final class _TestTransaction implements CommerceStoreTransaction {
  const _TestTransaction({
    required this.store,
    required this.status,
    required this.storeProductId,
    required this.storeTransactionId,
    required this.storeVerificationData,
    required this.requiresDeviceCompletion,
  });

  @override
  final CommerceStore store;
  @override
  final CommerceStoreTransactionStatus status;
  @override
  final String storeProductId;
  @override
  final String? storeTransactionId;
  @override
  final String? storeVerificationData;
  @override
  final bool requiresDeviceCompletion;
}
