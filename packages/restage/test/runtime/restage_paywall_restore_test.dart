import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart';

class _StaticResolver implements VariantResolver {
  _StaticResolver(this.bytes);
  final Uint8List bytes;
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(bytes: bytes, paywallId: id);
}

/// Fake [BillingGateway] returning a fixed [RestoreOutcome].
class _FakeGateway implements BillingGateway {
  _FakeGateway({required this.onRestore});

  final Future<RestoreOutcome> Function() onRestore;
  final List<String> calls = <String>[];

  @override
  Future<PurchaseOutcome> purchase(String productId,
      {String? basePlanId}) async {
    return PurchaseOutcome.failed(
      productId: productId,
      errorCode: 'unsupported',
      message: 'fake gateway: purchase not used in this test',
    );
  }

  @override
  Future<RestoreOutcome> restore() {
    calls.add('restore');
    return onRestore();
  }
}

void main() {
  setUp(() => Restage.debugReset());

  testWidgets(
      'RestoreInitiated -> BillingGateway.restore -> RestoreSucceeded + entitlement granted',
      (tester) async {
    Restage.configure(
      apiKey: 'pk_test',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
      billingGateway: _FakeGateway(
        onRestore: () async => RestoreOutcome.succeeded(
          restoredProductIds: const <String>['pro_monthly'],
        ),
      ),
    );

    const source = '''
      import restage.core;
      import restage.material;
      widget Paywall = TextButton(
        onPressed: event 'restage.restore' { },
        child: Text(text: "Restore"),
      );
    ''';
    final bytes =
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));

    final received = <RestageEvent>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: _StaticResolver(bytes),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    final names = received.map((e) => e.name).toList();
    expect(names, contains('restore_initiated'));
    expect(names, contains('restore_succeeded'));

    final succeeded =
        received.firstWhere((e) => e is RestoreSucceeded) as RestoreSucceeded;
    expect(succeeded.restoredProductIds, const <String>['pro_monthly']);

    expect(
      Restage.currentEntitlements.any(
        (e) => e.id == 'pro' && e.source == EntitlementSource.restore,
      ),
      isTrue,
    );
  });

  testWidgets('RestoreOutcomeNoPurchases -> RestoreNoPurchases, no entitlement',
      (tester) async {
    Restage.configure(
      apiKey: 'pk_test',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
      billingGateway: _FakeGateway(
        onRestore: () async => RestoreOutcome.noPurchases(),
      ),
    );

    const source = '''
      import restage.core;
      import restage.material;
      widget Paywall = TextButton(
        onPressed: event 'restage.restore' { },
        child: Text(text: "Restore"),
      );
    ''';
    final bytes =
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));

    final received = <RestageEvent>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: _StaticResolver(bytes),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    final names = received.map((e) => e.name).toList();
    expect(names, contains('restore_initiated'));
    expect(names, contains('restore_no_purchases'));
    expect(Restage.currentEntitlements, isEmpty);
  });

  testWidgets('RestoreOutcomeFailed -> RestoreFailed, no entitlement',
      (tester) async {
    Restage.configure(
      apiKey: 'pk_test',
      products: const [
        RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      ],
      billingGateway: _FakeGateway(
        onRestore: () async => RestoreOutcome.failed(
          errorCode: 'network_error',
          message: 'connection lost',
        ),
      ),
    );

    const source = '''
      import restage.core;
      import restage.material;
      widget Paywall = TextButton(
        onPressed: event 'restage.restore' { },
        child: Text(text: "Restore"),
      );
    ''';
    final bytes =
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));

    final received = <RestageEvent>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: _StaticResolver(bytes),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    final names = received.map((e) => e.name).toList();
    expect(names, contains('restore_initiated'));
    expect(names, contains('restore_failed'));

    final failed =
        received.firstWhere((e) => e is RestoreFailed) as RestoreFailed;
    expect(failed.errorCode, 'network_error');
    expect(failed.message, 'connection lost');
    expect(Restage.currentEntitlements, isEmpty);
  });
}
