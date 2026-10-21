import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/render_bundles/surface_capture.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';

/// A one-pixel PNG.
final _png = Uint8List.fromList(const <int>[
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, //
  0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, //
  84, 120, 218, 99, 100, 248, 207, 80, 15, 0, 3, 134, 1, 128, 90, 52, 125, //
  107, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130, //
]);

/// A process the test finishes by hand.
final class _FakeProcess implements Process {
  _FakeProcess({String output = ''}) {
    _stdout.add(utf8.encode(output));
    unawaited(_stdout.close());
    unawaited(_stderr.close());
  }

  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  final _exit = Completer<int>();
  final killed = <ProcessSignal>[];

  void finish(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed.add(signal);
    finish(-15);
    return true;
  }

  @override
  int get pid => 1;

  @override
  IOSink get stdin => throw UnimplementedError();
}

void main() {
  late Directory root;
  late Directory app;
  late List<List<String>> started;
  late SurfacePublicationManifestEntry entry;

  void write(String path, String text) =>
      File(p.joinAll([root.path, ...path.split('/')]))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);

  String imagesDirectory() =>
      p.join(app.path, '.restage', 'build', 'surface_capture', 'images');

  setUp(() async {
    root = Directory.systemTemp.createTempSync('surface_capture_test_');
    app = Directory(p.join(root.path, 'app'));
    write(
      'app/.dart_tool/package_config.json',
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          <String, Object?>{
            'name': fixturePackageName,
            'rootUri': '../',
            'packageUri': 'lib/',
          },
          <String, Object?>{
            'name': 'flutter',
            'rootUri': '../../flutter/packages/flutter',
            'packageUri': 'lib/',
          },
        ],
        'flutterRoot': Uri.directory(p.join(root.path, 'flutter')).toString(),
      }),
    );
    write(
      'app/.dart_tool/package_graph.json',
      jsonEncode(<String, Object?>{
        'configVersion': 1,
        'packages': <Object?>[
          <String, Object?>{
            'name': fixturePackageName,
            'dependencies': ['flutter'],
            'devDependencies': <String>[],
          },
          <String, Object?>{
            'name': 'flutter',
            'dependencies': <String>[],
            'devDependencies': <String>[],
          },
        ],
      }),
    );
    write('flutter/bin/flutter', '#!/bin/sh\n');
    write('flutter/packages/flutter/pubspec.yaml', 'name: flutter\n');
    write(
      'flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      'ttf',
    );
    write('app/lib/paywalls/pro_upgrade.dart', '''
import 'package:flutter/material.dart';

part 'restage.generated/pro_upgrade.restage.g.dart';

@Paywall()
class ProUpgrade extends StatelessWidget {
  const ProUpgrade({super.key});
}
''');
    write('app/lib/paywalls/restage.generated/pro_upgrade.restage.g.dart', '''
part of '../pro_upgrade.dart';

final class ProUpgradeSurface extends StatelessWidget {
  const ProUpgradeSurface({super.key});

  @override
  Widget build(BuildContext context) {
    return RestagePaywall(
      id: 'pro_upgrade',
      fallbackBuilder: (context) => ProUpgrade(),
    );
  }
}
''');
    entry = await seedGeneratedPaywall(
      app,
      sources: const ['lib/paywalls/pro_upgrade.dart'],
    );
    write('app/pubspec.yaml', '''
name: $fixturePackageName
environment:
  sdk: ^3.10.0
dependencies:
  flutter:
    sdk: flutter
''');
    started = [];
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<ProcessResult> versionRunner(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async => ProcessResult(1, 0, '{"frameworkVersion": "3.99.0"}', '');

  /// Resolves, then renders by writing [image] for each test it was given.
  SurfaceCaptureProcessStarter renderer({
    Uint8List? image,
    int testExit = 0,
    String output = '',
    void Function(_FakeProcess process)? onTest,
    void Function(_FakeProcess process)? onStart,
  }) => (executable, arguments, {workingDirectory}) async {
    started.add(arguments);
    if (onStart != null) {
      // Every process hangs until it is killed.
      final process = _FakeProcess();
      onStart(process);
      return process;
    }
    if (arguments.first == 'pub') {
      File(p.join(workingDirectory!, '.dart_tool', 'package_config.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
      return _FakeProcess()..finish(0);
    }
    final process = _FakeProcess(output: output);
    if (onTest != null) {
      onTest(process);
      return process;
    }
    if (image != null) {
      for (final test in arguments.where((a) => a.endsWith('_test.dart'))) {
        final name = p.basename(test).replaceAll('_test.dart', '');
        File(p.join(imagesDirectory(), '$name.png')).writeAsBytesSync(image);
      }
    }
    return process..finish(testExit);
  };

  Future<SurfaceCaptureResult> capture(
    SurfaceCaptureProcessStarter starter, {
    Duration timeout = surfaceCaptureTimeout,
    Future<void>? cancel,
    String? wrapper,
  }) => captureSurfaceImages(
    projectRoot: app,
    entries: [entry],
    flagRoot: p.join(root.path, 'flutter'),
    wrapper: wrapper,
    processRunner: versionRunner,
    processStarter: starter,
    timeout: timeout,
    cancel: cancel,
  );

  test('renders only stale surfaces and records what it drew', () async {
    final first = await capture(renderer(image: _png));

    expect(first.failure, isNull);
    expect(first.images['paywall.pro_upgrade'], _png);
    expect(started.map((arguments) => arguments.first), ['pub', 'test']);
    expect(started.last, contains('test/paywall.pro_upgrade_test.dart'));
    final record =
        jsonDecode(
              File(
                p.join(p.dirname(imagesDirectory()), 'images.json'),
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    expect(record.keys, ['paywall.pro_upgrade']);

    started.clear();
    final again = await capture(renderer(image: _png));

    expect(again.images['paywall.pro_upgrade'], _png);
    expect(started, isEmpty, reason: 'an unchanged surface is reused');
  });

  test('names the test to run when a surface did not render', () async {
    final result = await capture(renderer(testExit: 1, output: 'boom'));

    expect(
      result.skipped['paywall.pro_upgrade'],
      'it did not render; run `flutter test '
      'test/paywall.pro_upgrade_test.dart` in '
      '${p.join('.restage', 'build', 'surface_capture')} to see why',
    );
  });

  test('says what stopped a surface from rendering', () async {
    final result = await capture(
      renderer(
        onTest: (process) {
          File(
            p.join(imagesDirectory(), 'paywall.pro_upgrade.error.txt'),
          ).writeAsStringSync(
            'Error: Could not find the correct Provider<CartBloc> above '
            'this ProUpgrade Widget.\n\nThis happens because...',
          );
          process.finish(1);
        },
      ),
    );

    expect(
      result.skipped['paywall.pro_upgrade'],
      'it did not render: Could not find the correct Provider<CartBloc> '
      'above this ProUpgrade Widget. If it reads something your app provides '
      'above it, name a function that provides it as previewWrapper in '
      'restage_config.yaml. `flutter test test/paywall.pro_upgrade_test.dart` '
      'in ${p.join('.restage', 'build', 'surface_capture')} shows the whole '
      'error',
    );
  });

  test('draws every surface inside the configured wrapper', () async {
    write('app/lib/preview.dart', '''
import 'package:flutter/widgets.dart';

Widget wrapPreview(Widget child) => child;
''');
    final result = await capture(
      renderer(image: _png),
      wrapper: 'lib/preview.dart#wrapPreview',
    );

    expect(result.images['paywall.pro_upgrade'], _png);
    final source = File(
      p.join(
        p.dirname(imagesDirectory()),
        'test',
        'paywall.pro_upgrade_test.dart',
      ),
    ).readAsStringSync();
    expect(
      source,
      contains(
        "import 'package:$fixturePackageName/preview.dart' "
        'as restage_capture_wrap;',
      ),
    );
    expect(source, contains('wrap: restage_capture_wrap.wrapPreview'));
  });

  test('an edit to the wrapper draws the surfaces again', () async {
    write(
      'app/lib/preview.dart',
      'Widget wrapPreview(Widget child) => child;\n',
    );
    await capture(
      renderer(image: _png),
      wrapper: 'lib/preview.dart#wrapPreview',
    );
    started.clear();
    write(
      'app/lib/preview.dart',
      'Widget wrapPreview(Widget child) => Center(child: child);\n',
    );
    final again = await capture(
      renderer(image: _png),
      wrapper: 'lib/preview.dart#wrapPreview',
    );

    expect(again.images['paywall.pro_upgrade'], _png);
    expect(started.map((arguments) => arguments.first), ['test']);
  });

  test('refuses a wrapper the app does not declare', () async {
    write(
      'app/lib/preview.dart',
      'Widget other(Widget child) => child;\nWidget wrapPreview() => x;\n',
    );
    for (final (spec, reason) in [
      (
        'preview.dart#wrapPreview',
        'previewWrapper in restage_config.yaml must look like '
            '`lib/preview.dart#wrapPreview`, not `preview.dart#wrapPreview`',
      ),
      (
        'lib/../tool/preview.dart#wrapPreview',
        'previewWrapper in restage_config.yaml must look like '
            '`lib/preview.dart#wrapPreview`, not '
            '`lib/../tool/preview.dart#wrapPreview`',
      ),
      (
        'lib/missing.dart#wrapPreview',
        'previewWrapper names lib/missing.dart, which does not exist',
      ),
      (
        'lib/preview.dart#wrapPreview',
        'previewWrapper names `wrapPreview`, which lib/preview.dart does not '
            'declare as `Widget wrapPreview(Widget child)`',
      ),
    ]) {
      final result = await capture(renderer(image: _png), wrapper: spec);
      expect(result.failure, reason);
    }
    expect(started, isEmpty);
  });

  test('kills a render that outlives its deadline', () async {
    final processes = <_FakeProcess>[];
    final result = await capture(
      renderer(onStart: processes.add),
      timeout: const Duration(seconds: 2),
    );

    expect(result.failure, 'rendering took too long');
    expect(processes, hasLength(1));
    expect(processes.single.killed, [ProcessSignal.sigterm]);
  });

  test('kills a render the push no longer needs', () async {
    final started = Completer<_FakeProcess>();
    final result = await capture(
      renderer(onStart: started.complete),
      cancel: started.future,
    );

    expect(result.failure, 'the push stopped first');
    expect((await started.future).killed, [ProcessSignal.sigterm]);
  });

  test('refuses to draw without the SDK fonts', () async {
    File(
      p.join(
        root.path,
        'flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
    ).deleteSync();

    final result = await capture(renderer(image: _png));

    expect(
      result.failure,
      "Flutter's fonts are not downloaded; run `flutter precache`",
    );
    expect(started, isEmpty);
  });

  test('says a surface with no generated widget is not drawn', () async {
    final screen = await seedGeneratedPaywall(
      app,
      slug: 'welcome',
      surface: Surface.onboarding,
    );

    final result = await captureSurfaceImages(
      projectRoot: app,
      entries: [screen],
      flagRoot: p.join(root.path, 'flutter'),
      processRunner: versionRunner,
      processStarter: renderer(image: _png),
    );

    expect(
      result.skipped['onboarding.welcome'],
      'it has no generated widget to draw',
    );
    expect(started, isEmpty);
  });
}
