import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart';

import '../support/restage_runtime_test_support.dart';

class _LegacyIconResolver implements VariantResolver {
  _LegacyIconResolver(this.mirroring);

  final bool? mirroring;

  @override
  Future<ResolvedVariant> resolve(String id,
      {String? placementId, Locale? locale}) async {
    final flag =
        mirroring == null ? '' : ', iconMatchTextDirection: $mirroring';
    return ResolvedVariant(
      paywallId: id,
      surfaceVersion: 'legacy-icon',
      bytes: Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
import restage.material;
widget Paywall = Icon(iconCodepoint: 57490$flag);
'''))),
    );
  }
}

void main() {
  installRestageRuntimeTestSupport();
  setUp(() {
    Restage.debugReset();
    InstalledWidgetLibraries.reset();
    InstalledIconTable.reset();
  });
  tearDown(() {
    Restage.debugReset();
    InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
    InstalledIconTable.reset();
  });

  for (final direction in TextDirection.values) {
    for (final mirroring in <bool?>[null, false, true]) {
      testWidgets(
          'Icon mirror=$mirroring keeps its actual $direction transform',
          (tester) async {
        await tester.runAsync(() async {
          Restage.configure(
            resolver: _LegacyIconResolver(mirroring),
            analyticsEnabled: false,
            measurementEnabled: false,
          );
        });
        await tester.pumpWidget(MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: RestagePaywall(
              id: 'legacy-icon',
              errorBuilder: (_, error) => Text('ERROR: ${error.message}'),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('ERROR:'), findsNothing);
        // This const is the exact value main's old factory produced for a
        // bare code point. A true flag deliberately selects Flutter's twin.
        final expected = mirroring == true
            ? Icons.arrow_back
            : const IconData(57490, fontFamily: 'MaterialIcons');
        final icon = find.byIcon(expected);
        expect(icon, findsOneWidget);
        expect(tester.widget<Icon>(icon).icon, same(expected));
        final transforms = tester.widgetList<Transform>(find.descendant(
          of: icon,
          matching: find.byType(Transform),
        ));
        final shouldMirror =
            mirroring == true && direction == TextDirection.rtl;
        expect(transforms, hasLength(shouldMirror ? 1 : 0));
        if (shouldMirror) {
          expect(transforms.single.transform.entry(0, 0), -1);
          expect(transforms.single.transform.entry(1, 1), 1);
        }
      });
    }
  }
}
