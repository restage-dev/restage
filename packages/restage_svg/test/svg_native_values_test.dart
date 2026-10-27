import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage_core/restage_core.dart';
import 'package:restage_svg/restage_svg.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

import 'fixtures/native_value_source.dart' as fixture;

const _surface = LibraryName(['test', 'surface']);

class _Bundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(fixture.markup.codeUnits));
}

class _Client extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(Stream.value(fixture.markup.codeUnits), 200);
  }

  @override
  void close() {
    closed = true;
  }
}

class _WaitingLoader extends BytesLoader {
  final ready = Completer<ByteData>();
  @override
  Future<ByteData> loadBytes(BuildContext? context) => ready.future;
}

class _Marker extends InheritedWidget {
  const _Marker({required super.child});
  @override
  bool updateShouldNotify(_Marker oldWidget) => false;
}

Future<T> _captureNativeErrors<T>(
  Future<T> Function() action,
  List<Object> errors,
) {
  final done = Completer<T>();
  runZonedGuarded(
    () {
      action().then(done.complete, onError: done.completeError);
    },
    (error, _) {
      errors.add(error);
    },
  );
  return done.future;
}

String _dsl(String name) => switch (name) {
  'fresh' => fixture.freshDsl,
  'constants' => fixture.constantsDsl,
  'failing' => fixture.failingDsl,
  'staged' => fixture.stagedDsl,
  'stagedHeaders' => fixture.stagedHeadersDsl,
  'stagedHeaderLiteral' => fixture.stagedHeaderLiteralDsl,
  'stagedFile' => fixture.stagedFileDsl,
  'stagedCallbacks' => fixture.stagedCallbacksDsl,
  'stagedValues' => fixture.stagedValuesDsl,
  _ => throw StateError(name),
};

Map<String, NativeBinding<Object?>> _bindings(
  String name,
  fixture.ValueSource source,
) => switch (name) {
  'fresh' => fixture.freshBindings(source),
  'constants' => fixture.constantsBindings(source),
  'failing' => fixture.failingBindings(source),
  'staged' => fixture.stagedBindings(source),
  'stagedHeaders' => fixture.stagedHeadersBindings(source),
  'stagedHeaderLiteral' => fixture.stagedHeaderLiteralBindings(source),
  'stagedFile' => fixture.stagedFileBindings(source),
  'stagedCallbacks' => fixture.stagedCallbacksBindings(source),
  'stagedValues' => fixture.stagedValuesBindings(source),
  _ => throw StateError(name),
};

Widget _native(String name, fixture.ValueSource source, BuildContext context) =>
    switch (name) {
      'fresh' => source.fresh(context),
      'constants' => source.constants(context),
      'failing' => source.failing(context),
      'staged' => source.staged(context),
      'stagedHeaders' => source.stagedHeaders(context),
      'stagedHeaderLiteral' => source.stagedHeaderLiteral(context),
      'stagedFile' => source.stagedFile(context),
      'stagedCallbacks' => source.stagedCallbacks(context),
      'stagedValues' => source.stagedValues(context),
      _ => throw StateError(name),
    };

Widget _screen(
  String name,
  fixture.ValueSource source, {
  required bool generated,
}) {
  Widget body;
  if (generated) {
    final bindings = _bindings(name, source);
    final runtime = Runtime()
      ..update(const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
      ..update(
        const LibraryName(['restage', 'svg']),
        buildCuratedWidgetLibrary(),
      )
      ..update(
        _surface,
        parseLibraryFile(
          'import restage.core; import restage.svg; widget Root = ${_dsl(name)};',
        ),
      );
    body = RestageNativeValues(
      bindings: bindings,
      child: RemoteWidget(
        runtime: runtime,
        data: DynamicContent({
          'context': {
            for (final entry in bindings.entries)
              entry.key: entry.value.contract.reference(entry.key),
          },
        }),
        widget: const FullyQualifiedWidgetName(_surface, 'Root'),
        onEvent: (_, _) {},
      ),
    );
  } else {
    body = Builder(builder: (context) => _native(name, source, context));
  }
  return _Marker(
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(width: 20, height: 20, child: body),
    ),
  );
}

