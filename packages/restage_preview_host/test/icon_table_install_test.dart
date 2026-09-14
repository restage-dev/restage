import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_preview_host/restage_preview_host.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

/// The one code point the narrow table below carries. The whole built-in table
/// also carries it, under a different icon, so a last-wins add is visible.
const int _sharedCodePoint = 0xe156;

/// A code point no narrow per-app table carries. The whole built-in table
/// gives it [Icons.pets].
const int _petsCodePoint = 0xe4a1;

/// A table of the shape an app installs — the icons that app's own surfaces
/// render, and nothing else.
const RestageIconTable _narrowTable = RestageIconTable.fromFamilies(
  families: <String, Map<int, IconData>>{
    RestageIconTable.materialIconsFamily: <int, IconData>{
      _sharedCodePoint: Icons.star,
    },
  },
);

RenderEnv _environment() => RenderEnv(
      theme: const <String, Object?>{},
      brightness: 'light',
      locale: 'en-US',
      textScale: 1,
      zoom: 1,
      frame: const Size(390, 844),
    );

Future<void> _pumpPreview(WidgetTester tester, int codePoint) async {
  final blob = encodeLibraryBlob(
    parseLibraryFile(
      'import restage.material;\n'
      'widget Preview = Icon(iconCodepoint: $codePoint);\n',
    ),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: RawRfwRenderSurface(
        epoch: 1,
        blob: blob,
        data: const <String, Object?>{},
        environment: _environment(),
        registrations: const <RestageWidgetLibraryRegistration>[],
        entryWidgetName: 'Preview',
        onRemoteEvent: (_, __) {},
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(InstalledIconTable.reset);
  tearDown(InstalledIconTable.reset);

  test('a narrow app table does not carry the icon under test', () {
    InstalledIconTable.install(_narrowTable);

    expect(
      () => resolveInstalledIcon(
        _petsCodePoint,
        fontFamily: RestageIconTable.materialIconsFamily,
      ),
      throwsA(isA<RestageIconUnavailableError>()),
    );
  });

  testWidgets('a preview renders through the app table it was given',
      (tester) async {
    InstalledIconTable.install(_narrowTable);

    await _pumpPreview(tester, _sharedCodePoint);

    expect(tester.widget<Icon>(find.byType(Icon)).icon, equals(Icons.star));
  });

  testWidgets('rendering leaves the app table entries meaning what they did',
      (tester) async {
    InstalledIconTable.install(_narrowTable);

    await _pumpPreview(tester, _sharedCodePoint);

    // The whole built-in table gives this code point Icons.check, so a
    // last-wins add would change what the app's own surfaces render here.
    expect(
      resolveInstalledIcon(
        _sharedCodePoint,
        fontFamily: RestageIconTable.materialIconsFamily,
      ),
      equals(Icons.star),
    );
  });

  testWidgets('a preview renders an icon the app table omits', (tester) async {
    InstalledIconTable.install(_narrowTable);

    await _pumpPreview(tester, _petsCodePoint);

    expect(tester.widget<Icon>(find.byType(Icon)).icon, equals(Icons.pets));
  });
}
