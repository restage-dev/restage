import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The install call the assertion has to name for a developer to act on it.
const String _installCall =
    'InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn())';

class _TextPaywallResolver implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    const source = '''
      import restage.core;
      widget Paywall = Text(text: "Upgrade");
    ''';
    return ResolvedVariant(
      bytes: Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source))),
      surfaceVersion: 'test',
      paywallId: id,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Restage.debugReset();
    // The state of an app that never installed anything.
    InstalledWidgetLibraries.reset();
  });

  // Restore what every other test in this package mounts against.
  tearDown(
    () => InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn()),
  );

  testWidgets(
    'mounting a paywall with no widget libraries installed fails with a '
    'message naming the install call',
    (tester) async {
      final received = <RestageEvent>[];
      RestagePaywallError? captured;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RestagePaywall(
            id: 'nothing-installed',
            resolver: _TextPaywallResolver(),
            onEvent: received.add,
            errorBuilder: (context, error) {
              captured = error;
              return const Text('Unavailable');
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // The runtime is assembled outside a build, so the assertion is reported
      // to the developer rather than routed through an error boundary.
      final thrown = tester.takeException();
      expect(thrown, isA<AssertionError>());
      expect(thrown.toString(), contains(_installCall));
      expect(thrown.toString(), contains('can resolve no widget'));
      expect(
        thrown.toString(),
        contains('mounted through its generated reference'),
      );

      // The same message reaches the host through the load failure.
      expect(captured?.cause, same(thrown));
      expect(captured?.message, contains(_installCall));
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.text('Upgrade'), findsNothing);

      final failures = received.whereType<PaywallLoadFailed>();
      expect(failures, hasLength(1));
      expect(failures.first.message, contains(_installCall));
    },
  );
}
