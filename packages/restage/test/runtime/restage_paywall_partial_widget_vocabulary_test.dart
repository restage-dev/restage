import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drawn by a widget the app did install, so a miss proves the one absent
/// widget failed rather than that nothing was installed.
const String _installedLabel = 'Upgrade';

/// A real catalog widget the narrow installation below deliberately omits.
const String _absentWidget = 'Chip';

class _PartialVocabularyResolver implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    const source = '''
      import restage.core;
      import restage.material;
      widget Paywall = Column(
        children: [
          Text(text: "$_installedLabel"),
          Chip(label: Text(text: "Pro")),
        ],
      );
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
    // The shipped shape: the widgets this app's own surfaces draw are
    // installed, and the one the served blob adds is not.
    InstalledWidgetLibraries.install(
      const RestageWidgetLibraries.fromVocabulary(
        core: <String, LocalWidgetBuilder>{
          'Column': buildColumn,
          'Text': buildText,
        },
        material: <String, LocalWidgetBuilder>{'Icon': buildIcon},
      ),
    );
  });

  // Restore what every other test in this package mounts against.
  tearDown(
    () => InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn()),
  );

  testWidgets(
    'a paywall naming one widget the installed libraries omit renders the '
    'fallback instead of a partial surface',
    (tester) async {
      final received = <RestageEvent>[];
      RestagePaywallError? captured;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RestagePaywall(
            id: 'partial-vocabulary',
            resolver: _PartialVocabularyResolver(),
            onEvent: received.add,
            errorBuilder: (context, error) {
              captured = error;
              return const Text('Unavailable');
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // The failure is contained: nothing escapes to the host.
      expect(tester.takeException(), isNull);

      // The caller's fallback is what the user sees.
      expect(find.text('Unavailable'), findsOneWidget);
      expect(captured?.code, RestageErrorCodes.renderError);
      expect(captured?.message, contains(_absentWidget));

      // The miss reaches the host as a load failure naming the widget.
      final failures = received.whereType<PaywallLoadFailed>();
      expect(failures, hasLength(1));
      expect(failures.first.errorCode, RestageErrorCodes.renderError);
      expect(failures.first.message, contains(_absentWidget));

      // The half that resolved is not left painted beside the fallback.
      expect(find.text(_installedLabel), findsNothing);
      expect(find.byType(Chip), findsNothing);
    },
  );
}
