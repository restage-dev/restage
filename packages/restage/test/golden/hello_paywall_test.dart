import 'dart:io' show Platform;
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

void main() {
  testWidgets('hello paywall golden — iPhone 16 Pro Max frame', (tester) async {
    Restage.debugReset();

    // iPhone 16 Pro Max: 440 × 956 logical (× 3 = 1320 × 2868 physical).
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const source = '''
      import restage.core;
      import restage.material;

      widget Paywall = Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: "center",
            children: [
              Text(
                text: "Restage Pro",
                fontSize: 32.0,
                fontWeight: "w700",
                textAlign: "center",
              ),
              SizedBox(height: 16.0),
              Text(
                text: "Render paywalls as real Flutter widgets, not webviews.",
                fontSize: 16.0,
                textAlign: "center",
              ),
              SizedBox(height: 40.0),
              ElevatedButton(
                onPressed: event "restage.purchase" { slot: "primary" },
                child: Text(text: "Continue"),
              ),
              SizedBox(height: 12.0),
              TextButton(
                onPressed: event "restage.restore" { },
                child: Text(text: "Restore purchases"),
              ),
            ],
          ),
        ),
      );
    ''';
    final bytes =
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: Scaffold(
        body: RestagePaywall(id: 'hello', resolver: _StaticResolver(bytes)),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(RestagePaywall),
      matchesGoldenFile('goldens/hello_paywall_iphone_16_pro_max.png'),
    );
    // Goldens are recorded on macOS. Linux's font renderer produces
    // sub-percent pixel differences that aren't actionable — skip the
    // pixel comparison on non-mac so CI stays meaningful.
  }, skip: !Platform.isMacOS);
}
