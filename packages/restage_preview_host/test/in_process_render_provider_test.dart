import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart'
    show RestageWidgetLibraryRegistration, kReservedPreviewConstructorName;
import 'package:restage_preview_host/restage_preview_host.dart';
import 'package:rfw/formats.dart';

const _markerPath = '["Preview","child"]';

void main() {
  testWidgets(
    'render drives the public surface with exact blob, data, env, lifecycle, '
    'and geometry zero',
    (tester) async {
      final provider = InProcessRenderProvider();
      addTearDown(provider.dispose);
      final timeline = <Object>[];
      final events = provider.events.listen(timeline.add);
      final geometry = provider.geometry.listen(timeline.add);
      addTearDown(events.cancel);
      addTearDown(geometry.cancel);

      await tester.pumpWidget(_host(provider));
      final request = _request(
        1,
        label: 'Provider-owned pixels',
        data: const <String, Object?>{
          'offer': <String, Object?>{'active': true},
        },
        env: _env(
          theme: const <String, Object?>{
            'brand': <String, Object?>{'accent': '#ff8844'},
          },
          brightness: 'dark',
          locale: 'sv-SE',
          textScale: 1.25,
        ),
      );

      await provider.render(request);
      await tester.pump();
      await tester.pump();

      expect(find.text('Provider-owned pixels'), findsOneWidget);
      final raw = tester.widget<RawRfwRenderSurface>(
        find.byType(RawRfwRenderSurface),
      );
      expect(raw.epoch, request.epoch);
      expect(raw.blob, orderedEquals(request.blob));
      expect(raw.data, request.data);
      expect(raw.environment, same(request.env));
      expect(
        Theme.of(tester.element(find.text('Provider-owned pixels'))).brightness,
        Brightness.dark,
      );
      expect(
        Localizations.localeOf(
          tester.element(find.text('Provider-owned pixels')),
        ).toLanguageTag(),
        'sv-SE',
      );

      expect(timeline, hasLength(2));
      expect(timeline.first, isA<Settled>());
      final zero = timeline.last as GeometrySnapshot;
      expect(zero.epoch, 1);
      expect(zero.generation, 0);
      expect(zero.rects[_markerPath], isNotNull);
    },
  );

  testWidgets('successive renders replace every request-owned input', (
    tester,
  ) async {
    final provider = InProcessRenderProvider();
    addTearDown(provider.dispose);
    final events = <RenderEvent>[];
    final snapshots = <GeometrySnapshot>[];
    final eventSubscription = provider.events.listen(events.add);
    final geometrySubscription = provider.geometry.listen(snapshots.add);
    addTearDown(eventSubscription.cancel);
    addTearDown(geometrySubscription.cancel);
    await tester.pumpWidget(_host(provider));

    await provider.render(
      _request(
        1,
        label: 'First render',
        data: const <String, Object?>{'revision': 1},
        env: _env(),
      ),
    );
    await tester.pump();
    await tester.pump();

    final second = _request(
      2,
      label: 'Second render',
      data: const <String, Object?>{'revision': 2},
      env: _env(
        theme: const <String, Object?>{'mode': 'second'},
        brightness: 'dark',
        locale: 'fr-FR',
        textScale: 1.5,
        frame: const Size(240, 180),
      ),
    );
    await provider.render(second);
    await tester.pump();
    await tester.pump();

    expect(find.text('First render'), findsNothing);
    expect(find.text('Second render'), findsOneWidget);
    final raw = tester.widget<RawRfwRenderSurface>(
      find.byType(RawRfwRenderSurface),
    );
    expect(raw.epoch, 2);
    expect(raw.blob, orderedEquals(second.blob));
    expect(raw.data, second.data);
    expect(raw.environment, same(second.env));
    expect(
      Theme.of(tester.element(find.text('Second render'))).brightness,
      Brightness.dark,
    );
    expect(
      Localizations.localeOf(
        tester.element(find.text('Second render')),
      ).toLanguageTag(),
      'fr-FR',
    );
    expect(events.whereType<Settled>().map((event) => event.epoch), <int>[
      1,
      2,
    ]);
    expect(
      snapshots.map((snapshot) => (snapshot.epoch, snapshot.generation)),
      <(int, int)>[(1, 0), (2, 0)],
    );
  });

  test('non-monotonic epochs fail closed like the seam provider', () async {
    final provider = InProcessRenderProvider();
    addTearDown(provider.dispose);

    await provider.render(_request(2, label: 'Accepted'));

    await expectLater(
      provider.render(_request(2, label: 'Duplicate')),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          'must be strictly monotonic',
        ),
      ),
    );
    await expectLater(
      provider.render(_request(1, label: 'Stale')),
      throwsA(isA<ArgumentError>()),
    );
    await provider.render(_request(3, label: 'Next accepted epoch'));
  });

  testWidgets('a superseded pre-paint request cannot emit stale output', (
    tester,
  ) async {
    final provider = InProcessRenderProvider();
    addTearDown(provider.dispose);
    final events = <RenderEvent>[];
    final snapshots = <GeometrySnapshot>[];
    final eventSubscription = provider.events.listen(events.add);
    final geometrySubscription = provider.geometry.listen(snapshots.add);
    addTearDown(eventSubscription.cancel);
    addTearDown(geometrySubscription.cancel);
    await tester.pumpWidget(_host(provider));

    await provider.render(_request(1, label: 'Superseded'));
    await provider.render(_request(2, label: 'Current'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Superseded'), findsNothing);
    expect(find.text('Current'), findsOneWidget);
    expect(events.whereType<Settled>().map((event) => event.epoch), <int>[2]);
    expect(events.whereType<RenderError>(), isEmpty);
    expect(snapshots.map((snapshot) => snapshot.epoch), <int>[2]);
    expect(snapshots.single.generation, 0);
  });

  testWidgets('terminal decode errors emit once and a later epoch recovers', (
    tester,
  ) async {
    final provider = InProcessRenderProvider();
    addTearDown(provider.dispose);
    final events = <RenderEvent>[];
    final snapshots = <GeometrySnapshot>[];
    final eventSubscription = provider.events.listen(events.add);
    final geometrySubscription = provider.geometry.listen(snapshots.add);
    addTearDown(eventSubscription.cancel);
    addTearDown(geometrySubscription.cancel);
    await tester.pumpWidget(_host(provider));

    await provider.render(
      RenderRequest(
        epoch: 1,
        blob: Uint8List(0),
        data: const <String, Object?>{},
        env: _env(),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(events.whereType<RenderError>(), hasLength(1));
    expect(events.whereType<RenderError>().single.epoch, 1);
    expect(events.whereType<Settled>(), isEmpty);
    expect(snapshots, isEmpty);

    await provider.render(_request(2, label: 'Recovered'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Recovered'), findsOneWidget);
    expect(events.whereType<Settled>().map((event) => event.epoch), <int>[2]);
    expect(snapshots.single.epoch, 2);
    expect(snapshots.single.generation, 0);
  });
}

Widget _host(InProcessRenderProvider provider) {
  return MaterialApp(
    home: InProcessPreviewSurface(
      provider: provider,
      registrations: const <RestageWidgetLibraryRegistration>[],
      entryWidgetName: 'Preview',
      onRemoteEvent: (_, __) {},
    ),
  );
}

RenderRequest _request(
  int epoch, {
  required String label,
  Map<String, Object?> data = const <String, Object?>{},
  RenderEnv? env,
}) {
  return RenderRequest(
    epoch: epoch,
    blob: encodeLibraryBlob(_library()),
    data: <String, Object?>{...data, 'title': label},
    env: env ?? _env(),
  );
}

RemoteWidgetLibrary _library() {
  return RemoteWidgetLibrary(
    const <Import>[
      Import(LibraryName(<String>['restage', 'editor'])),
      Import(LibraryName(<String>['restage', 'core'])),
    ],
    <WidgetDeclaration>[
      WidgetDeclaration(
        'Preview',
        null,
        ConstructorCall(kReservedPreviewConstructorName, <String, Object?>{
          'path': _markerPath,
          'child': ConstructorCall('Text', <String, Object?>{
            'text': const DataReference(<Object>['title']),
          }),
        }),
      ),
    ],
  );
}

RenderEnv _env({
  Map<String, Object?> theme = const <String, Object?>{},
  String brightness = 'light',
  String locale = 'en-US',
  double textScale = 1,
  Size frame = const Size(200, 150),
}) {
  return RenderEnv(
    theme: theme,
    brightness: brightness,
    locale: locale,
    textScale: textScale,
    zoom: 1,
    frame: frame,
  );
}