void main() {
  for (final name in [
    'fresh',
    'constants',
    'staged',
    'stagedHeaders',
    'stagedHeaderLiteral',
    'stagedFile',
    'stagedCallbacks',
    'stagedValues',
  ]) {
    testWidgets(
      'generated native SVG values match authored timing and actual identities $name',
      (tester) async {
        final temp = Directory.systemTemp.createTempSync('svg-values-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final file = File('${temp.path}/picture.svg')
          ..writeAsStringSync(fixture.markup);

        List<String>? nativeEvents;
        for (final generated in [false, true]) {
          final recorder = fixture.Recorder();
          final client = _Client();
          final source = fixture.ValueSource(
            recorder: recorder,
            bundle: _Bundle(),
            client: client,
            loader: const SvgStringLoader(fixture.markup),
            file: file,
          );
          final screen = _screen(name, source, generated: generated);
          expect(recorder.events, isEmpty, reason: '$name before mount');
          await tester.pumpWidget(screen);
          final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
          if (name == 'staged') {
            expect(recorder.loaders, hasLength(1));
            expect(recorder.themes, hasLength(1));
            expect(picture.bytesLoader, same(recorder.loaders.single));
          }
          if (name == 'stagedFile')
            expect((picture.bytesLoader as SvgFileLoader).file, same(file));
          if (name == 'stagedHeaders') {
            expect(recorder.headers, hasLength(1));
            expect(
              (picture.bytesLoader as SvgNetworkLoader).headers,
              same(recorder.headers.single),
            );
          }
          if (name == 'stagedValues') {
            final bytes = picture.bytesLoader as SvgBytesLoader;
            expect(bytes.colorMapper, same(recorder.mappers.single));
            expect(bytes.theme, same(recorder.themes.single));
            expect(recorder.events.where((e) => e == 'bytes'), hasLength(1));
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
          expect(recorder.errors, isEmpty);
          if (name == 'constants') {
            expect(picture.imageBuilder, same(fixture.constantImage));
            expect(picture.errorBuilder, same(fixture.constantError));
            expect(picture.colorFilter, same(fixture.constantFilter));
            expect(
              (picture.bytesLoader as SvgStringLoader).theme,
              same(fixture.constantTheme),
            );
          } else {
            expect(recorder.children, isNotEmpty);
          }
          for (final context in recorder.contexts) {
            expect(
              context.widget.runtimeType.toString(),
              contains('VectorGraphic'),
            );
            expect(context.getInheritedWidgetOfExactType<_Marker>(), isNotNull);
          }
          if (name == 'stagedHeaderLiteral')
            expect(
              (picture.bytesLoader as SvgNetworkLoader).headers,
              same(recorder.headers.last),
            );
          if (name == 'stagedValues')
            expect(
              (picture.bytesLoader as SvgBytesLoader).bytes,
              same(recorder.byteBuffers.last),
            );
          if (name == 'stagedHeaders' || name == 'stagedHeaderLiteral') {
            expect(client.requests, isNotEmpty);
            expect(
              client.requests.last.headers['X-Svg'],
              name == 'stagedHeaders' ? 'staged' : 'literal',
            );
          }
          if (!generated) {
            nativeEvents = List.of(recorder.events);
          } else {
            expect(recorder.events, nativeEvents, reason: name);
          }
          final child = const SizedBox();
          final context = tester.element(find.byType(SvgPicture));
          final count = recorder.events
              .where((e) => e.startsWith('count:'))
              .length;
          expect(picture.imageBuilder!(context, child), same(child));
          if (name == 'stagedCallbacks') {
            expect(
              recorder.events.where((e) => e.startsWith('count:')).last,
              'count:$count',
            );
          }
          if (name != 'constants') {
            expect(recorder.children.last, same(child));
            expect(recorder.contexts.last, same(context));
          }
          await tester.pumpWidget(const SizedBox());
          expect(client.closed, isFalse);
          expect(
            tester.takeException(),
            isNull,
            reason: '$name generated=$generated',
          );
        }
      },
    );
  }

  testWidgets(
    'fresh installed SVG callbacks replace while native errors are pending',
    (tester) async {
      final errors = <Object>[];
      await _captureNativeErrors(() async {
        for (final generated in [false, true]) {
          final waiting = _WaitingLoader();
          final first = fixture.Recorder();
          final second = fixture.Recorder();
          final client = _Client();
          fixture.ValueSource source(fixture.Recorder recorder) =>
              fixture.ValueSource(
                recorder: recorder,
                bundle: _Bundle(),
                client: client,
                loader: waiting,
                file: File('unused.svg'),
              );
          await tester.pumpWidget(
            _screen('failing', source(first), generated: generated),
          );
          expect(first.events, isEmpty);
          await tester.pumpWidget(
            _screen('failing', source(second), generated: generated),
          );
          final failure = StateError('original native error');
          final stack = StackTrace.current;
          waiting.ready.completeError(failure, stack);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pumpAndSettle();
          expect(first.events, isEmpty);
          expect(second.events, ['error']);
          expect(second.errors.single, same(failure));
          expect(second.stacks.single, same(stack));
          expect(second.children, isEmpty);
          expect(
            second.contexts.single.widget.runtimeType.toString(),
            contains('VectorGraphic'),
          );
          expect(find.byKey(const ValueKey('native-error')), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        }
      }, errors);
      // errorBuilder handles the failure, so nothing reaches the zone.
      expect(errors, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
