// The data.device.* channel on the blob paywall, re-published when the ambient
// MediaQuery changes. Values are read while mounted and asserted after
// unmounting, because RestagePaywall installs a runtime error boundary.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

class _StaticResolver implements VariantResolver {
  _StaticResolver(this.bytes);
  final Uint8List bytes;
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(bytes: bytes, surfaceVersion: 'test', paywallId: id);
}

const _kFixturesLibrary = WidgetLibrary.custom('acme.fixtures');

/// Holds what the `data.device.*` channel published.
class _DeviceProbe extends StatelessWidget {
  const _DeviceProbe({this.width});
  final double? width;
  @override
  Widget build(BuildContext context) => const SizedBox(width: 50, height: 50);
}

void _registerProbe() {
  Restage.registerWidgetLibrary(
    _kFixturesLibrary,
    widgets: <RestageWidgetFactory>[
      RestageWidgetFactory(
        name: 'DeviceProbe',
        builder: (context, source) => _DeviceProbe(
          width: source.v<double>(<Object>['width']),
        ),
      ),
    ],
  );
}

void main() {
  setUp(() {
    Restage.debugReset();
    _registerProbe();
  });

  testWidgets('the device channel resolves and re-publishes on a resize',
      (tester) async {
    final resolver = _StaticResolver(
      Uint8List.fromList(
        encodeLibraryBlob(
          parseLibraryFile('''
            import restage.core;
            import acme.fixtures;
            widget Paywall = DeviceProbe(width: data.device.screenWidth);
          '''),
        ),
      ),
    );

    Widget app(Size size) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: Scaffold(
              body: RestagePaywall(id: 'p', resolver: resolver),
            ),
          ),
        );

    _DeviceProbe probe() =>
        tester.widget<_DeviceProbe>(find.byType(_DeviceProbe));

    await tester.pumpWidget(app(const Size(390, 844)));
    await tester.pumpAndSettle();
    final firstWidth = probe().width;

    // Rotate: same RestagePaywall element, new ambient MediaQuery.
    await tester.pumpWidget(app(const Size(844, 390)));
    await tester.pumpAndSettle();
    final rotatedWidth = probe().width;

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(firstWidth, 390.0);
    expect(rotatedWidth, 844.0,
        reason: 'a resize re-publishes data.device.screenWidth');
  });
}
