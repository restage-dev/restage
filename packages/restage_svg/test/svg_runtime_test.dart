import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' show buildCoreWidgetLibrary;
import 'package:restage_svg/restage_svg.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart' as schema;

const svg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10"><path fill="currentColor" d="M0 0h4v10H0z"/></svg>';
const surface = LibraryName(['test', 'surface']);
const svgLibrary = LibraryName(['restage', 'svg']);

class FixtureBundle extends CachingAssetBundle {
  final keys = <String>[];
  @override
  Future<ByteData> load(String key) async {
    keys.add(key);
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(svg)));
  }
}

void main() {
  test('the optional namespace declares capability two', () {
    final library =
        kRegistry.libraries[const schema.WidgetLibrary.custom('restage.svg')]!;
    expect(library.capabilityVersion, 2);
    expect(library.compatibleSince, 1);
    expect(buildCuratedWidgetLibrary().widgets, hasLength(6));
  });

  testWidgets('native string memory asset and loader preserve rendering data', (
    tester,
  ) async {
    final bundle = FixtureBundle();
    final semantics = tester.ensureSemantics();
    try {
      final constructors = [
        File('test/fixtures/string_picture.rfwtxt').readAsStringSync().trim(),
        'SvgPictureMemory(bytes: ${utf8.encode(svg)}, width: 24.0)',
        'SvgPictureAsset(assetName: "tiny.svg", package: "icons", width: 24.0)',
        'SvgPicture(bytesLoader: {kind: "SvgStringLoader", value: ${jsonEncode(svg)}, theme: {fontSize: 18.0}}, width: 24.0)',
        File('test/fixtures/aliased_picture.rfwtxt').readAsStringSync().trim(),
      ];
      final types = [
        SvgStringLoader,
        SvgBytesLoader,
        SvgAssetLoader,
        SvgStringLoader,
        SvgStringLoader,
      ];
      for (var i = 0; i < constructors.length; i++) {
        final runtime = Runtime()
          ..update(svgLibrary, buildCuratedWidgetLibrary())
          ..update(
            surface,
            parseLibraryFile(
              'import restage.svg; widget Screen = ${constructors[i]};',
            ),
          );
        await tester.pumpWidget(
          DefaultAssetBundle(
            bundle: bundle,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: RemoteWidget(
                runtime: runtime,
                data: DynamicContent(),
                widget: const FullyQualifiedWidgetName(surface, 'Screen'),
                onEvent: (_, _) {},
              ),
            ),
          ),
        );
        final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
        expect(picture.bytesLoader.runtimeType, types[i]);
        expect(picture.placeholderBuilder, isNull);
        expect(picture.errorBuilder, isNull);
        expect(picture.imageBuilder, isNull);
        expect(picture.clipBehavior, Clip.hardEdge);
        expect(picture.renderingStrategy.name, 'picture');
        if (i == 1) {
          expect(
            (picture.bytesLoader as SvgBytesLoader).bytes,
            isA<Uint8List>(),
          );
          expect(
            (picture.bytesLoader as SvgBytesLoader).bytes,
            utf8.encode(svg),
          );
        }
        expect(picture.alignment, Alignment.center);
        if (i == 0 || i == 4) {
          expect(picture.matchTextDirection, isTrue);
          expect(picture.semanticsLabel, 'Mark');
          expect(
            picture.colorFilter,
            const ColorFilter.mode(Color(0xffaa0000), BlendMode.srcIn),
          );
          expect((picture.bytesLoader as SvgStringLoader).theme!.xHeight, 10);
        }
        final info = await tester.runAsync(
          () => vg.loadPicture(
            picture.bytesLoader,
            tester.element(find.byType(SvgPicture)),
          ),
        );
        expect(info!.size, const Size(10, 10));
        info.picture.dispose();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (i == 0 || i == 4) {
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Transform && widget.transform.entry(0, 0) == -1.0,
            ),
            findsOneWidget,
          );
          expect(find.bySemanticsLabel('Mark'), findsOneWidget);
        }
      }
      expect(bundle.keys, contains('packages/icons/tiny.svg'));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'nullable native placeholder callback uses the installed builder contract',
    (tester) async {
      final waiting = Completer<ByteData>();
      final source = File(
        'test/fixtures/placeholder_picture.rfwtxt',
      ).readAsStringSync().trim();
      final runtime = Runtime()
        ..update(
          const LibraryName(['restage', 'core']),
          buildCoreWidgetLibrary(),
        )
        ..update(svgLibrary, buildCuratedWidgetLibrary())
        ..update(
          surface,
          parseLibraryFile(
            'import restage.svg; import restage.core; widget Screen = $source;',
          ),
        );
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: WaitingBundle(waiting.future),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: RemoteWidget(
              runtime: runtime,
              data: DynamicContent(),
              widget: const FullyQualifiedWidgetName(surface, 'Screen'),
            ),
          ),
        ),
      );
      expect(
        tester.widget<SvgPicture>(find.byType(SvgPicture)).placeholderBuilder,
        isNotNull,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.width == 7,
        ),
        findsOneWidget,
      );
      waiting.complete(
        ByteData.sublistView(Uint8List.fromList(utf8.encode(svg))),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('native network loader fetches local bytes with headers', (
    tester,
  ) async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previous);
    final server = await tester.runAsync(
      () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    addTearDown(() => server!.close(force: true));
    String? header;
    await tester.runAsync(() async {
      server!.listen((request) async {
        header = request.headers.value('X-Svg');
        request.response
          ..headers.contentType = ContentType('image', 'svg+xml')
          ..write(svg);
        await request.response.close();
      });
    });
    final url = 'http://127.0.0.1:${server!.port}/tiny.svg';
    final runtime = Runtime()
      ..update(svgLibrary, buildCuratedWidgetLibrary())
      ..update(
        surface,
        parseLibraryFile(
          'import restage.svg; widget Screen = SvgPictureNetwork(url: "$url", headers: [{key: "X-Svg", value: "fixture"}], width: 24.0);',
        ),
      );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RemoteWidget(
          runtime: runtime,
          data: DynamicContent(),
          widget: const FullyQualifiedWidgetName(surface, 'Screen'),
          onEvent: (_, _) {},
        ),
      ),
    );
    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    final loader = picture.bytesLoader as SvgNetworkLoader;
    expect(loader.url, url);
    expect(loader.headers, {'X-Svg': 'fixture'});
    final response = await tester.runAsync(() => loader.prepareMessage(null));
    expect(utf8.decode(response!), svg);
    final info = await tester.runAsync(
      () => vg.loadPicture(SvgBytesLoader(response), null),
    );
    expect(info!.size, const Size(10, 10));
    info.picture.dispose();
    expect(header, 'fixture');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class WaitingBundle extends CachingAssetBundle {
  WaitingBundle(this.result);
  final Future<ByteData> result;
  @override
  Future<ByteData> load(String key) => result;
}
