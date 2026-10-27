import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage_core/restage_core.dart';
import 'package:restage_svg/restage_svg.dart';
import 'package:restage_svg/src/native_values.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const _markup =
    '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><path fill="#ff0000" d="M0 0h10v10H0z"/></svg>';
const _surface = LibraryName(['test', 'surface']);

class _Bundle extends CachingAssetBundle {
  final requests = <String>[];
  @override
  Future<ByteData> load(String key) async {
    requests.add(key);
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(_markup)));
  }
}

class _Client extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(Stream.value(utf8.encode(_markup)), 200);
  }

  @override
  void close() {
    closed = true;
  }
}

class _Mapper extends ColorMapper {
  final colors = <Color>[];
  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    colors.add(color);
    return const Color(0xff00ff00);
  }
}

class _WaitingLoader extends BytesLoader {
  final completed = Completer<ByteData>();
  @override
  Future<ByteData> loadBytes(BuildContext? context) => completed.future;
}

void main() {
  testWidgets(
    'native SVG decoders reject malformed supplied values and allow null',
    (tester) async {
      final fixtures =
          jsonDecode(
                File('test/fixtures/native_bindings.json').readAsStringSync(),
              )
              as Map;
      final types = <String, String>{
        for (final fixture in fixtures.values)
          for (final binding in (fixture['bindings'] as Map).values)
            binding['source'] as String: binding['type'] as String,
      };
      final readers =
          <String, Object? Function(BuildContext, DataSource, List<Object>)>{
            'bundle': SvgNativeValues.assetBundle,
            'client': SvgNativeValues.httpClient,
            'mapper': SvgNativeValues.colorMapper,
            'file': SvgNativeValues.file,
            'errorBuilder': SvgNativeValues.errorBuilder,
            'imageBuilder': SvgNativeValues.imageBuilder,
            'loader': SvgNativeValues.loader,
          };
      const probe = LibraryName(['test', 'probe']);
      for (final reader in readers.entries) {
        Future<Object?> decode(
          String argument, {
          Object? dataValue,
          Map<String, NativeBinding<Object?>> bindings = const {},
        }) async {
          Object? result;
          final runtime = Runtime()
            ..update(
              probe,
              LocalWidgetLibrary({
                'Probe': (context, source) {
                  try {
                    result = reader.value(
                      context,
                      RestageValueBinding.dataSource(source, context),
                      const ['value'],
                    );
                  } on FormatException catch (error) {
                    result = error;
                  }
                  return const SizedBox();
                },
              }),
            )
            ..update(
              _surface,
              parseLibraryFile(
                'import test.probe; widget Root = Probe($argument);',
              ),
            );
          await tester.pumpWidget(
            RestageNativeValues(
              bindings: bindings,
              child: RemoteWidget(
                runtime: runtime,
                data: DynamicContent({
                  'context': {if (dataValue != null) 'value': dataValue},
                }),
                widget: const FullyQualifiedWidgetName(_surface, 'Root'),
                onEvent: (_, _) {},
              ),
            ),
          );
          return result;
        }

        expect(await decode(''), isNull, reason: reader.key);
        expect(await decode('value: null'), isNull, reason: reader.key);
        expect(
          await decode('value: data.context.value'),
          isNull,
          reason: reader.key,
        );
        final contract = NativeBindingContract(
          type: types[reader.key]!,
          nullable: true,
        );
        expect(
          await decode(
            'value: data.context.value',
            dataValue: contract.reference('nullable'),
            bindings: {
              'nullable': NativeBinding(contract: contract, value: null),
            },
          ),
          isNull,
          reason: reader.key,
        );
        for (final malformed in <Object>[
          [],
          [1],
          0,
          1.5,
          false,
          'invalid',
        ]) {
          expect(
            await decode('value: ${jsonEncode(malformed)}'),
            isA<FormatException>(),
            reason: '${reader.key}: $malformed',
          );
          expect(
            await decode('value: data.context.value', dataValue: malformed),
            isA<FormatException>(),
            reason: '${reader.key} referenced: $malformed',
          );
        }
      }
    },
  );

  test('native file loader preserves the platform missing-file error', () async {
    final file = File(
      '${Directory.systemTemp.path}/svg-missing-${DateTime.now().microsecondsSinceEpoch}.svg',
    );
    await expectLater(
      Future.sync(() => SvgFileLoader(file).loadBytes(null)),
      throwsA(isA<FileSystemException>()),
    );
  });

  testWidgets(
    'compiled bindings reach every native SVG constructor and loader',
    (tester) async {
      final fixtures =
          jsonDecode(
                File('test/fixtures/native_bindings.json').readAsStringSync(),
              )
              as Map;
      final directory = Directory.systemTemp.createTempSync(
        'svg-native-bindings-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/picture.svg')
        ..writeAsStringSync(_markup);
      final explicit = _Bundle();
      final descendant = _Bundle();
      final client = _Client();
      final mapper = _Mapper();
      const loader = SvgStringLoader(_markup);
      final errorCalls = <Object>[];
      final imageCalls = <Object>[];
      Widget errorBuilder(
        BuildContext context,
        Object error,
        StackTrace stack,
      ) {
        errorCalls.addAll([context, error, stack]);
        return const SizedBox();
      }

      Widget imageBuilder(BuildContext context, Widget child) {
        imageCalls.addAll([context, child]);
        return child;
      }

      final objects = <String, Object>{
        'bundle': explicit,
        "const {'X-Svg': 'bound'}": const <String, String>{'X-Svg': 'bound'},
        'client': client,
        'mapper': mapper,
        'file': file,
        'loader': loader,
        'errorBuilder': errorBuilder,
        'imageBuilder': imageBuilder,
      };
      for (final entry in fixtures.entries) {
        final fixture = entry.value as Map;
        final values = fixture['bindings'] as Map;
        final bindings = <String, NativeBinding<Object?>>{};
        final contextData = <String, Object?>{};
        for (final b in values.entries) {
          final contract = NativeBindingContract(
            type: b.value['type'] as String,
            nullable: b.value['nullable'] as bool,
          );
          bindings[b.key as String] = NativeBinding(
            contract: contract,
            value: objects[b.value['source']],
          );
          contextData[b.key as String] = contract.reference(b.key as String);
        }
        final runtime = Runtime()
          ..update(
            const LibraryName(['restage', 'svg']),
            buildCuratedWidgetLibrary(),
          )
          ..update(
            _surface,
            parseLibraryFile(
              'import restage.svg; widget Root = ${fixture['dsl']};',
            ),
          );
        await tester.pumpWidget(
          RestageNativeValues(
            bindings: bindings,
            child: DefaultAssetBundle(
              bundle: descendant,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: RemoteWidget(
                  runtime: runtime,
                  data: DynamicContent({'context': contextData}),
                  widget: const FullyQualifiedWidgetName(_surface, 'Root'),
                  onEvent: (_, _) {},
                ),
              ),
            ),
          ),
        );
        final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
        if (entry.key != 'defaultAsset') {
          expect(
            identical(picture.errorBuilder, errorBuilder),
            isTrue,
            reason: entry.key,
          );
          expect(
            identical(picture.imageBuilder, imageBuilder),
            isTrue,
            reason: entry.key,
          );
        }
        final bytes = picture.bytesLoader;
        if (entry.key == 'boundLoader') {
          expect(identical(bytes, loader), isTrue);
        } else if (entry.key != 'defaultAsset') {
          expect(
            identical((bytes as SvgLoader).colorMapper, mapper),
            isTrue,
            reason: entry.key,
          );
        }
        if (bytes is SvgAssetLoader)
          expect(
            identical(
              bytes.assetBundle,
              entry.key == 'defaultAsset' ? null : explicit,
            ),
            isTrue,
          );
        if (bytes is SvgFileLoader) expect(identical(bytes.file, file), isTrue);
        if (bytes is SvgNetworkLoader) {
          expect(bytes.headers, {'X-Svg': 'bound'});
        }
        final info = await tester.runAsync(
          () => vg.loadPicture(bytes, tester.element(find.byType(SvgPicture))),
        );
        expect(info!.size, const Size(10, 10));
        if (entry.key == 'string') {
          expect(
            bytes.cacheKey(tester.element(find.byType(SvgPicture))),
            isNot(
              SvgStringLoader(
                _markup,
                colorMapper: _Mapper(),
              ).cacheKey(tester.element(find.byType(SvgPicture))),
            ),
          );
          await tester.runAsync(() async {
            final image = await info.picture.toImage(10, 10);
            final pixels = (await image.toByteData())!;
            expect(pixels.buffer.asUint8List().sublist(220, 224), [
              0,
              255,
              0,
              255,
            ]);
            image.dispose();
          });
        }
        info.picture.dispose();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: entry.key);
      }
      expect(explicit.requests, contains('tiny.svg'));
      expect(descendant.requests, contains('tiny.svg'));
      expect(client.requests, isNotEmpty);
      expect(
        client.requests.every((r) => r.headers['X-Svg'] == 'bound'),
        isTrue,
      );
      expect(client.closed, isFalse);
      expect(mapper.colors, isNotEmpty);
      expect(errorCalls, isEmpty);
      expect(imageCalls, isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      expect(client.closed, isFalse);
    },
  );

  testWidgets(
    'native callbacks retain error stack context child and replacement',
    (tester) async {
      final unhandled = <Object>[];
      await runZonedGuarded(
        () async {
          final fixture =
              (jsonDecode(
                        File(
                          'test/fixtures/native_bindings.json',
                        ).readAsStringSync(),
                      )
                      as Map)['boundLoader']
                  as Map;
          final metadata = fixture['bindings'] as Map;
          final runtime = Runtime()
            ..update(
              const LibraryName(['restage', 'svg']),
              buildCuratedWidgetLibrary(),
            )
            ..update(
              _surface,
              parseLibraryFile(
                'import restage.svg; widget Root = ${fixture['dsl']};',
              ),
            );
          final failure = StateError('native loader failure');
          final stack = StackTrace.current;
          final first = <Object>[];
          final second = <Object>[];
          final images = <Object>[];
          Widget onError(
            List<Object> calls,
            BuildContext context,
            Object error,
            StackTrace trace,
          ) {
            calls.addAll([context, error, trace]);
            return const SizedBox(key: ValueKey('error'));
          }

          Future<void> mount(BytesLoader loader, List<Object> errors) async {
            final objects = <String, Object>{
              'loader': loader,
              'errorBuilder': (BuildContext c, Object e, StackTrace s) =>
                  onError(errors, c, e, s),
              'imageBuilder': (BuildContext c, Widget child) {
                images.addAll([c, child]);
                return child;
              },
            };
            final bindings = <String, NativeBinding<Object?>>{};
            final contextData = <String, Object?>{};
            for (final b in metadata.entries) {
              final contract = NativeBindingContract(
                type: b.value['type'] as String,
                nullable: b.value['nullable'] as bool,
              );
              bindings[b.key as String] = NativeBinding(
                contract: contract,
                value: objects[b.value['source']],
              );
              contextData[b.key as String] = contract.reference(
                b.key as String,
              );
            }
            await tester.pumpWidget(
              RestageNativeValues(
                bindings: bindings,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: RemoteWidget(
                    runtime: runtime,
                    data: DynamicContent({'context': contextData}),
                    widget: const FullyQualifiedWidgetName(_surface, 'Root'),
                    onEvent: (_, _) {},
                  ),
                ),
              ),
            );
          }

          final waiting = _WaitingLoader();
          await mount(waiting, first);
          expect(images, isEmpty);
          await mount(waiting, second);
          waiting.completed.completeError(failure, stack);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pumpAndSettle();
          expect(first, isEmpty);
          expect(second.length, 3);
          expect(identical(second[1], failure), isTrue);
          expect(identical(second[2], stack), isTrue);
          expect(
            (second[0] as BuildContext).widget.runtimeType.toString(),
            contains('VectorGraphic'),
          );
          expect(images, isEmpty);
          expect(find.byKey(const ValueKey('error')), findsOneWidget);
          await mount(const SvgStringLoader(_markup), second);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pumpAndSettle();
          expect(images.length, greaterThanOrEqualTo(2));
          final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
          final child = const SizedBox();
          final context = tester.element(find.byType(SvgPicture));
          expect(
            identical(picture.imageBuilder!(context, child), child),
            isTrue,
          );
          expect(identical(images.last, child), isTrue);
          expect(identical(images[images.length - 2], context), isTrue);
          expect(tester.takeException(), isNull);
        },
        (error, stack) {
          unhandled.add(error);
        },
      );
      // errorBuilder handles the failure, so nothing reaches the zone.
      expect(unhandled, isEmpty);
    },
  );
}
