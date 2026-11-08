import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:logging/logging.dart';
import 'package:package_config/package_config.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/islands/islands.dart'
    show islandNameConflictIssue;
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/islands/island_registration.dart';
import 'package:restage_codegen/src/render_catalog_builder.dart';
import 'package:restage_codegen/src/user_factory_emitter.dart'
    show emitEmptyUserFactoriesDart;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show kMeasurementPublicationTapEventNameV1;
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_codegen/src/user_catalog_json_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';
import '../support/native_flow_fixture_generation.dart';

void main() {
  test(
    'production builder retains compilation provenance on screen uploads',
    () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final config = await findPackageConfig(Directory.current);
      for (final package in config!.packages) {
        final pubspec = File.fromUri(package.root.resolve('pubspec.yaml'));
        if (pubspec.existsSync()) {
          readerWriter.testing.writeString(
            AssetId(package.name, 'pubspec.yaml'),
            pubspec.readAsStringSync(),
          );
        }
      }
      final pending = ['restage_codegen', 'restage', 'rfw_catalog_compiler'];
      final visited = <String>{};
      while (pending.isNotEmpty) {
        final name = pending.removeLast();
        if (!visited.add(name)) continue;
        final package = config[name]!;
        final pubspec =
            loadYaml(
                  File.fromUri(
                    package.root.resolve('pubspec.yaml'),
                  ).readAsStringSync(),
                )
                as Map<Object?, Object?>;
        if (pubspec['dependencies']
            case final Map<Object?, Object?> dependencies) {
          pending.addAll(dependencies.keys.cast<String>());
        }
        final directory = Directory.fromUri(package.packageUriRoot);
        if (!directory.existsSync()) continue;
        await for (final file in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (file is! File ||
              !(file.path.endsWith('.dart') ||
                  file.path.endsWith('.json') ||
                  file.path.endsWith('.yaml'))) {
            continue;
          }
          readerWriter.testing.writeBytes(
            AssetId(name, file.uri.path.substring(package.root.path.length)),
            file.readAsBytesSync(),
          );
        }
      }
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'pubspec.yaml'),
        'name: apps_examples\n',
      );
      const source = """
import 'package:flutter/material.dart' as f;
import 'package:restage/restage.dart' as r;
part 'restage.generated/notice.restage.g.dart';
@r.Screen(id: 'notice', version: 1, surface: r.Surface.general)
class Notice extends f.StatelessWidget {
  const Notice({super.key});
  @override
  f.Widget build(f.BuildContext context) => const f.Text('Notice');
}
""";
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        {'apps_examples|lib/notice.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final bundle = _readBundle(readerWriter);
      final entry = bundle.manifest!.publications.single;
      final provenance = entry.publication.compilationProvenance;
      expect(provenance, isNotNull);
      expect(provenance!.packageVersions, contains('restage_codegen'));
      final roundTrip = SurfacePublicationManifestV1Codec.decodeJson(
        SurfacePublicationManifestV1Codec.encodeCanonicalJson(bundle.manifest!),
      );
      expect(
        roundTrip.publications.single.publication.compilationProvenance!
            .toJson(),
        provenance.toJson(),
      );
    },
  );

  test(
    'canonical paywall threads installed native declarations through artifacts',
    () async {
      const source = '''
import 'package:flutter/material.dart' as f;
import 'package:restage/restage.dart' as r;
part 'restage.generated/native_offer.restage.g.dart';
int shade() => -1;
@r.Paywall(id: 'native_offer')
final class NativeOffer extends f.StatelessWidget {
  const NativeOffer({super.key, required this.swatch});
  final Map<int, f.Color> swatch;
  static const base = 0xff102030;
  static final offset = 0;
  static int get extra => 0;
  static int shade() => base + offset + extra;
  @override
  f.Widget build(f.BuildContext context) => f.LayoutBuilder(builder: (context, constraints) {
    final color = f.MaterialColor(shade() + base - base + offset + extra, swatch);
    return f.ColoredBox(color: color);
  });
}
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        const {'apps_examples|lib/native_offer.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final bundle = _readBundle(readerWriter);
      expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
      final generated = utf8.decode(
        bundle
            .ownedOutputs['lib/restage.generated/native_offer.restage.g.dart']!,
      );
      expect(generated, contains('r.NativeCallAdapter('));
      expect(generated, contains('_restageAs<Map<int, f.Color>>'));
      for (final member in ['shade', 'base', 'offset', 'extra']) {
        expect(generated, contains('NativeOffer.$member'));
      }
      expect(bundle.artifacts, contains('assets/paywalls/native_offer.rfw'));
      await _expectAnalyzesClean({
        'apps_examples|lib/native_offer.dart': source,
        'apps_examples|lib/restage.generated/native_offer.restage.g.dart':
            generated,
      });
    },
  );

  test(
    'canonical native identity is stable across physical package roots',
    () async {
      const source = '''
import 'package:flutter/material.dart' as f;
import 'package:restage/restage.dart' as r;
part 'restage.generated/native_offer.restage.g.dart';
@r.Paywall(id: 'native_offer')
final class NativeOffer extends f.StatelessWidget {
  const NativeOffer({super.key});
  static const seed = 0xff102030;
  static final swatch = <int, f.Color>{500: const f.Color(seed)};
  @override
  f.Widget build(f.BuildContext context) => f.LayoutBuilder(builder: (context, constraints) {
    final color = f.MaterialColor(seed, swatch);
    return f.ColoredBox(color: color);
  });
}
''';
      final config = (await findPackageConfig(Directory.current))!;
      final roots = [
        Directory.systemTemp.createTempSync('native-source-a-'),
        Directory.systemTemp.createTempSync('native-source-b-'),
      ];
      addTearDown(() {
        for (final root in roots) {
          root.deleteSync(recursive: true);
        }
      });
      final outputs = <String>[];
      for (final root in roots) {
        final file = File.fromUri(root.uri.resolve('lib/native_offer.dart'));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(source);
        final relocated = PackageConfig([
          for (final package in config.packages)
            if (package.name == 'apps_examples')
              Package(
                package.name,
                root.uri,
                packageUriRoot: root.uri.resolve('lib/'),
                languageVersion: package.languageVersion,
              )
            else
              package,
        ]);
        final readerWriter = await readerWriterWithFilesystemSources(
          rootPackage: 'apps_examples',
        );
        final result = await testBuilder(
          const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
          {'apps_examples|lib/native_offer.dart': file.readAsStringSync()},
          packageConfig: relocated,
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          flattenOutput: true,
        );
        expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
        final bundle = _readBundle(readerWriter);
        expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
        final generated = utf8.decode(
          bundle
              .ownedOutputs['lib/restage.generated/native_offer.restage.g.dart']!,
        );
        expect(generated, contains('r.NativeCallAdapter('));
        outputs.add(generated);
      }
      expect(outputs[0], outputs[1]);
    },
  );

  test(
    'canonical native factories preserve free library names outside mount scope',
    () async {
      const source = '''
import 'package:flutter/material.dart' as f;
import 'package:restage/restage.dart' as r;
part 'restage.generated/native_offer.restage.g.dart';
const context = <int, f.Color>{500: f.Color(0xff102030)};
const loadingBuilder = context;
@r.Paywall(id: 'native_offer')
final class NativeOffer extends f.StatelessWidget {
  const NativeOffer({super.key});
  @override
  f.Widget build(f.BuildContext ctx) => f.ColoredBox(
    color: const f.MaterialColor(0xff102030, context),
    child: f.ColoredBox(color: const f.MaterialAccentColor(0xff102030, loadingBuilder)));
}
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        {'apps_examples|lib/native_offer.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final bundle = _readBundle(readerWriter);
      expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
      final generated = utf8.decode(
        bundle
            .ownedOutputs['lib/restage.generated/native_offer.restage.g.dart']!,
      );
      expect(
        generated.indexOf('const f.MaterialColor('),
        lessThan(generated.indexOf('final class NativeOfferSurface')),
      );
      await _expectAnalyzesClean({
        'apps_examples|lib/native_offer.dart': source,
        'apps_examples|lib/restage.generated/native_offer.restage.g.dart':
            generated,
      });
    },
  );

  test(
    'canonical helper native plans use destination imports; a private name renders from the app',
    () async {
      const screen = '''
import 'package:flutter/material.dart' as _restageInputs;
import 'package:restage/restage.dart' as r;
import 'helper.dart' as h;
part 'restage.generated/native_offer.restage.g.dart';
@r.Paywall(id: 'native_offer')
final class NativeOffer extends _restageInputs.StatelessWidget {
  const NativeOffer({super.key});
  @override
  _restageInputs.Widget build(_restageInputs.BuildContext context) => h.box();
}
''';
      for (final private in [false, true]) {
        final swatch = private ? '_swatch' : 'swatch';
        final helper =
            '''
import 'package:flutter/material.dart' as f;
final $swatch = <int, f.Color>{500: const f.Color(0xff102030)};
f.Widget box() => f.LayoutBuilder(builder: (context, constraints) {
  final color = f.MaterialColor(0xff102030, $swatch);
  return f.ColoredBox(color: color);
});
''';
        final readerWriter = await readerWriterWithFilesystemSources(
          rootPackage: 'apps_examples',
        );
        final result = await testBuilder(
          const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
          {
            'apps_examples|lib/native_offer.dart': screen,
            'apps_examples|lib/helper.dart': helper,
          },
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          flattenOutput: true,
        );
        expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
        final bundle = _readBundle(readerWriter);
        expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
        final generated = utf8.decode(
          bundle
              .ownedOutputs['lib/restage.generated/native_offer.restage.g.dart']!,
        );
        if (private) {
          // A private name can't be spelled here, so the helper renders whole
          // from the app, as an island.
          expect(
            generated,
            contains("_restageRecording.island('native__offer_box_0', h.box()"),
          );
          expect(generated, isNot(contains('_swatch')));
        } else {
          expect(generated, contains('_restageInputs.MaterialColor'));
          expect(generated, contains('h.swatch'));
          expect(generated, contains('_restage_Inputs'));
          expect(generated, isNot(contains('f.MaterialColor')));
        }
        await _expectAnalyzesClean({
          'apps_examples|lib/native_offer.dart': screen,
          'apps_examples|lib/helper.dart': helper,
          'apps_examples|lib/restage.generated/native_offer.restage.g.dart':
              generated,
        });
      }
    },
  );

  group('tracked package Measurement policy', () {
    test('shares one policy within a package', () async {
      final compilations = await _runPolicyProbe({
        'apps_examples': [
          MeasurementCompilerPolicyInput.shippedDefault,
          MeasurementCompilerPolicyInput.shippedDefault,
        ],
      });

      final packageCompilations = compilations['apps_examples']!;
      expect(
        identical(packageCompilations.first, packageCompilations.last),
        isTrue,
      );
      expect(
        packageCompilations.map((compilation) => compilation.isValid),
        orderedEquals([true, true]),
      );
    });

    test('rejects conflicting policies within a package', () async {
      final compilations = await _runPolicyProbe({
        'apps_examples': [
          MeasurementCompilerPolicyInput.shippedDefault,
          _alternateMeasurementPolicy,
        ],
      });

      final packageCompilations = compilations['apps_examples']!;
      expect(
        packageCompilations.map((compilation) => compilation.isValid),
        orderedEquals([true, false]),
      );
      final issue = packageCompilations.last.issues.single;
      expect(issue.code.name, 'conflictingTargetConfig');
      expect(issue.message, contains('Measurement policy options conflict'));
    });

    test('accepts distinct policies for distinct packages', () async {
      final compilations = await _runPolicyProbe({
        'apps_examples': [MeasurementCompilerPolicyInput.shippedDefault],
        'restage_codegen': [_alternateMeasurementPolicy],
      });

      expect(compilations['apps_examples']!.single.isValid, isTrue);
      expect(compilations['restage_codegen']!.single.isValid, isTrue);
    });
  });

  test(
    'ledger writer replaces its target through an adjacent temporary file',
    () {
      final root = Directory.systemTemp.createTempSync(
        'restage-measurement-ledger-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final file = File(
        '${root.path}/nested/restage_measurement.compiler.json',
      );
      final first = utf8.encode('{"value":"first"}');
      final second = utf8.encode('{"value":"second"}');

      writeMeasurementCompilerLedgerSource(
        file: file,
        bytes: first,
        processId: 41,
      );
      expect(file.readAsBytesSync(), orderedEquals(first));
      expect(File('${file.path}.tmp.41').existsSync(), isFalse);

      writeMeasurementCompilerLedgerSource(
        file: file,
        bytes: second,
        processId: 42,
      );
      expect(file.readAsBytesSync(), orderedEquals(second));
      expect(File('${file.path}.tmp.42').existsSync(), isFalse);
    },
  );

  test(
    'compiles tracked arbitrary-directory sources into the fixed bundle',
    () async {
      const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/announcement.restage.g.dart';

@Screen(surface: Surface.general)
final class FeatureAnnouncement extends StatelessWidget {
  const FeatureAnnouncement({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  Widget build(BuildContext context) => const Text('Announcement');
}
''';
      const flow = '''
import 'package:restage/restage.dart';

import '../features/announcement.dart';

part 'restage.generated/launch.restage.g.dart';

@FlowGraph(surface: Surface.general)
const launch = FlowDefinition(
  start: FeatureAnnouncement,
  transitions: [
    Transition.complete(FeatureAnnouncement.dismiss),
  ],
);
''';
      final sources = <String, String>{
        'apps_examples|lib/features/announcement.dart': screen,
        'apps_examples|lib/journeys/launch.dart': flow,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final logs = <LogRecord>[];
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
        onLog: logs.add,
        verbose: true,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final encoded = readerWriter.testing.readString(
        AssetId(
          'apps_examples',
          kRestageSurfacePublicationCompilerBundlePath,
        ),
      );
      final bundle = RestageSurfacePublicationBundle.fromJson(
        jsonDecode(encoded),
      );
      expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
      expect(
        bundle.manifest!.publications
            .map((entry) => entry.publication.slug)
            .toList(),
        orderedEquals(['announcement', 'launch']),
      );
      expectArtifactsFor(bundle.artifacts.keys, <String>[
        'assets/general/screens/announcement.rfw',
        'assets/general/screens/announcement.capability.json',
        'assets/general/flows/launch.flow.json',
      ]);
      expect(
        bundle.ownedOutputs.keys,
        containsAll(<String>[
          'assets/general/screens/announcement.rfwtxt',
          'lib/features/restage.generated/announcement.restage.g.dart',
          'lib/journeys/restage.generated/launch.restage.g.dart',
        ]),
      );
      expect(
        utf8.decode(
          bundle.ownedOutputs['assets/general/screens/announcement.rfwtxt']!,
        ),
        contains('"Announcement"'),
      );
      expect(
        collapsedWhitespace(
          utf8.decode(
            bundle
                .ownedOutputs['lib/features/restage.generated/announcement.restage.g.dart']!,
          ),
        ),
        matches(
          RegExp(r'SurfaceScreenRef<\s*FeatureAnnouncementSurfaceEvent\s*>'),
        ),
      );
      expect(
        utf8.decode(
          bundle
              .ownedOutputs['lib/journeys/restage.generated/launch.restage.g.dart']!,
        ),
        contains('SurfaceFlowRef<LaunchResult>'),
      );
      final summaries = logs
          .where((record) => record.message.contains('[restage] Compiled'))
          .map((record) => record.message)
          .toList();
      expect(summaries, hasLength(1));
      expect(summaries.single, contains('2 surfaces'));
      expect(summaries.single, contains('1 screen'));
      expect(summaries.single, contains('1 flow'));
      expect(summaries.single, contains('FeatureAnnouncementSurface'));
      expect(summaries.single, contains('LaunchSurface'));
      expect(summaries.single, contains('generated surface classes: '));
    },
  );

  test(
    'does not report compilation success for a package without surfaces',
    () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final logs = <LogRecord>[];
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        const {'apps_examples|lib/plain.dart': 'class Plain {}'},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
        onLog: logs.add,
        verbose: true,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(
        logs.map((record) => record.message),
        everyElement(isNot(contains('[restage] Compiled'))),
      );
    },
  );

  test("a standalone screen's mount records its islands", () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/tips.restage.g.dart';

class Painted extends StatelessWidget {
  const Painted({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: null, child: child);
}

@Screen(id: 'tips', surface: Surface.general)
final class Tips extends StatelessWidget {
  const Tips({super.key});
  @override
  Widget build(BuildContext context) =>
      Column(children: [const Text('x'), Painted(child: const Text('tip'))]);
}
''';
    late RestageSurfacePublicationBundle bundle;
    final part = await _generatedPart(
      screen,
      'tips',
      handoff: (b) => bundle = b,
    );
    final host = _hostContractOf(part, '');
    expect(host.islands, isNotEmpty);
    expect(bundle.surfaceIslands['general/tips'], host.islands.keys);
    expect(
      [for (final site in bundle.splitSites) site.mount],
      everyElement('TipsSurface'),
    );
  });

  test('emits valid mount types for legacy callback formals', () async {
    // `final` and `var` on a function-typed formal's parameter are illegal
    // from Dart 3.13, so the modifiers this covers only exist below it.
    const screen = '''
// @dart=3.12
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/callbacks.restage.g.dart';

@Screen(id: 'callbacks', surface: Surface.general)
final class Callbacks extends StatelessWidget {
  const Callbacks(
    void callback(final int value),
    void looseCallback(var value),
    void nullableCallback(int value)?,
    void annotatedCallback(@Deprecated('x') int value), {
    super.key,
  }) : callback = callback,
       looseCallback = looseCallback,
       nullableCallback = nullableCallback,
       annotatedCallback = annotatedCallback;

  final void Function(int) callback;
  final void Function(dynamic) looseCallback;
  final void Function(int)? nullableCallback;
  final void Function(int) annotatedCallback;

  @override
  Widget build(BuildContext context) => const Text('Callbacks');
}
''';
    final descriptor = await _generatedPart(screen, 'callbacks');
    expect(descriptor, contains('void Function(int value) callback'));
    expect(
      descriptor,
      contains('void Function(dynamic value) looseCallback'),
    );
    expect(
      descriptor,
      contains('final void Function(int value) _restageStored0;'),
    );
    expect(
      descriptor,
      contains('final void Function(dynamic value) _restageStored1;'),
    );
    expect(
      descriptor,
      contains('final void Function(int value)? _restageStored2;'),
    );
    expect(
      descriptor,
      contains('final void Function(int value) _restageStored3;'),
    );
    expect(descriptor, isNot(contains('Function(final')));
    expect(descriptor, isNot(contains('Function(var')));
    expect(descriptor, isNot(contains('@Deprecated')));
  });

  test('mirrors the library language override on the generated part', () async {
    const screen = '''
// @dart=3.6
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/pinned_language.restage.g.dart';

@Screen(id: 'pinned_language', surface: Surface.general)
final class PinnedLanguage extends StatelessWidget {
  const PinnedLanguage({super.key});

  @override
  Widget build(BuildContext context) => const Text('Pinned language');
}
''';
    final descriptor = await _generatedPart(
      screen,
      'pinned_language',
    );
    expect(descriptor, startsWith('// @dart=3.6\npart of '));
  });

  test('keeps qualified types outside a generic callback scope', () async {
    const screen = '''
import 'dart:typed_data';
import 'dart:typed_data' as data;
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/captured_callback.restage.g.dart';

@Screen(id: 'captured_callback', surface: Surface.general)
final class CapturedCallback extends StatelessWidget {
  const CapturedCallback(
    void callback<Uint8List>(data.Uint8List value), {
    super.key,
  }) : callback = callback;

  final void Function<Uint8List>(data.Uint8List) callback;

  @override
  Widget build(BuildContext context) => const Text('Captured callback');
}
''';
    final descriptor = await _generatedPart(
      screen,
      'captured_callback',
    );

    expect(
      descriptor,
      contains(
        'void Function<Uint8List>(data.Uint8List value) callback',
      ),
    );
    expect(
      descriptor,
      contains(
        'final void Function<Uint8List>(data.Uint8List value) '
        '_restageStored0;',
      ),
    );
    expect(
      descriptor,
      isNot(contains('Function<Uint8List>(Uint8List)')),
    );
  });

  test('qualifies a forwarded callback under a generic shadow', () async {
    const screen = '''
import 'dart:typed_data';
import 'dart:typed_data' as data;
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/forwarded_callback.restage.g.dart';

abstract class CallbackBase extends StatelessWidget {
  const CallbackBase(this.callback, {super.key});
  final void Function<Uint8List>(data.Uint8List)? callback;
}

@Screen(id: 'forwarded_callback', surface: Surface.general)
final class ForwardedCallback extends CallbackBase {
  const ForwardedCallback(super.callback, {super.key});

  @override
  Widget build(BuildContext context) => const Text('Forwarded callback');
}
''';
    final descriptor = await _generatedPart(
      screen,
      'forwarded_callback',
    );

    expect(
      descriptor,
      contains(
        'final void Function<Uint8List>(data.Uint8List)? _restageStored0;',
      ),
    );
    expect(descriptor, isNot(contains('Function<Uint8List>(Uint8List)')));
  });

  test('keeps an explicit backed super callback type', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/inherited_callback.restage.g.dart';

abstract class CallbackBase extends StatelessWidget {
  const CallbackBase(this.callback, {super.key});
  final void Function(int) callback;
}

@Screen(id: 'inherited_callback', surface: Surface.general)
final class InheritedCallback extends CallbackBase {
  const InheritedCallback(void super.callback(num value), {super.key});

  @override
  Widget build(BuildContext context) => const Text('Inherited callback');
}
''';
    final descriptor = await _generatedPart(
      screen,
      'inherited_callback',
    );

    expect(
      descriptor,
      contains('void Function(num value) callback'),
    );
    expect(
      descriptor,
      contains('final void Function(num value) _restageStored0;'),
    );
    expect(descriptor, isNot(contains('void Function(int) callback')));
  });

  test(
    'compiles callback-free static collection leaves with measurement',
    () async {
      const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/collection_labels.restage.g.dart';

@Screen(id: 'collection_labels', surface: Surface.general)
final class CollectionLabels extends StatelessWidget {
  const CollectionLabels({super.key});
  static const third = Text('third');

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final label in const ['first', 'second']) Text(label),
          if (true) third,
          ...const [Text('fourth')],
        ],
      );
}
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(
          BuilderOptions({
            kMeasurementMinimumClientOption: 1,
            kMeasurementPrivacyPolicyRevisionOption: 'privacy.default',
            kMeasurementCollectionBudgetRevisionOption: 'budget.default',
          }),
        ),
        const <String, String>{
          'apps_examples|lib/features/collection_labels.dart': screen,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final bundle = _readBundle(readerWriter);
      expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
      final text = utf8.decode(
        bundle.ownedOutputs['assets/general/screens/collection_labels.rfwtxt']!,
      );
      expect(text, contains('"first"'));
      expect(text, contains('"second"'));
      expect(text, contains('"third"'));
      expect(text, contains('"fourth"'));
    },
  );

  test('publishes helper-bound const-object widget fields', () async {
    const sources = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/bound_receiver.restage.g.dart';

final class ActionSet {
  const ActionSet(this.widget);
  final Widget widget;
}

@Screen(id: 'bound_receiver', surface: Surface.general)
final class BoundReceiver extends StatelessWidget {
  const BoundReceiver({super.key});
  static const set = ActionSet(Text('accepted'));

  List<Widget> select(ActionSet source) => [if (true) source.widget];

  @override
  Widget build(BuildContext context) =>
      Column(children: [...select(set)]);
}

@Paywall(id: 'bound_receiver_offer')
final class BoundReceiverOffer extends StatelessWidget {
  const BoundReceiverOffer({super.key});
  static const set = ActionSet(Text('accepted'));

  List<Widget> select(ActionSet source) => [if (true) source.widget];

  @override
  Widget build(BuildContext context) =>
      Column(children: [...select(set)]);
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(
        BuilderOptions({
          kMeasurementMinimumClientOption: 1,
          kMeasurementPrivacyPolicyRevisionOption: 'privacy.default',
          kMeasurementCollectionBudgetRevisionOption: 'budget.default',
        }),
      ),
      const <String, String>{
        'apps_examples|lib/features/bound_receiver.dart': sources,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
    for (final path in [
      'assets/general/screens/bound_receiver.rfwtxt',
      'assets/paywalls/bound_receiver_offer.rfwtxt',
    ]) {
      final text = utf8.decode(bundle.ownedOutputs[path]!);
      expect(text, contains('Text(text: "accepted")'));
      expect(text, isNot(contains('source.widget')));
    }
  });

  test(
    'mixed const and runtime object receivers render from the app',
    () async {
      const sources = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/mixed_receiver.restage.g.dart';

final class WidgetSet {
  const WidgetSet(this.widgets);
  final List<Widget> widgets;
}

@Screen(id: 'mixed_receiver', surface: Surface.general)
final class MixedReceiver extends StatelessWidget {
  const MixedReceiver({required this.selectConstant, super.key});
  final bool selectConstant;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ...(selectConstant
            ? const WidgetSet(<Widget>[Text('constant')])
            : WidgetSet(<Widget>[const Text('runtime')]))
          .widgets,
    ],
  );
}

@Paywall(id: 'mixed_receiver_offer')
final class MixedReceiverOffer extends StatelessWidget {
  const MixedReceiverOffer({required this.selectConstant, super.key});
  final bool selectConstant;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ...(selectConstant
            ? const WidgetSet(<Widget>[Text('constant')])
            : WidgetSet(<Widget>[const Text('runtime')]))
          .widgets,
    ],
  );
}
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(
          BuilderOptions({
            kMeasurementMinimumClientOption: 1,
            kMeasurementPrivacyPolicyRevisionOption: 'privacy.default',
            kMeasurementCollectionBudgetRevisionOption: 'budget.default',
          }),
        ),
        const <String, String>{
          'apps_examples|lib/features/mixed_receiver.dart': sources,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      final errors = result.errors.join('\n');

      // A screen splits like a paywall: what cannot lower renders from the
      // app, so nothing is refused.
      expect(result.succeeded, isTrue, reason: errors);
    },
  );

  test(
    'compiles hidden custom collection leaves for screens and paywalls',
    () async {
      const sources = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'restage.generated/hidden_collection.restage.g.dart';

final class WidgetSet {
  const WidgetSet(this.widget);
  final Widget widget;
}

@RestageWidget(
  name: 'HiddenLabel',
  library: WidgetLibrary.custom('fixture.hidden'),
  category: WidgetCategory.content,
  description: 'Hidden label.',
)
final class HiddenLabel extends StatelessWidget {
  const HiddenLabel({super.key});

  @override
  Widget build(BuildContext context) => const Text('resolved');
}

const hiddenLabel = HiddenLabel();
const widgetSet = WidgetSet(hiddenLabel);
const collectionEntries = <Widget>[if (true) widgetSet.widget];

@Screen(id: 'hidden_collection', surface: Surface.general)
final class HiddenCollection extends StatelessWidget {
  const HiddenCollection({super.key});

  @override
  Widget build(BuildContext context) =>
      Column(children: [...collectionEntries]);
}

@Paywall(id: 'hidden_collection_offer')
final class HiddenCollectionOffer extends StatelessWidget {
  const HiddenCollectionOffer({super.key});

  @override
  Widget build(BuildContext context) =>
      Column(children: [...collectionEntries]);
}
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final catalogBuild = await testBuilder(
        const UserCatalogJsonBuilder(BuilderOptions.empty),
        const <String, String>{
          'apps_examples|lib/features/hidden_collection.dart': sources,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(
        catalogBuild.succeeded,
        isTrue,
        reason: catalogBuild.errors.join('\n'),
      );
      final catalog = readerWriter.testing.readString(
        AssetId(
          'apps_examples',
          'lib/src/widget_catalog/catalog.json',
        ),
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(
          BuilderOptions({
            kMeasurementMinimumClientOption: 1,
            kMeasurementPrivacyPolicyRevisionOption: 'privacy.default',
            kMeasurementCollectionBudgetRevisionOption: 'budget.default',
          }),
        ),
        <String, String>{
          'apps_examples|lib/features/hidden_collection.dart': sources,
          'apps_examples|lib/src/widget_catalog/catalog.json': catalog,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final bundle = _readBundle(readerWriter);
      expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
      for (final path in [
        'assets/general/screens/hidden_collection.rfwtxt',
        'assets/paywalls/hidden_collection_offer.rfwtxt',
      ]) {
        final text = utf8.decode(bundle.ownedOutputs[path]!);
        expect(text, contains('HiddenLabel()'));
        expect(text, contains('Text(text: "resolved")'));
      }
    },
  );

  test('inlines a custom widget absent from the package catalog', () async {
    const sources = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'restage.generated/plain_badge.restage.g.dart';

@RestageWidget(
  name: 'PlainBadge',
  library: WidgetLibrary.custom('fixture.badge'),
  category: WidgetCategory.content,
  description: 'Badge.',
)
final class PlainBadge extends StatelessWidget {
  const PlainBadge({super.key, required this.label});

  /// The badge text.
  final String label;

  @override
  Widget build(BuildContext context) => Text(label);
}

@Screen(id: 'plain_badge', surface: Surface.general)
final class PlainBadgeScreen extends StatelessWidget {
  const PlainBadgeScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Column(children: [PlainBadge(label: 'streak')]);
}

@Paywall(id: 'plain_badge_offer')
final class PlainBadgeOffer extends StatelessWidget {
  const PlainBadgeOffer({super.key});

  @override
  Widget build(BuildContext context) =>
      const Column(children: [PlainBadge(label: 'streak')]);
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(
        BuilderOptions({
          kMeasurementMinimumClientOption: 1,
          kMeasurementPrivacyPolicyRevisionOption: 'privacy.default',
          kMeasurementCollectionBudgetRevisionOption: 'budget.default',
        }),
      ),
      const <String, String>{
        'apps_examples|lib/features/plain_badge.dart': sources,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
    for (final path in [
      'assets/general/screens/plain_badge.rfwtxt',
      'assets/paywalls/plain_badge_offer.rfwtxt',
    ]) {
      final text = utf8.decode(bundle.ownedOutputs[path]!);
      expect(text, contains('PlainBadge(label: "streak")'));
      expect(text, contains('widget PlainBadge'));
    }
    // A paywall whose mount passes nothing carries no host data.
    final paywall = bundle.manifest!.publications
        .map((entry) => entry.publication)
        .singleWhere((publication) => publication.slug == 'plain_badge_offer');
    expect(paywall.hostDataContract, isNull);
    expect(paywall.hostDataContractHash, isNull);
  });

  test('leaves a dependency package to compile in its own build', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/dependency_screen.restage.g.dart';

@Screen(id: 'dependency_screen', surface: Surface.general)
final class DependencyScreen extends StatelessWidget {
  const DependencyScreen({super.key});

  @override
  Widget build(BuildContext context) => const Text('dependency');
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      restagePackageSurfaceCompilerBuilder(
        const BuilderOptions({'bundled_runtime': true}),
      ),
      const <String, String>{
        'apps_examples|lib/features/dependency_screen.dart': screen,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    expect(
      readerWriter.testing.exists(
        AssetId('apps_examples', kRestageSurfacePublicationCompilerBundlePath),
      ),
      isFalse,
    );
  });

  test('reused callback collection sources render from the app', () async {
    const sources = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/reused_actions.restage.g.dart';

final class ActionSet {
  const ActionSet(this.widget);
  final Widget widget;
}

List<Widget> selectAction(Widget value) => [value];

@Screen(id: 'reused_actions', surface: Surface.general)
final class ReusedActions extends StatelessWidget {
  const ReusedActions({super.key});
  static void activate() {}
  static const action = ElevatedButton(
    onPressed: activate,
    child: Text('Activate'),
  );
  static const set = ActionSet(action);
  List<Widget> actions() => selectAction(set.widget);

  @override
  Widget build(BuildContext context) =>
      Column(children: [...actions(), ...actions()]);
}

@Paywall(id: 'reused_actions_offer')
final class ReusedActionsOffer extends StatelessWidget {
  const ReusedActionsOffer({super.key});
  static void activate() {}
  static const action = ElevatedButton(
    onPressed: activate,
    child: Text('Activate'),
  );
  static const set = ActionSet(action);
  List<Widget> actions() => selectAction(set.widget);

  @override
  Widget build(BuildContext context) =>
      Column(children: [...actions(), ...actions()]);
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(
        BuilderOptions({
          kMeasurementMinimumClientOption: 1,
          kMeasurementPrivacyPolicyRevisionOption: 'privacy.default',
          kMeasurementCollectionBudgetRevisionOption: 'budget.default',
        }),
      ),
      const <String, String>{
        'apps_examples|lib/features/reused_actions.dart': sources,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    // A screen splits like a paywall: what cannot lower renders from the
    // app, so nothing is refused.
    expect(result.succeeded, isTrue, reason: result.errors.join("\n"));
  });

  test(
    'callback reuse across nested sibling lists renders from the app',
    () async {
      const sources = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/nested_actions.restage.g.dart';

List<Widget> actions() => [
      ElevatedButton(
        onPressed: () {},
        child: const Text('Activate'),
      ),
    ];

@Screen(id: 'nested_actions', surface: Surface.general)
final class NestedActions extends StatelessWidget {
  const NestedActions({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Row(children: [...actions()]),
          Row(children: [...actions()]),
        ],
      );
}

@Paywall(id: 'nested_actions_offer')
final class NestedActionsOffer extends StatelessWidget {
  const NestedActionsOffer({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Row(children: [...actions()]),
          Row(children: [...actions()]),
        ],
      );
}
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(
          BuilderOptions({
            kMeasurementMinimumClientOption: 1,
            kMeasurementPrivacyPolicyRevisionOption: 'privacy.default',
            kMeasurementCollectionBudgetRevisionOption: 'budget.default',
          }),
        ),
        const <String, String>{
          'apps_examples|lib/features/nested_actions.dart': sources,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      final errors = result.errors.join('\n');

      // A screen splits like a paywall: what cannot lower renders from the
      // app, so nothing is refused.
      expect(result.succeeded, isTrue, reason: errors);
    },
  );

  test(
    'one callback source shared by two event slots renders from the app',
    () async {
      const sources = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/shared_slots.restage.g.dart';

List<Widget> actions(VoidCallback callback) => [
      GestureDetector(
        onTap: callback,
        onDoubleTap: callback,
        child: const Text('Activate'),
      ),
    ];

@Screen(id: 'shared_slots', surface: Surface.general)
final class SharedSlots extends StatelessWidget {
  const SharedSlots({super.key});

  @override
  Widget build(BuildContext context) =>
      Column(children: [...actions(() {})]);
}

@Paywall(id: 'shared_slots_offer')
final class SharedSlotsOffer extends StatelessWidget {
  const SharedSlotsOffer({super.key});

  @override
  Widget build(BuildContext context) =>
      Column(children: [...actions(() {})]);
}
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(
          BuilderOptions({
            kMeasurementMinimumClientOption: 1,
            kMeasurementPrivacyPolicyRevisionOption: 'privacy.default',
            kMeasurementCollectionBudgetRevisionOption: 'budget.default',
          }),
        ),
        const <String, String>{
          'apps_examples|lib/features/shared_slots.dart': sources,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      final errors = result.errors.join('\n');

      // A screen splits like a paywall: what cannot lower renders from the
      // app, so nothing is refused.
      expect(result.succeeded, isTrue, reason: errors);
    },
  );

  test(
    'rejects a helper root sharing one callback across event slots',
    () async {
      const sources = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/helper_slots.restage.g.dart';

Widget action(VoidCallback callback) => GestureDetector(
      onTap: callback,
      onDoubleTap: callback,
      child: const Text('Activate'),
    );

@Screen(id: 'helper_slots', surface: Surface.general)
final class HelperSlots extends StatelessWidget {
  const HelperSlots({super.key});

  @override
  Widget build(BuildContext context) => action(() {});
}

@Paywall(id: 'helper_slots_offer')
final class HelperSlotsOffer extends StatelessWidget {
  const HelperSlotsOffer({super.key});

  @override
  Widget build(BuildContext context) => action(() {});
}
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(
          BuilderOptions({
            kMeasurementMinimumClientOption: 1,
            kMeasurementPrivacyPolicyRevisionOption: 'privacy.default',
            kMeasurementCollectionBudgetRevisionOption: 'budget.default',
          }),
        ),
        const <String, String>{
          'apps_examples|lib/features/helper_slots.dart': sources,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      final errors = result.errors.join('\n');

      expect(result.succeeded, isFalse);
      expect(
        errors,
        contains('callback-bearing static collection source is reused'),
      );
      expect(
        errors,
        isNot(
          contains(
            'One exact callback expression cannot carry two measurement routes',
          ),
        ),
      );
    },
  );

  test(
    'materializes one neutral screen for two containing flow surfaces',
    () async {
      const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome.restage.g.dart';

@Screen()
final class Welcome extends StatelessWidget {
  const Welcome({super.key});
  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Welcome');
}
''';
      const onboardingFlow = '''
import 'package:restage/restage.dart';
import '../shared/welcome.dart';
part 'restage.generated/onboarding.restage.g.dart';

@FlowGraph(surface: Surface.onboarding)
const onboarding = FlowDefinition(
  start: Welcome,
  transitions: [Transition.complete(Welcome.finish)],
);
''';
      const messageFlow = '''
import 'package:restage/restage.dart';
import '../shared/welcome.dart';
part 'restage.generated/message.restage.g.dart';

@FlowGraph(surface: Surface.message)
const message = FlowDefinition(
  start: Welcome,
  transitions: [Transition.complete(Welcome.finish)],
);
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        <String, String>{
          'apps_examples|lib/shared/welcome.dart': screen,
          'apps_examples|lib/journeys/onboarding.dart': onboardingFlow,
          'apps_examples|lib/journeys/message.dart': messageFlow,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final bundle = _readBundle(readerWriter);
      expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
      const onboardingBlob = 'assets/onboarding/screens/welcome.rfw';
      const messageBlob = 'assets/message/screens/welcome.rfw';
      expect(artifactFor(bundle.artifacts, onboardingBlob), isNotEmpty);
      expect(artifactFor(bundle.artifacts, messageBlob), isNotEmpty);
      // Each containing flow is its own publication, so one neutral screen is
      // materialized twice and each copy carries that publication's identity.
      final onboardingText = _declarativeText(
        artifactFor(bundle.artifacts, onboardingBlob),
      );
      final messageText = _declarativeText(
        artifactFor(bundle.artifacts, messageBlob),
      );
      expect(
        _withoutMeasurementIdentity(onboardingText),
        _withoutMeasurementIdentity(messageText),
        reason:
            'one neutral screen materializes the same widget for both '
            'containing flows',
      );
      expect(
        onboardingText,
        isNot(messageText),
        reason:
            'each materialization carries its own publication identity, so '
            'one cannot be attributed to the other',
      );
      expect(
        bundle.manifest!.publications
            .map((entry) => entry.publication.slug)
            .toList(),
        orderedEquals(['message', 'onboarding']),
        reason: 'a neutral screen is flow-owned, never standalone',
      );
    },
  );

  test('records a flow screen where the bundle actually emits it', () async {
    // One screen inside two flows is claimed twice, so each publication owns
    // its own copy at its own path. A client finds a screen by joining the
    // surface directory to the location its flow document records, so this
    // pins that join against the artifacts the bundle emits.
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/shared_entry.restage.g.dart';

@Screen(id: 'shared_entry', surface: Surface.general)
final class SharedEntry extends StatelessWidget {
  const SharedEntry({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => const Text('Shared entry');
}
''';
    const first = '''
import 'package:restage/restage.dart';

import '../ui/shared_entry.dart';

part 'restage.generated/first_journey.restage.g.dart';

@FlowGraph(id: 'first_journey', surface: Surface.general)
const firstJourney = FlowDefinition(
  start: SharedEntry,
  transitions: [Transition.complete(SharedEntry.next)],
);
''';
    const second = '''
import 'package:restage/restage.dart';

import '../ui/shared_entry.dart';

part 'restage.generated/second_journey.restage.g.dart';

@FlowGraph(id: 'second_journey', surface: Surface.general)
const secondJourney = FlowDefinition(
  start: SharedEntry,
  transitions: [Transition.complete(SharedEntry.next)],
);
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/ui/shared_entry.dart': screen,
        'apps_examples|lib/journeys/first_journey.dart': first,
        'apps_examples|lib/journeys/second_journey.dart': second,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
    final documents =
        bundle.artifacts.keys
            .where((path) => path.endsWith('.flow.json'))
            .toList()
          ..sort();
    expect(
      documents,
      orderedEquals(<String>[
        'assets/general/flows/first_journey.flow.json',
        'assets/general/flows/second_journey.flow.json',
      ]),
    );
    final located = <String>{};
    for (final path in documents) {
      final document = FlowDocumentCodec.decodeJson(
        utf8.decode(bundle.artifacts[path]!),
      );
      for (final entry in document.screenArtifacts.entries) {
        // The exact join a client performs to load the screen.
        final blobPath = 'assets/general/screens/${entry.value.path}';
        expect(
          bundle.artifacts,
          contains(blobPath),
          reason: '$path records ${entry.key} at a location the bundle emits',
        );
        expect(
          FlowContentHash.compute(bundle.artifacts[blobPath]!),
          entry.value.contentHash,
          reason: '$path records the hash of the blob at $blobPath',
        );
        located.add(blobPath);
      }
    }
    expect(
      located,
      hasLength(2),
      reason: 'each containing flow resolves to its own copy of the screen',
    );
  });

  test('compiled flow fixture retains original constructors '
      'and exact child graphs', () async {
    final candidate = await compileNativeFlowFixture();
    final source = candidate.source;
    final result = candidate.result;
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = candidate.bundle;
    expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
    final generated = candidate.generated;
    await _expectAnalyzesClean({
      'apps_examples|lib/native_flow.dart':
          '''
$source
const originalNotice = NativeNoticeSurface('original', 3);
const defaultNotice = NativeNoticeSurface('default');
const namedNotice = NativeNoticeSurface.atPlacement('notice_card', 'named', 4);
const originalOffer = NativeOfferSurface();
const namedOffer = NativeOfferSurface.atPlacement('offer_card');

Future<void> presentNotice(BuildContext context) => Restage.presentPlacement(
  context,
  builder: (_, presentation) => originalNotice,
);

Future<void> presentOffer(BuildContext context) => Restage.presentPlacement(
  context,
  builder: (_, presentation) => namedOffer,
);
''',
      'apps_examples|lib/restage.generated/native_flow.restage.g.dart':
          generated,
    });
    final output = File(nativeFlowFixturePath);
    // The fixture lives in a package on the short format style, so compare
    // content and ignore layout.
    if (Platform.environment['UPDATE_COMPILED_SURFACE_FIXTURE'] == '1') {
      output.writeAsStringSync(candidate.rendered);
    }
    String packed(String source) => source
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r',(?=[)\]}])'), '');
    expect(packed(generated), packed(output.readAsStringSync()));
    expect(generated, contains('class NativeWelcomeFlowSurface'));
    expect(generated, contains('NativeWelcome.new'));
    expect(generated, contains('NativeOffer.new'));
    expect(generated, contains('class NativeNoticeSurface'));
  });

  test(
    'generates a typed paywall mount with its authored constructor',
    () async {
      const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
part 'restage.generated/offer.restage.g.dart';

@Paywall(id: 'upgrade_offer')
final class UpgradeOffer extends StatelessWidget {
  const UpgradeOffer(this.title, {
    super.key,
    this.subtitle = 'Try it',
    this.onUnavailable = 'Try again',
    this.unavailable = false,
  });
  final String title;
  final String subtitle;
  final String onUnavailable;
  final bool unavailable;
  @override
  Widget build(BuildContext context) => Text(title);
}
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        const {'apps_examples|lib/offer.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final bundle = _readBundle(readerWriter);
      expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
      final generated = utf8.decode(
        bundle.ownedOutputs['lib/restage.generated/offer.restage.g.dart']!,
      );
      expect(generated, contains('class UpgradeOfferSurface'));
      expect(generated, contains("id: 'upgrade_offer'"));
      expect(generated, matches(RegExp(r'_restageDesign\(\s*UpgradeOffer\(')));
      await _expectAnalyzesClean({
        'apps_examples|lib/offer.dart':
            '''
$source
const defaultOffer = UpgradeOfferSurface('Offer');
const customOffer = UpgradeOfferSurface(
  'Offer', onUnavailable: 'Retry', unavailable: true,
);
''',
        'apps_examples|lib/restage.generated/offer.restage.g.dart': generated,
      });
    },
  );

  test('a paywall publishes what its mount passes as host data', () async {
    const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
part 'restage.generated/offer.restage.g.dart';

@Paywall(id: 'upgrade_offer')
final class UpgradeOffer extends StatelessWidget {
  const UpgradeOffer({super.key, required this.price});
  final String price;
  @override
  Widget build(BuildContext context) =>
      Text(price, style: TextStyle(color: Theme.of(context).primaryColor));
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const {'apps_examples|lib/offer.dart': source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
    final publication = bundle.manifest!.publications.single.publication;
    final contract = publication.hostDataContract;
    expect(contract, isNotNull);
    expect(contract!.inputs.keys, contains('price'));
    // The hoisted theme color is a value only the app can compute.
    expect(
      contract.inputs.keys.where((key) => key.startsWith('_h')),
      hasLength(1),
    );
    expect(publication.hostDataContractHash, isNotNull);
  });

  test(
    'a helper the app renders is measured as the widget it builds',
    () async {
      const source = """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
part 'restage.generated/mounted.restage.g.dart';

Widget card(bool on) {
  if (on) return const Text('on');
  return const Text('off');
}

class Wrapper extends StatelessWidget {
  const Wrapper({super.key, this.on = false});
  final bool on;
  @override
  Widget build(BuildContext context) => Column(children: [card(on)]);
}

@Paywall(id: 'mounted')
final class Mounted extends StatelessWidget {
  const Mounted({super.key, this.flag = false});
  final bool flag;
  @override
  Widget build(BuildContext context) =>
      Column(children: [card(flag), Wrapper(on: flag)]);
}
""";
      final warnings = <String>[];
      final part = await _generatedPart(
        source,
        'mounted',
        warned: warnings.addAll,
      );
      expect(part, contains(r'_restageIsland$mounted_card_0'));
      expect(
        warnings.join('\n'),
        isNot(contains('Measurement is unavailable')),
      );
    },
  );

  test('S10 a build local named context is a mount local', () async {
    const source = """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
part 'restage.generated/mounted.restage.g.dart';

class Tinted extends StatelessWidget {
  const Tinted({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: const Color(0xFF000000), child: child);
}

@Paywall(id: 'mounted')
final class Mounted extends StatelessWidget {
  const Mounted({super.key, this.title, this.flag = false});
  final String? title;
  final bool flag;
  @override
  Widget build(BuildContext buildContext) {
    final context = title ?? 'x';
    if (flag) {
      return Tinted(child: Text(context));
    }
    return const Text('none');
  }
}
""";
    final part = await _generatedPart(source, 'mounted', warningFree: true);
    final flat = part.replaceAll(RegExp(r'\s+'), ' ');
    // The app's own local is declared and read where the app writes it.
    expect(flat, contains("final context = _restageArgument1 ?? 'x';"));
    expect(flat, isNot(contains('_restageLocal_')));
  });

  test(
    'a loop that steps its own index compiles and runs as the app does',
    () async {
      const source = """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
part 'restage.generated/probed.restage.g.dart';

class Offer {
  const Offer(this.title);
  final String title;
}

@Paywall(id: 'probed')
final class Probed extends StatelessWidget {
  const Probed({super.key, this.offers = const []});
  final List<Offer> offers;
  @override
  Widget build(BuildContext context) {
    for (var i = 0; i < offers.length; i++) {
      final o = offers[i];
      if (o.title.isNotEmpty) return Text(o.title);
      i++;
    }
    return const Text('none');
  }
}
""";
      final part = await _generatedPart(source, 'probed', warningFree: true);
      final flat = part.replaceAll(RegExp(r'\s+'), ' ');
      // The copy runs the loop as written: it steps `i` itself, records the
      // item's title and the branch the build takes.
      expect(
        flat,
        contains(
          'for (var i = 0; i < _restageArgument1.length; i++) { '
          'final o = _restageArgument1[i]; '
          'if (o.title.isNotEmpty) return _restageDesign( '
          "_restageRecording.branch( '_h34a704d316', 0, "
          "Text(_restageRecording.value('_hd048281828', o.title)), ), ); "
          'i++; }',
        ),
      );
      expect(
        flat,
        contains(
          "_restageRecording.branch('_h34a704d316', 1, const Text('none'))",
        ),
      );
    },
  );

  for (final (id, declarations, body, name, place) in [
    (
      'C1 an app function named with the reserved prefix',
      "String _restageLocal_headline() => 'app';",
      "if (flag) {\n      final headline = 'block';\n      return Text(headline);\n    }\n    return Text(_restageLocal_headline());",
      '_restageLocal_headline',
      'lib/probed.dart:17:17',
    ),
    (
      'C5 an app final named with the reserved prefix',
      "final _restageLocal_label2 = 'app2';",
      "if (flag) {\n      final label = 'one';\n      return Text(label);\n    }\n    return Text(_restageLocal_label2);",
      '_restageLocal_label2',
      'lib/probed.dart:17:17',
    ),
    (
      'C6 a local named with the reserved prefix',
      '',
      "final _restageCount = flag ? 1 : 2;\n    return Text('\$_restageCount');",
      '_restageCount',
      'lib/probed.dart:13:11',
    ),
  ]) {
    test(id, () async {
      final source =
          """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
part 'restage.generated/probed.restage.g.dart';

$declarations

@Paywall(id: 'probed')
final class Probed extends StatelessWidget {
  const Probed({super.key, this.flag = false});
  final bool flag;
  @override
  Widget build(BuildContext context) {
    $body
  }
}
""";
      await _generatedPart(
        source,
        'probed',
        refused: (errors) {
          expect(errors.map(_issueMessage), [
            '`$name` ($place): Restage reserves names that start with '
                "`_restage` for the code it generates. Try a name that doesn't "
                'start with `_restage`.',
          ]);
        },
      );
    });
  }

  test('a build switch that throws over null quotes it readably', () async {
    const source = """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
part 'restage.generated/mounted.restage.g.dart';

@Paywall(id: 'mounted')
final class Mounted extends StatelessWidget {
  const Mounted({super.key, this.title});
  final String? title;
  @override
  Widget build(BuildContext context) {
    switch (title) {
      case null:
        throw StateError('none');
      default:
        return Text(title!);
    }
  }
}
""";
    await _generatedPart(
      source,
      'mounted',
      refused: (errors) {
        expect(errors.map(_issueMessage), [
          startsWith("`switch (title) {case null: throw StateError('none'); "),
        ]);
      },
    );
  });

  test('a build switch with one returning case names the statement', () async {
    const source = """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
part 'restage.generated/mounted.restage.g.dart';

@Paywall(id: 'mounted')
final class Mounted extends StatelessWidget {
  const Mounted({super.key, this.flag = false});
  final bool flag;
  @override
  Widget build(BuildContext context) {
    switch (flag) {
      case true:
        return const Text('on');
      case false:
        throw StateError('off');
    }
  }
}
""";
    await _generatedPart(
      source,
      'mounted',
      refused: (errors) {
        expect(errors.map(_issueMessage), [
          "`switch (flag) {case true: return const Text('on'); case fal…` "
              "(lib/mounted.dart:11:5): Restage can't translate this statement "
              'in a build method. Try using a `switch` or `?:` expression in '
              'the returned widget, or moving the code into a widget of its '
              'own.',
        ]);
      },
    );
  });

  test(
    'an onboarding screen keeps a constant ValueKey on its widget',
    () async {
      const source = """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
part 'restage.generated/get_started.restage.g.dart';

@Screen(id: 'get_started', surface: Surface.onboarding)
final class GetStarted extends StatelessWidget {
  const GetStarted({super.key, required this.title});
  static const continueEvent = SurfaceEvent<String>('continue');
  final String title;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        key: const ValueKey('get-started-action'),
        onPressed: surfaceEvent(continueEvent, 'preview'),
        child: const Text('Get started'),
      ),
    );
  }
}
""";
      String? design;
      final generated = await _generatedPart(
        source,
        'get_started',
        warningFree: true,
        handoff: (bundle) => design = fmt
            .decodeLibraryBlob(
              Uint8List.fromList(
                bundle.artifacts['assets/onboarding/screens/get_started.rfw']!,
              ),
            )
            .toString(),
      );
      final key = RegExp(
        r'key: data\.context\.(_h[0-9a-f]+)',
      ).firstMatch(design!)?.group(1);
      expect(key, isNotNull, reason: design);
      final flat = generated.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        flat,
        contains(
          "_restageRecording.native( '$key', "
          "const ValueKey('get-started-action'), type: 'flutter.Key', "
          'nullable: false, )',
        ),
      );
      expect(
        flat,
        contains(
          '"$key":{"kind":"nativeBinding","contract":'
          '{"type":"flutter.Key","nullable":false}',
        ),
      );
    },
  );

  test('an onboarding screen splits like a paywall', () async {
    const source = """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
part 'restage.generated/welcome.restage.g.dart';

class Tinted extends StatelessWidget {
  const Tinted({super.key, required this.child, this.tint = 0});
  final Widget child;
  final int tint;
  @override
  Widget build(BuildContext context) => ColoredBox(color: Color(0xFF000000 + tint), child: child);
}

@Screen(id: 'welcome', surface: Surface.onboarding)
final class Welcome extends StatefulWidget {
  const Welcome({super.key, required this.title});
  final String title;
  @override
  State<Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<Welcome> {
  final ScrollController _scroll = ScrollController();
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(widget.title),
        Tinted(tint: 2, child: const Text('slot')),
        SizedBox(
          height: 40,
          child: ListView(controller: _scroll, children: const [Text('a')]),
        ),
      ]);
}
""";
    final generated = await _generatedPart(source, 'welcome');
    final flat = generated.replaceAll(RegExp(r'\s+'), ' ');
    expect(flat, contains('class _WelcomeSurfaceState'));
    expect(flat, contains('child: RestageScreen<'));
    expect(flat, contains("WidgetLibrary.custom('apps_examples.islands')"));
    expect(flat, contains(r'Widget _restageIsland$welcome_Tinted_0('));
    expect(flat, contains('return RestageIslandScope('));
    expect(
      flat,
      contains(
        "controller: _restageRecording.native( '_h8604b300d0', "
        "_scroll, type: 'flutter.ScrollController', nullable: false, )",
      ),
    );
  });

  test(
    'borrows constructor native scalers through the typed binding scope',
    () async {
      const source = """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
part 'restage.generated/welcome.restage.g.dart';
@Screen(id: 'welcome', surface: Surface.onboarding)
final class Welcome extends StatelessWidget {
  const Welcome({super.key, required this.scaler});
  final TextScaler? scaler;
  @override
  Widget build(BuildContext context) => Text('Hi', textScaler: scaler);
}
""";
      final generated = await _generatedPart(
        source,
        'welcome',
        expectedFloor: 24,
      );
      final flat = generated.replaceAll(RegExp(r'\s+'), ' ');
      expect(flat, contains('RestageNativeValues('));
      expect(flat, contains('bindings: _restageRecording.bindings('));
      expect(flat, contains('NativeBinding('));
      expect(flat, contains("type: 'flutter.TextScaler', nullable: true"));
      expect(flat, contains('"kind": "nativeBinding"'));
      expect(flat, isNot(contains('restageNativeObjects({')));
      await _expectAnalyzesClean({
        'apps_examples|lib/welcome.dart': source,
        'apps_examples|lib/restage.generated/welcome.restage.g.dart': generated,
      });
    },
  );

  test(
    'mounts exact native text scalers at the authored root context',
    () async {
      const source = """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
part 'restage.generated/welcome.restage.g.dart';
@Screen(id: 'welcome', surface: Surface.onboarding)
final class Welcome extends StatelessWidget {
  const Welcome({super.key});
  @override
  Widget build(BuildContext context) => Text('Hi', textScaler:
    MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.8));
}
""";
      final generated = await _generatedPart(source, 'welcome');
      final flat = generated.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        flat,
        contains(
          "textScaler: _restageRecording.scaler( '_h3a8adf83ba', "
          'MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.8), )',
        ),
      );
      expect(flat, contains('RestageNativeValues('));
      expect(flat, contains('textScalers: _restageRecording.scalers,'));
      expect(flat, contains('"kind": "native"'));
      expect(flat, isNot(contains('textScaleFactor:')));
    },
  );

  test('mounts native scalers through a root-context helper alias', () async {
    const source = """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
part 'restage.generated/welcome.restage.g.dart';
TextScaler scalerFor(BuildContext root) => MediaQuery.textScalerOf(root);
@Screen(id: 'welcome', surface: Surface.onboarding)
final class Welcome extends StatelessWidget {
  const Welcome({super.key});
  @override
  Widget build(BuildContext context) {
    final root = context;
    return Text('Hi', softWrap: !MediaQuery.boldTextOf(root), textScaler: scalerFor(root));
  }
}
""";
    final generated = await _generatedPart(source, 'welcome');
    final flat = generated.replaceAll(RegExp(r'\s+'), ' ');
    expect(
      flat,
      contains(
        "textScaler: _restageRecording.scaler('_hfc4bc5d087', scalerFor(root))",
      ),
    );
    expect(flat, contains('final root = context;'));
    expect(flat, contains('!MediaQuery.boldTextOf(root)'));
    expect(flat, contains('RestageNativeValues('));
  });

  test('computes app-only values in the generated mount', () async {
    const source = """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome.restage.g.dart';

class Palette extends InheritedWidget {
  const Palette({super.key, required super.child, required this.ink});
  final Color ink;
  static Palette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Palette>()!;
  @override
  bool updateShouldNotify(Palette old) => ink != old.ink;
}

abstract final class Styles {
  static final TextStyle title = TextStyle(fontSize: 28);
}

@Screen(id: 'welcome', surface: Surface.onboarding)
final class Welcome extends StatelessWidget {
  const Welcome({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context) {
    final ink = Palette.of(context).ink;
    return ColoredBox(
      color: ink,
      child: Text(name, style: Styles.title.copyWith(color: ink)),
    );
  }
}
""";
    final generated = await _generatedPart(source, 'welcome');
    final flat = generated.replaceAll(RegExp(r'\s+'), ' ');
    // The build's prelude runs once in the mount; values read it by name.
    expect(flat, contains('final ink = Palette.of(context).ink;'));
    expect('Palette.of('.allMatches(flat), hasLength(1));
    expect(
      flat,
      contains(
        "color: _restageRecording.native( '_h311660936e', ink, "
        "type: 'flutter.Color', nullable: false, )",
      ),
    );
    expect(
      flat,
      contains(
        "style: _restageRecording.value( '_ha1c5544b55', "
        'Styles.title.copyWith(color: ink), )',
      ),
    );
    expect(flat, contains('Text( _restageArgument1,'));
    await _expectAnalyzesClean({
      'apps_examples|lib/welcome.dart': source,
      'apps_examples|lib/restage.generated/welcome.restage.g.dart': generated,
    });
  });

  test('a build local nothing reads still runs once in the mount', () async {
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/seen.restage.g.dart';

final class Store {
  int marks = 0;
  bool markSeen() => ++marks > 0;
}

final _store = Store();

@Paywall()
final class Seen extends StatelessWidget {
  const Seen({super.key});
  @override
  Widget build(BuildContext context) {
    final seen = _store.markSeen();
    return const Text('Hi');
  }
}
''';
    final generated = await _generatedPart(source, 'seen');
    expect(generated, contains('final seen = _store.markSeen();'));
  });

  test('a build local read by two values runs once in the mount', () async {
    const source = r'''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/route.restage.g.dart';

@Paywall()
final class Route extends StatelessWidget {
  const Route({super.key});
  @override
  Widget build(BuildContext context) {
    final route = Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const SizedBox()),
    );
    return Column(children: [Text('$route'), Text('at $route')]);
  }
}
''';
    final generated = await _generatedPart(source, 'route');
    expect('Navigator.push'.allMatches(generated), hasLength(1));
    expect(generated, contains(r"'$route'"));
    expect(generated, contains(r"'at $route'"));
  });

  for (final (where, body) in [
    (r"'$n'", r"Center(child: Text('$n'))"),
    (r"'${n + 1}'", r"Center(child: Text('${n + 1}'))"),
    (
      r"an action's '$n'",
      r"GestureDetector(onTap: () => mark('$n'), child: const Text('x'))",
    ),
  ]) {
    test('a build prelude read only in $where is declared', () async {
      final source =
          """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/count.restage.g.dart';

int _calls = 0;
int count() => ++_calls;
void mark(String value) {}

@Paywall()
final class Count extends StatelessWidget {
  const Count({super.key});
  @override
  Widget build(BuildContext context) {
    final n = count();
    return $body;
  }
}
""";
      // The part analyzes clean only when the local it reads is declared.
      final generated = await _generatedPart(source, 'count');
      expect(generated, contains('final n = count();'));
    });
  }

  test('a build prelude whose reads lower stays delivered', () async {
    const source = """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/shade.restage.g.dart';

final _held = GlobalKey();

@Paywall()
final class Shade extends StatelessWidget {
  const Shade({super.key});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      Container(color: dark ? Colors.black : Colors.white),
      KeyedSubtree(key: _held, child: const Text('held')),
    ]);
  }
}
""";
    late String text;
    final generated = await _generatedPart(
      source,
      'shade',
      paywallText: (payload) => text = payload,
    );
    expect(text, contains('switch data.theme.brightness'));
    // Only the compiled fallback reads the local; the app computes nothing.
    expect(generated, isNot(contains('() => dark')));
  });

  test('computes a per-item lookup for each host-supplied item', () async {
    const source = """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/garden.restage.g.dart';

class Labels {
  const Labels();
  static Labels of(BuildContext context) => const Labels();
  String labelFor(int tone) => tone.toString();
}

final class Plant {
  const Plant({required this.name, required this.tone});
  final String name;
  final int tone;
}

@Screen(id: 'garden', surface: Surface.onboarding)
final class Garden extends StatelessWidget {
  const Garden({super.key, required this.plants});
  final List<Plant> plants;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final plant in plants)
            Text(Labels.of(context).labelFor(plant.tone)),
        ],
      );
}
""";
    final generated = await _generatedPart(source, 'garden');
    final flat = generated.replaceAll(RegExp(r'\s+'), ' ');
    expect(
      flat,
      contains(
        "for (final plant in _restageRecording.items( 'plants', "
        '_restageArgument1, )) Text( _restageRecording.value( '
        "'_hb4c01f8328', Labels.of(context).labelFor(plant.tone), "
        "'plants', ), ),",
      ),
    );
    await _expectAnalyzesClean({
      'apps_examples|lib/garden.dart': source,
      'apps_examples|lib/restage.generated/garden.restage.g.dart': generated,
    });
  });

  test('binds a Color computed for each host-supplied item per item', () async {
    const source = """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/garden.restage.g.dart';

class Tones {
  const Tones();
  static Tones of(BuildContext context) => const Tones();
  Color colorFor(int tone) => Color(0xFF000000 + tone);
}

final class Plant {
  const Plant({required this.name, required this.tone});
  final String name;
  final int tone;
}

@Screen(id: 'garden', surface: Surface.onboarding)
final class Garden extends StatelessWidget {
  const Garden({super.key, required this.plants});
  final List<Plant> plants;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final plant in plants)
            ColoredBox(color: Tones.of(context).colorFor(plant.tone)),
        ],
      );
}
""";
    final generated = await _generatedPart(source, 'garden');
    final flat = generated.replaceAll(RegExp(r'\s+'), ' ');
    expect(
      flat,
      contains(
        "for (final plant in _restageRecording.items( 'plants', "
        '_restageArgument1, )) ColoredBox( color: '
        "_restageRecording.native( '_hdc89203caa', "
        "Tones.of(context).colorFor(plant.tone), items: 'plants', "
        "type: 'flutter.Color', nullable: false, ), ),",
      ),
    );
  });

  test('gives the same per-item expression over two lists two keys', () async {
    const source = r"""
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/plans.restage.g.dart';

final class Days {
  const Days();
  static Days of(BuildContext context) => const Days();
  String format(int day) => 'Day $day';
}

final class Entry {
  const Entry({required this.day});
  final int day;
}

@Screen(id: 'plans', surface: Surface.onboarding)
final class Plans extends StatelessWidget {
  const Plans({super.key, required this.habits, required this.goals});
  final List<Entry> habits;
  final List<Entry> goals;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final x in habits) Text(Days.of(context).format(x.day)),
          for (final x in goals) Text(Days.of(context).format(x.day)),
        ],
      );
}
""";
    final generated = await _generatedPart(source, 'plans');
    final keys =
        RegExp(r"_restageRecording\.value\(\s*'(_h[0-9a-f]{10})',\s*Days\.of")
            .allMatches(generated.replaceAll(RegExp(r'\s+'), ' '))
            .map((match) => match[1])
            .toList();
    expect(keys, hasLength(2));
    expect(keys.toSet(), hasLength(2));
  });

  test('computes a guarded lookup under a guard of its own', () async {
    const source = """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/offer_line.restage.g.dart';

final class Offer {
  const Offer(this.title);
  final String title;
}

final class Store {
  static final Store instance = Store();
  Offer? offer;
}

@Screen(id: 'offer_line', surface: Surface.onboarding)
final class OfferLine extends StatefulWidget {
  const OfferLine({super.key});

  static const toggle = SurfaceEvent<void>('toggle');

  @override
  State<OfferLine> createState() => _OfferLineState();
}

final class _OfferLineState extends State<OfferLine> {
  bool isPro = false;

  void _flip() => setState(() => isPro = !isPro);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: _flip,
        child: Text(isPro ? Store.instance.offer!.title : 'Free'),
      );
}
""";
    final generated = await _generatedPart(source, 'offer_line');
    final flat = generated.replaceAll(RegExp(r'\s+'), ' ');
    // The State moves into the mount, and the lookup runs where the app runs
    // it: only under its guard.
    _expectTemplate(
      flat,
      "_restageRecording.value( '<wireKey>', isPro ? Store.instance.offer!.title "
      ": 'Free', )",
    );
  });

  test('mirrors a build that receives a ref so ref reads move too', () async {
    const source = """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/greeting.restage.g.dart';

final class Provider<T> {
  const Provider(this.value);
  final T value;
}

abstract class WidgetRef {
  T watch<T>(Provider<T> provider);
}

final class _Ref implements WidgetRef {
  @override
  T watch<T>(Provider<T> provider) => provider.value;
}

abstract class ConsumerWidget extends StatefulWidget {
  const ConsumerWidget({super.key});
  Widget build(BuildContext context, WidgetRef ref);
  @override
  State<ConsumerWidget> createState() => _ConsumerState();
}

final class _ConsumerState extends State<ConsumerWidget> {
  @override
  Widget build(BuildContext context) => widget.build(context, _Ref());
}

const accent = Provider<Color>(Color(0xFF123456));

@Screen(id: 'greeting', surface: Surface.onboarding)
final class Greeting extends ConsumerWidget {
  const Greeting({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ColoredBox(color: ref.watch(accent));
}
""";
    final generated = await _generatedPart(source, 'greeting');
    final flat = generated.replaceAll(RegExp(r'\s+'), ' ');
    expect(
      flat,
      contains('final class GreetingSurface extends ConsumerWidget {'),
    );
    expect(
      flat,
      contains('Widget build(BuildContext context, WidgetRef ref) {'),
    );
    expect(
      flat,
      contains(
        "color: _restageRecording.native( '_haa781a94f1', "
        "ref.watch(accent), type: 'flutter.Color', nullable: false, )",
      ),
    );
    await _expectAnalyzesClean({
      'apps_examples|lib/greeting.dart': source,
      'apps_examples|lib/restage.generated/greeting.restage.g.dart': generated,
    });
  });

  for (final (name, field, body, need) in [
    (
      'an island',
      'final _scroll = ScrollController();',
      "CustomPaint(painter: null, child: const Text('slot'))",
      '`CustomPaint` in `Split` (lib/split.dart:11:7)',
    ),
    (
      'a widget holding a global key',
      'final _held = GlobalKey();',
      "Column(children: [const Text('Go'), "
          "KeyedSubtree(key: _held, child: const Text('held'))])",
      '`KeyedSubtree` in `Split` (lib/split.dart:11:43)',
    ),
  ]) {
    test('$name on a paywall without a part line is refused', () async {
      final source =
          '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

$field

@Paywall()
final class Split extends StatelessWidget {
  const Split({super.key});
  @override
  Widget build(BuildContext context) =>
      $body;
}
''';
      late List<String> errors;
      await _generatedPart(
        source,
        'split',
        expectPart: false,
        refused: (e) => errors = e,
      );
      expect(
        errors.map(_issueMessage),
        contains(
          '$need runs app code, which needs the generated '
          '`SplitSurface`, and lib/split.dart has no '
          "`part 'restage.generated/split.restage.g.dart';` line. Try "
          'adding that line to lib/split.dart.',
        ),
      );
    });
  }

  test('a deprecated screen source whose build needs a generated widget is '
      'refused', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
part 'restage.generated/welcome.restage.g.dart';

@ScreenSource(id: 'welcome', version: 1, minClient: 1)
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) =>
      const Text('Welcome', key: ValueKey('welcome'));
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilders(
      [
        onboardingScreenBuilder(BuilderOptions.empty),
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      ],
      const <String, String>{
        'apps_examples|lib/onboarding/screens/welcome.dart': screen,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.map(_issueMessage),
      contains(
        "`ValueKey('welcome')` "
        '(lib/onboarding/screens/welcome.dart:11:34): Restage keeps a '
        "widget's key only through the screen's generated widget, and this "
        'build doesn\'t use one. Try showing the screen through '
        '`WelcomeSurface`, or removing the key.',
      ),
      reason: result.errors.join('\n'),
    );
  });

  test("a paywall's generated definition names its generated widget", () async {
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/plain.restage.g.dart';

@Paywall()
final class Plain extends StatelessWidget {
  const Plain({super.key});
  @override
  Widget build(BuildContext context) => const Text('Plain');
}
''';
    final part = await _generatedPart(source, 'plain');
    expect(part, contains("surfaceWidget: 'PlainSurface',"));
  });

  test("a screen's generated definition names its generated widget", () async {
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/plain.restage.g.dart';

@Screen(id: 'plain', surface: Surface.onboarding)
final class Plain extends StatelessWidget {
  const Plain({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Text(title);
}
''';
    final part = await _generatedPart(source, 'plain', warningFree: true);
    expect(part, contains('RestageScreen.generatedPlacementDefinition('));
    expect(part, contains("surfaceWidget: 'PlainSurface',"));
  });

  test('a screen input its build never reads is not stored', () async {
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/toned.restage.g.dart';

enum Tone { calm, urgent }

@Screen(id: 'toned', surface: Surface.onboarding)
final class Toned extends StatelessWidget {
  const Toned({super.key, required this.title, this.tone = Tone.calm});
  final String title;
  final Tone tone;
  @override
  Widget build(BuildContext context) =>
      Text(title, key: const ValueKey('title'));
}
''';
    final part = await _generatedPart(source, 'toned', warningFree: true);
    expect(part, contains('Tone tone = '));
    expect(part, isNot(contains('_restageStored2')));
  });

  test('an island repeated by a delivered loop publishes and fits', () async {
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/plans.restage.g.dart';

class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child});
  final Widget child;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final _press = AnimationController(vsync: this);
  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _press, child: widget.child);
}

@Paywall()
final class Plans extends StatelessWidget {
  const Plans({super.key, required this.names});
  final List<String> names;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final name in names) Pressable(child: Text(name)),
      ]);
}
''';
    late RestageSurfacePublicationBundle bundle;
    final generated = await _generatedPart(
      source,
      'plans',
      handoff: (b) => bundle = b,
    );
    final publication = bundle.manifest!.publications.single.publication;
    final requirement = publication.fitRequirement!;
    final name = requirement.requiredIslands.keys.single;
    expect(requirement.islandLabels[name], 'Pressable in Plans');
    final entry = [
      for (final contract in publication.compiledScreenContracts.values)
        ...contract.catalog.widgets,
    ].firstWhere((widget) => widget.name == name.split(':').last);
    expect(entry.itemInputs, 1);
    // Its own build provides it.
    final host = _hostContractOf(generated, '');
    expect(host.islands, requirement.requiredIslands);
  });

  test(
    'an opt-out keeps a widget the design would deliver in the app',
    () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/kept.restage.g.dart';

@RenderInApp()
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Text(label);
}

@Paywall()
final class Kept extends StatelessWidget {
  const Kept({super.key});
  @override
  Widget build(BuildContext context) =>
      Column(children: [const Text('delivered'), Pill(label: 'kept')]);
}
''';
      late RestageSurfacePublicationBundle bundle;
      await _generatedPart(source, 'kept', handoff: (b) => bundle = b);
      expect(
        [
          for (final site in bundle.splitSites)
            if (site.kind.name == 'island') '${site.widget}: ${site.reason}',
        ],
        [
          "Pill: Designs can't change `Pill` (lib/kept.dart:19:50) because "
              '`@RenderInApp` is on `Pill`.',
        ],
      );
    },
  );

  test("a promoted island becomes a widget of the app's own", () async {
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/promo.restage.g.dart';

class Tinted extends StatelessWidget {
  const Tinted({super.key, required this.child, this.tint = 0});
  final Widget child;
  final int tint;
  @override
  Widget build(BuildContext context) => ColoredBox(color: Color(0xFF000000 + tint), child: child);
}

@Paywall()
final class Promo extends StatefulWidget {
  const Promo({super.key});
  @override
  State<Promo> createState() => _PromoState();
}

class _PromoState extends State<Promo> {
  final int _tint = 3;
  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('delivered'),
        Tinted(tint: _tint + 1, child: const Text('slot')),
      ]);
}
''';
    late RestageSurfacePublicationBundle bundle;
    await _generatedPart(source, 'promo', handoff: (b) => bundle = b);
    final island = bundle.splitSites.singleWhere(
      (site) => site.kind.name == 'island',
    );
    final plan = island.promotion!;
    expect(plan['call'], '{{name}}(tint: _tint, child: const Text(\'slot\'))');
    expect(
      plan['class'],
      [
        '/// The `Tinted` moved out of `_PromoState.build`. Describe what '
            'this widget shows.',
        '@RestageWidget()',
        'class {{name}} extends StatelessWidget {',
        '  const {{name}}({super.key, required this.tint, required this.child});',
        '  /// Describe `tint`.',
        '  final int tint;',
        '  /// Describe `child`.',
        '  final Widget child;',
        '',
        '  @override',
        '  Widget build(BuildContext context) => '
            'Tinted(tint: tint + 1, child: child);',
        '}',
      ].join('\n'),
    );
    // Applied and exported from a widget library, the code is a widget the
    // design delivers, and nothing renders from the app.
    final offset = plan['offset']! as int;
    final original = plan['original']! as String;
    expect(source.substring(offset, offset + original.length), original);
    String named(Object? text) =>
        (text! as String).replaceAll('{{name}}', 'PromoTint');
    final promoted =
        '${source.replaceRange(offset, offset + original.length, named(plan['call']))}'
        '\n${named(plan['class'])}\n';
    late RestageSurfacePublicationBundle after;
    String? text;
    await _generatedPart(
      promoted,
      'promo',
      otherFiles: {
        'apps_examples|lib/widgets.dart': '''
import 'package:restage/restage.dart';
export 'promo.dart' show PromoTint;
@RestageLibrary(library: WidgetLibrary.custom('promo.widgets'), capabilityVersion: 1)
const restageLibrary = 0;
''',
      },
      handoff: (b) => after = b,
      paywallText: (payload) => text = payload,
    );
    expect(
      [for (final site in after.splitSites) site.kind.name],
      isNot(contains('island')),
    );
    // The design passes its input, the value the app's build records, so a
    // new design can change it; the widget is placed by name, so its State
    // moves between the design and the app.
    expect(
      text,
      matches(
        RegExp(
          r'PromoTint\(tint: data\.context\._h[0-9a-f]+, '
          r'child: Text\(text: "slot"\), restageIsland: "promo_PromoTint_0"\)',
        ),
      ),
    );
  });

  test('islands render from the app through the generated part', () async {
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/split.restage.g.dart';

class Tinted extends StatelessWidget {
  const Tinted({super.key, required this.child, this.tint = 0});
  final Widget child;
  final int tint;
  @override
  Widget build(BuildContext context) => ColoredBox(color: Color(0xFF000000 + tint), child: child);
}

void buy() {}

@Paywall()
final class Split extends StatelessWidget {
  const Split({super.key});
  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('delivered'),
        Tinted(tint: 3, child: const Text('slot')),
        Tinted(tint: 3, child: const Text('slot')),
        GestureDetector(onTap: () => buy(), child: const Text('buy')),
      ]);
}
''';
    late RestageSurfacePublicationBundle bundle;
    late Catalog render;
    final generated = await _generatedPart(
      source,
      'split',
      handoff: (b) => bundle = b,
      renderCatalog: (c) => render = c,
    );
    // One app-wide library installs each mount's own registration, and the
    // previews build each island outside a mount; both analyze against the
    // generated part.
    final factories = emitEmptyUserFactoriesDart(
      dependencyFactories: islandRegistration(
        'apps_examples',
        bundle.splitSites,
        surfaceIslands: bundle.surfaceIslands,
      ),
    );
    // A surface's previews hold only its own islands.
    expect(
      factories.replaceAll(RegExp(r'\s+'), ''),
      contains(
        "'paywall/split':{'split_Tinted_0':island0.restagePreview"
        r"$split_Tinted_0,'split_Tinted_1':island0.restagePreview$"
        "split_Tinted_1},",
      ),
    );
    final flatFactories = factories.replaceAll(RegExp(r'\s+'), ' ');
    expect(
      flatFactories,
      contains(
        "Restage.registerWidgetLibrary( "
        "WidgetLibrary.custom('apps_examples.islands'), "
        r"widgets: [ ...island0.restageIslands$split_Tinted_0.widgets, ], );",
      ),
    );
    expect(
      flatFactories,
      contains("'split_Tinted_1': island0.restagePreview\$split_Tinted_1,"),
    );
    await _expectAnalyzesClean({
      'apps_examples|lib/user_factories.g.dart': factories,
      'apps_examples|lib/split.dart': source,
      'apps_examples|lib/restage.generated/split.restage.g.dart': generated,
    });
    // Fit asks the mount for each island by token, not for a library.
    final requirement =
        bundle.manifest!.publications.single.publication.fitRequirement!;
    expect(requirement.requiredIslands.keys, [
      'apps_examples.islands:split_Tinted_0',
      'apps_examples.islands:split_Tinted_1',
    ]);
    expect(requirement.capabilities.requiredLibraries, isEmpty);
    // Each island's published label has no position in it.
    expect(requirement.islandLabels.values, [
      'Tinted in Split',
      'Tinted in Split (2nd)',
    ]);
    // The render bundle's catalog carries the islands, with their tokens.
    expect(
      {
        for (final widget in render.widgets)
          if (widget.library.namespace == 'apps_examples.islands')
            'apps_examples.islands:${widget.name}': widget.wireId.value,
      },
      requirement.requiredIslands,
    );
    expect(
      [
        for (final site in bundle.splitSites)
          [
            site.name,
            site.widget,
            site.location,
            site.kind.name,
            if (site.widgets case final widgets?) widgets,
            if (site.reason != null) 'because',
          ].join(' '),
      ],
      [
        'SplitSurface Split lib/split.dart design 6',
        'apps_examples.islands:split_Tinted_0 Tinted lib/split.dart:22:9 '
            'island 1 because',
        'apps_examples.islands:split_Tinted_1 Tinted lib/split.dart:23:9 '
            'island 1 because',
        '_h19162a7a41 () => buy() lib/split.dart:24:32 action',
      ],
    );
    // The parts round-trip through the handoff.
    expect(
      RestageSurfacePublicationBundle.fromJson(
        jsonDecode(bundle.encodeCanonicalJson()),
      ).splitSites.map((site) => site.toJson()),
      bundle.splitSites.map((site) => site.toJson()),
    );
    final flat = generated.replaceAll(RegExp(r'\s+'), ' ');
    // The mount's host contract offers the same tokens.
    expect(
      flat,
      contains(
        "'islands': <String, Object?>{ "
        "'apps_examples.islands:split_Tinted_0': "
        "'${requirement.requiredIslands['apps_examples.islands:split_Tinted_0']}', ",
      ),
    );
    // The mount registers its own islands through a public constant, which
    // the package registration installs too.
    expect(
      flat,
      contains(
        r"const restageIslands$split_Tinted_0 = "
        "RestageWidgetLibraryRegistration.constant( "
        "library: WidgetLibrary.custom('apps_examples.islands'), "
        "widgets: [ RestageWidgetFactory( name: 'split_Tinted_0', "
        r"builder: _restageIsland$split_Tinted_0, ),",
      ),
    );
    // The registration says structurally that these are islands.
    expect(flat, contains('islands: true'));
    expect(flat, isNot(contains('capabilityVersion')));
    expect(
      flat,
      contains(
        r'Widget _restageIsland$split_Tinted_0(BuildContext context, '
        "DataSource source) => RestageIslandScope.build( 'split_Tinted_0', "
        "'`Tinted` (lib/split.dart:22:9) needs app code that only "
        "`SplitSurface` provides. Try using `SplitSurface` to build this "
        "screen.',",
      ),
    );
    expect(flat, contains(r'Widget restagePreview$split_Tinted_0('));
    // Each island registers under its own name, and the mount builds it from
    // what its build recorded.
    expect(
      flat,
      contains(
        "RestageWidgetFactory( name: 'split_Tinted_1', "
        r"builder: _restageIsland$split_Tinted_1, ),",
      ),
    );
    expect(
      flat,
      contains(
        "'split_Tinted_1': (_restageContext, _restageSource) => "
        "_restageRecording.islandAt( 'split_Tinted_1', [], "
        '_restageContext, _restageSource, ),',
      ),
    );
    expect(
      flat,
      contains(
        "_restageRecording.island( 'split_Tinted_1', "
        "_restageRecording.built( Tinted(tint: 3, child: const Text('slot')),",
      ),
    );
    expect(
      flat,
      contains(
        'RestageValueBinding.read<int>(restageSource, '
        "const <Object>[ 'tint', ], restageContext) ?? 3",
      ),
    );
  });

  group('a mounted paywall compiles and analyzes clean', () {
    const header = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/mounted.restage.g.dart';

class Tinted extends StatelessWidget {
  const Tinted({super.key, required this.child, this.tint = 0});
  final Widget child;
  final int tint;
  @override
  Widget build(BuildContext context) => ColoredBox(color: Color(0xFF000000 + tint), child: child);
}

class Tap extends StatelessWidget {
  const Tap({super.key, required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: null, child: GestureDetector(onTap: onTap, child: child));
}

void buy() {}
void at(double x) {}

class Plan {
  const Plan({required this.id, required this.rank});
  final String id;
  final int rank;
}
''';
    const stateful = '''
@Paywall()
final class Mounted extends StatefulWidget {
  const Mounted({super.key, required this.title});
  final String title;
  @override
  State<Mounted> createState() => _MountedState();
}
''';
    for (final (name, body, expected, text) in [
      (
        'an island in a loop reads the published index',
        '''
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans});
  final List<Plan> plans;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final plan in plans) Tinted(tint: plan.rank, child: Text(plan.id)),
      ]);
}
''',
        ['restageIndex0', 'restageSource.v<int>('],
        <String>[],
      ),
      (
        'an island in a loop that reads no item takes the loop position',
        '''
class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans});
  final List<Plan> plans;
  @override
  Widget build(BuildContext context) => Hears(
        onContext: (context) => Navigator.of(context).maybePop(),
        child: Column(children: [
          for (final plan in plans)
            Row(children: [
              Text(plan.id),
              Tinted(tint: 2, child: const Text('x')),
            ]),
        ]),
      );
}
''',
        [
          "for (final plan in _restageRecording.items( 'plans', _restageArgument1, null, ['<wireKey>'], )) Row( children: [ Text(plan.id), _restageRecording.island( 'mounted_Tinted_0', _restageRecording.built( Tinted(tint: 2, child: const Text('x')),",
        ],
        [
          'mounted_Tinted_0(tint: 2, child: Text(text: "x"), '
              'restageItems: [plan.',
        ],
      ),
      (
        "an island that maps a screen's list reads it in the mount",
        '''
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans});
  final List<Plan> plans;
  @override
  Widget build(BuildContext context) =>
      Column(children: plans.map((p) => Text(p.id)).toList());
}
''',
        <String>[],
        <String>[],
      ),
      (
        "an island argument that calls a method on a screen's field",
        '''
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans});
  final List<Plan> plans;
  @override
  Widget build(BuildContext context) => Column(children: [
        Tinted(
          tint: plans.indexWhere((p) => p.id == 'a'),
          child: const SizedBox(),
        ),
      ]);
}
''',
        <String>[],
        <String>[],
      ),
      (
        'the fallback keys an island read through a local in a loop',
        r'''
class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans});
  final List<Plan> plans;
  @override
  Widget build(BuildContext context) {
    final badge = Tinted(tint: 2, child: const Text('x'));
    return Hears(
      onContext: (context) => Navigator.of(context).maybePop(),
      child: Column(children: [
        for (final plan in plans) Row(children: [Text(plan.id), badge]),
      ]),
    );
  }
}
''',
        [
          "final badge = _restageRecording.built( Tinted(tint: 2, child: const Text('x')),",
          "Text(plan.id), _restageRecording.island( 'mounted_Tinted_0', badge, items: 'plans', ), ], ),",
        ],
        <String>[],
      ),
      (
        'a widget local placed twice is two islands',
        r'''
class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) {
    final card = Tinted(tint: 2, child: const Text('x'));
    return Hears(
      onContext: (context) => Navigator.of(context).maybePop(),
      child: Column(children: [card, card]),
    );
  }
}
''',
        [
          "final card = _restageRecording.built( Tinted(tint: 2, child: const Text('x')),",
          "_restageRecording.island('mounted_card0_Tinted_0', card), _restageRecording.island('mounted_card1_Tinted_0', card),",
        ],
        [
          'Column(children: [mounted_card0_Tinted_0(tint: 2, child: '
              'Text(text: "x")), mounted_card1_Tinted_0(',
        ],
      ),
      (
        'a widget local placed twice beside a for element',
        r'''
class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans});
  final List<Plan> plans;
  @override
  Widget build(BuildContext context) {
    final card = Tinted(tint: 2, child: const Text('x'));
    return Hears(
      onContext: (context) => Navigator.of(context).maybePop(),
      child: Column(children: [card, card, for (final p in plans) Text(p.id)]),
    );
  }
}
''',
        [
          "final card = _restageRecording.built( Tinted(tint: 2, child: const Text('x')),",
          "_restageRecording.island('mounted_card0_Tinted_0', card), _restageRecording.island('mounted_card1_Tinted_0', card), for (final p in _restageArgument1) Text(p.id),",
        ],
        [
          'Column(children: [mounted_card0_Tinted_0(tint: 2, child: '
              'Text(text: "x")), mounted_card1_Tinted_0(',
        ],
      ),
      (
        'a widget local placed again under an if element',
        r'''
class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans});
  final List<Plan> plans;
  @override
  Widget build(BuildContext context) {
    final card = Tinted(tint: 2, child: const Text('x'));
    return Hears(
      onContext: (context) => Navigator.of(context).maybePop(),
      child: Column(children: [card, if (plans.isEmpty) card]),
    );
  }
}
''',
        [
          "final card = _restageRecording.built( Tinted(tint: 2, child: const Text('x')),",
          "_restageRecording.island('mounted_card0_Tinted_0', card), if (_restageArgument1.isEmpty) ..._restageRecording.mark('<wireKey>', true, [ _restageRecording.island('mounted_card1_Tinted_0', card), ])",
        ],
        ['mounted_card0_Tinted_0(', 'mounted_card1_Tinted_0('],
      ),
      (
        'the fallback keys a looped local beside a for element',
        r'''
class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans});
  final List<Plan> plans;
  @override
  Widget build(BuildContext context) {
    final row = Row(children: [
      for (final p in plans) Tinted(tint: p.rank, child: Text(p.id)),
    ]);
    return Hears(
      onContext: (context) => Navigator.of(context).maybePop(),
      child: Column(children: [row, for (final q in plans) Text(q.id)]),
    );
  }
}
''',
        [
          "final row = Row( children: [ for (final p in _restageRecording.items( 'plans', _restageArgument1, null, ['<wireKey>'], )) _restageRecording.island( 'mounted_Tinted_0', _restageRecording.built( Tinted(tint: p.rank, child: Text(p.id)),",
          // Placed once through `row`, it is keyed where it is built.
          "items: 'plans', ), ], );",
          'Column( children: [row, for (final q in _restageArgument1) Text(q.id)],',
        ],
        <String>[],
      ),
      (
        'the fallback keys a local read outside and inside a loop',
        r'''
class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans});
  final List<Plan> plans;
  @override
  Widget build(BuildContext context) {
    final card = Tinted(tint: 2, child: const Text('x'));
    return Hears(
      onContext: (context) => Navigator.of(context).maybePop(),
      child: Column(children: [
        card,
        for (final p in plans) Row(children: [Text(p.id), card]),
      ]),
    );
  }
}
''',
        [
          "final card = _restageRecording.built( Tinted(tint: 2, child: const Text('x')),",
          "_restageRecording.island('mounted_card0_Tinted_0', card), for (final p in _restageRecording.items( 'plans', _restageArgument1, null, ['<wireKey>'], )) Row( children: [ Text(p.id), _restageRecording.island( 'mounted_card1_Tinted_0', card, items: 'plans', ), ], ),",
        ],
        <String>[],
      ),
      (
        'a widget local in exclusive branches is one island',
        r'''
class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans, this.flag = false});
  final List<Plan> plans;
  final bool flag;
  @override
  Widget build(BuildContext context) {
    final card = Tinted(tint: 2, child: const Text('x'));
    return Hears(
      onContext: (context) => Navigator.of(context).maybePop(),
      child: flag
          ? Column(children: [card])
          : Column(children: [card, const Text('y')]),
    );
  }
}
''',
        [
          "final card = _restageRecording.built( Tinted(tint: 2, child: const Text('x')),",
          "_restageArgument2 ? _restageRecording.taken( '<wireKey>', true, Column( children: [ _restageRecording.island('mounted_Tinted_0', card), ], ), ) : _restageRecording.taken( '<wireKey>', false, Column( children: [ _restageRecording.island('mounted_Tinted_0', card), const Text('y'), ], ), )",
        ],
        [
          'true: Column(children: [mounted_Tinted_0(',
          'false: Column(children: [mounted_Tinted_0(',
        ],
      ),
      (
        'a widget local beside itself in one branch only',
        r'''
class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans, this.flag = false});
  final List<Plan> plans;
  final bool flag;
  @override
  Widget build(BuildContext context) {
    final card = Tinted(tint: 2, child: const Text('x'));
    return Hears(
      onContext: (context) => Navigator.of(context).maybePop(),
      child: flag
          ? Column(children: [card])
          : Column(children: [card, card]),
    );
  }
}
''',
        <String>[],
        [
          'true: Column(children: [mounted_card0_Tinted_0(',
          'false: Column(children: [mounted_card0_Tinted_0(tint: 2, child: '
              'Text(text: "x")), mounted_card1_Tinted_0(',
        ],
      ),
      (
        'a helper parameter placed twice is two islands',
        r'''
class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

Widget _twice(Widget w) => Row(children: [w, w]);

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans, this.flag = false});
  final List<Plan> plans;
  final bool flag;
  @override
  Widget build(BuildContext context) {
    
    return Hears(
      onContext: (context) => Navigator.of(context).maybePop(),
      child: _twice(Tinted(tint: 2, child: const Text('x'))),
    );
  }
}
''',
        <String>[],
        [
          'Row(children: [mounted__twice0_w0_Tinted_0(tint: 2, child: '
              'Text(text: "x")), mounted__twice0_w1_Tinted_0(',
        ],
      ),
      (
        'a const widget local placed twice is two islands',
        r'''
class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans, this.flag = false});
  final List<Plan> plans;
  final bool flag;
  @override
  Widget build(BuildContext context) {
    const card = Tinted(tint: 2, child: SizedBox());
    return Hears(
      onContext: (context) => Navigator.of(context).maybePop(),
      child: Column(children: [card, card]),
    );
  }
}
''',
        <String>[],
        [
          'Column(children: [mounted_card0_Tinted_0(tint: 2, child: '
              'SizedBox()), mounted_card1_Tinted_0(',
        ],
      ),
      (
        'a list local spread twice is two islands each',
        r'''
class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans, this.flag = false});
  final List<Plan> plans;
  final bool flag;
  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[Tinted(tint: 2, child: const SizedBox())];
    return Hears(
      onContext: (context) => Navigator.of(context).maybePop(),
      child: Column(children: [...cards, ...cards]),
    );
  }
}
''',
        // Each spread marks its widgets as its own placement, which keys the
        // island the design places there.
        [
          '..._restageRecording.spotEach(0, cards)',
          '..._restageRecording.spotEach(1, cards)',
          'spots: [0]',
          'spots: [1]',
        ],
        [
          'Column(children: [mounted_cards0_Tinted_0(tint: 2, child: '
              'SizedBox()), mounted_cards1_Tinted_0(',
        ],
      ),
      (
        'a helper called twice beside an if element is two islands',
        r'''
class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

Widget card(int tint) => Tinted(tint: tint, child: const Text('x'));

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans, this.flag = false});
  final List<Plan> plans;
  final bool flag;
  @override
  Widget build(BuildContext context) {
    
    return Hears(
      onContext: (context) => Navigator.of(context).maybePop(),
      child: Column(children: [card(2), if (flag) card(2)]),
    );
  }
}
''',
        <String>[],
        [
          'Column(children: [mounted_card0_Tinted_0(child: Text(text: "x")), ',
          'mounted_card1_Tinted_0(child: Text(text: "x"))',
        ],
      ),
      (
        'the fallback keys an island in nested loops by both positions',
        r'''
class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans});
  final List<Plan> plans;
  @override
  Widget build(BuildContext context) => Hears(
        onContext: (context) => Navigator.of(context).maybePop(),
        child: Column(children: [
          for (final plan in plans)
            for (final unit in plan.id.codeUnits)
              Tinted(tint: plan.rank, child: Text('$unit')),
        ]),
      );
}
''',
        [
          "for (final plan in _restageRecording.items( 'plans', _restageArgument1, null, ['<wireKey>'], )) for (final unit in _restageRecording.items( '<wireKey>', plan.id.codeUnits, 'plans', ['<wireKey>'], )) _restageRecording.island( 'mounted_Tinted_0', _restageRecording.built( Tinted( tint: plan.rank,",
          "items: '<wireKey>', ),",
        ],
        <String>[],
      ),
      (
        'an island in a nested loop reading the outer item takes both positions',
        r'''
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans});
  final List<Plan> plans;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final plan in plans)
          for (final unit in plan.id.codeUnits)
            Tinted(tint: plan.rank, child: Text('$unit')),
      ]);
}
''',
        <String>[],
        ['restageItems: [plan.', ', unit.'],
      ),
      (
        'a const island with a delivered child drops its const',
        r'''
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) => Column(children: [const Text('a'), const Tinted(child: SizedBox())]);
}
''',
        [
          "const Text('a'), _restageRecording.island( 'mounted_Tinted_0', _restageRecording.built( const Tinted(child: SizedBox()), (_restageContext, _restageSource) => Tinted(child: _restageSource.child(",
        ],
        <String>[],
      ),
      (
        'a const island with a literal property drops its const',
        r'''
class Swatch extends StatelessWidget {
  const Swatch({super.key, this.tint = 0});
  final int tint;
  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Color(0xFF000000 + tint), child: const SizedBox());
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) => Column(children: [const Text('a'), const Swatch(tint: 3)]);
}
''',
        [
          "_restageRecording.island( 'mounted_Swatch_0', _restageRecording.built( const Swatch(tint: 3), (_restageContext, _restageSource) => Swatch(",
        ],
        <String>[],
      ),
      (
        'a wrapper the mount keeps under a const parent drops the const',
        r'''
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) => Center(child: const Tinted(child: Text('x')));
}
''',
        [
          "return (() => Center(child: Tinted(child: _restageDesign(Text('x')))))();",
        ],
        <String>[],
      ),
      (
        'a const island in a loop drops its const',
        r'''
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans});
  final List<Plan> plans;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final plan in plans)
          Row(children: [Text(plan.id), const Tinted(child: SizedBox())]),
      ]);
}
''',
        [
          "Text(plan.id), _restageRecording.island( 'mounted_Tinted_0', _restageRecording.built( const Tinted(child: SizedBox()), (_restageContext, _restageSource) => Tinted( child:",
        ],
        <String>[],
      ),
      (
        'a lifted State reads host data through the widget',
        '''
$stateful
class _MountedState extends State<Mounted> {
  final ScrollController _scroll = ScrollController();
  @override
  Widget build(BuildContext context) =>
      ListView(controller: _scroll, children: [Text(widget.title)]);
}
''',
        [
          "Text( _restageRecording.value('<wireKey>', widget._restageArgument1), )",
        ],
        <String>[],
      ),
      (
        'a lifted State keeps its mixins and interfaces',
        '''
$stateful
class _MountedState extends State<Mounted>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _spin = AnimationController(vsync: this);
  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) =>
      RotationTransition(turns: _spin, child: Text(widget.title));
}
''',
        ['with SingleTickerProviderStateMixin, WidgetsBindingObserver'],
        <String>[],
      ),
      (
        'callbacks the app renders stay unmeasured',
        '''
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) => Tap(
        onTap: () => buy(),
        child: Column(children: [
          GestureDetector(
            onTap: () => buy(),
            onTapDown: (details) => at(details.localPosition.dx),
            child: const Text('buy'),
          ),
          GestureDetector(onTap: () => buy(), child: const Text('measured')),
        ]),
      );
}
''',
        [
          "GestureDetector( onTap: () => buy(), onTapDown: _restageRecording.native( '<wireKey>', (details) => at(details.localPosition.dx), type: '(package:flutter/src/gestures/tap.dart#TapDownDetails)->void', nullable: false, ), child: const Text('buy'), )",
        ],
        [kMeasurementPublicationTapEventNameV1],
      ),
      (
        'a helper gives each call site and surface its own island',
        '''
Widget card(String label) => Tinted(tint: label.length, child: Text(label));

@Paywall(id: 'mounted')
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) =>
      Column(children: [card('monthly'), card('yearly')]);
}

@Paywall(id: 'other')
final class Other extends StatelessWidget {
  const Other({super.key});
  @override
  Widget build(BuildContext context) => Column(children: [card('monthly')]);
}
''',
        [
          // Each call site is the same form, whichever comes first.
          for (final (index, label) in ['monthly', 'yearly'].indexed)
            "((String label) => _restageRecording.island( 'mounted_card${index}_Tinted_0', _restageRecording.built( Tinted(tint: label.length, child: Text(label)), (_restageContext, _restageSource) => Tinted( tint: label.length, child: _restageSource.child(const <Object>['child']), ), ), ))('$label'),",
          r'builder: _restageIsland$mounted_card1_Tinted_0,',
          r'builder: _restageIsland$other_card0_Tinted_0,',
        ],
        [
          'mounted_card0_Tinted_0(child: Text(text: "monthly"))',
          'mounted_card1_Tinted_0(child: Text(text: "yearly"))',
        ],
      ),
      (
        'islands over different lists or literals do not share a builder',
        '''
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.monthly, required this.yearly});
  final List<Plan> monthly;
  final List<Plan> yearly;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final p in monthly) Tinted(tint: p.rank, child: Text(p.id)),
        for (final p in yearly) Tinted(tint: p.rank, child: Text(p.id)),
        Tinted(tint: 2, child: const Text('two')),
        Tinted(tint: 5, child: const Text('five')),
      ]);
}
''',
        [
          "_restageRecording.island( 'mounted_Tinted_0', _restageRecording.built( Tinted(tint: p.rank, child: Text(p.id)),",
          "items: 'monthly', ),",
          "_restageRecording.island( 'mounted_Tinted_1', _restageRecording.built( Tinted(tint: p.rank, child: Text(p.id)),",
          "items: 'yearly', ),",
          "_restageRecording.island( 'mounted_Tinted_2', _restageRecording.built( Tinted(tint: 2, child: const Text('two')),",
          "_restageRecording.island( 'mounted_Tinted_3', _restageRecording.built( Tinted(tint: 5, child: const Text('five')),",
          r'builder: _restageIsland$mounted_Tinted_3,',
        ],
        <String>[],
      ),
      // Each call's verdict is its own, whichever order the calls take.
      for (final (calls, payload) in [
        (
          "t(ObjectKey(1)), t(const ValueKey('a'))",
          'Column(children: [mounted_t0_Text_0(), '
              'Text(text: "x", key: data.context._h',
        ),
        (
          "t(const ValueKey('a')), t(ObjectKey(1))",
          'Column(children: [Text(text: "x", key: data.context._h',
        ),
      ])
        (
          'helper calls keep their own verdicts: $calls',
          '''
Widget t(Key k) => Text('x', key: k);

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) => Column(children: [$calls]);
}
''',
          <String>[],
          [payload],
        ),
      (
        'islands are numbered in the order the surface uses them',
        '''
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) {
    final first = Tinted(tint: 1, child: const Text('a'));
    final second = Tinted(tint: 2, child: const Text('b'));
    return Column(children: [second, first]);
  }
}
''',
        <String>[],
        [
          'Column(children: [mounted_Tinted_0(tint: 2, '
              'child: Text(text: "b")), mounted_Tinted_1(tint: 1, '
              'child: Text(text: "a"))])',
        ],
      ),
      (
        'a design copy keeps the reads its guards promote',
        '''
$stateful
class _MountedState extends State<Mounted> {
  final ScrollController _scroll = ScrollController();
  final String? _label = 'x';
  @override
  Widget build(BuildContext context) => ListView(controller: _scroll, children: [
        if (_label != null) Tinted(tint: _label.length, child: Text(_label)),
      ]);
}
''',
        ['class _MountedSurfaceState'],
        <String>[],
      ),
      (
        'a measured tap in a loop over a published list keeps its route',
        '''
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.names});
  final List<String> names;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final name in names)
          GestureDetector(
            onTap: () => buy(),
            child: Tinted(tint: name.length, child: Text(name)),
          ),
      ]);
}
''',
        [
          "for (final name in _restageRecording.items( '<wireKey>', _restageArgument1, null, ['<wireKey>'], )) GestureDetector( onTap: () => buy(), child: _restageRecording.island( 'mounted_Tinted_0', _restageRecording.built( Tinted( tint: name.length, child: Text( _restageRecording.value( '<wireKey>', name, '<wireKey>', ), ), ),",
          "items: '<wireKey>', ), ),",
        ],
        [kMeasurementPublicationTapEventNameV1],
      ),
      (
        'an island property named source reads the payload in its own context',
        '''
class Thumbnail extends StatelessWidget {
  const Thumbnail({super.key, required this.source, required this.child});
  final String source;
  final Widget child;
  @override
  Widget build(BuildContext context) => CustomPaint(painter: null, child: child);
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) => Column(children: [
        Thumbnail(source: 'hero.png', child: const Text('a')),
      ]);
}
''',
        [
          "RestageDecoders.string(restageSource, const <Object>[ 'source', ], "
              "context: restageContext) ?? 'hero.png'",
        ],
        <String>[],
      ),
      (
        'root sheets that cannot lower run as actions',
        '''
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) => Column(children: [
        TextButton(
          onPressed: () => showModalBottomSheet<void>(
              context: context, builder: (_) => const Text('first')),
          child: const Text('a'),
        ),
        TextButton(
          onPressed: () => showModalBottomSheet<void>(
              context: context, builder: (_) => const Text('second')),
          child: const Text('b'),
        ),
      ]);
}
''',
        ['showModalBottomSheet<void>('],
        ['TextButton(onPressed: {nativeEvent: data.context._h'],
      ),
      (
        'a per-item action fits its list item',
        '''
void pick(String id) {}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans});
  final List<Plan> plans;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final p in plans)
          GestureDetector(onTap: () => pick(p.id), child: Text(p.id)),
      ]);
}
''',
        <String>[],
        ['GestureDetector(onTap: {nativeEvent: p._h'],
      ),
      (
        'islands and actions in nested loops read every loop position',
        '''
void choose(String feature) {}

class Tier {
  const Tier({required this.name, required this.features});
  final String name;
  final List<String> features;
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.tiers});
  final List<Tier> tiers;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final tier in tiers)
          for (final feature in tier.features)
            GestureDetector(
              onTap: () => choose('\${tier.name}/\$feature'),
              child: Tinted(tint: feature.length, child: Text(feature)),
            ),
      ]);
}
''',
        [
          "for (final tier in _restageRecording.items( 'tiers', _restageArgument1, null, ['<wireKey>'], )) for (final feature in _restageRecording.items( '<wireKey>', tier.features, 'tiers', ['<wireKey>'], )) GestureDetector( onTap: _restageRecording.native( '<wireKey>', () => choose('\${tier.name}/\$feature'), items: '<wireKey>', type: '()->void', nullable: false, ), child: _restageRecording.island( 'mounted_Tinted_0',",
          "_restageRecording.islandAt( 'mounted_Tinted_0', [ _restageSource.v<int>(const <Object>['restageItems', 0])!, _restageSource.v<int>(const <Object>['restageItems', 1])!, ],",
        ],
        [', feature.'],
      ),
      for (final (name, root) in [
        (
          'ListView.builder',
          'ListView.builder(itemCount: names.length, '
              'itemBuilder: (context, i) => Tinted(child: Text(names[i])))',
        ),
        (
          'PageView.builder',
          'PageView.builder(itemCount: names.length, '
              'itemBuilder: (context, i) => Tinted(child: Text(names[i])))',
        ),
      ])
        (
          'a root $name stays in the design',
          '''
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.names});
  final List<String> names;
  @override
  Widget build(BuildContext context) => $root;
}
''',
          <String>[],
          <String>[],
        ),
      (
        'reads promoted by a guard around an island keep their type',
        '''
class Premium extends Plan {
  const Premium({required super.id, required super.rank, required this.badge});
  final String badge;
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans, this.name});
  final List<Plan> plans;
  final String? name;
  @override
  Widget build(BuildContext context) {
    final n = name;
    return Column(children: [
      for (final p in plans)
        if (p is Premium) Tinted(tint: p.badge.length, child: Text(p.id)),
      if (n != null) Tinted(tint: n.length, child: Text(n)),
    ]);
  }
}
''',
        [
          "if (p is Premium) ..._restageRecording.mark('<wireKey>', true, [ _restageRecording.island( 'mounted_Tinted_0', _restageRecording.built( Tinted(tint: p.badge.length, child: Text(p.id)),",
          'final n = _restageArgument2; return _restageDesign(',
          "if (n != null) ..._restageRecording.mark('<wireKey>', true, [ _restageRecording.island( 'mounted_Tinted_1', _restageRecording.built( Tinted(tint: n.length, child: Text(n)),",
        ],
        <String>[],
      ),
      (
        "an inherited State member an island needs moves the State in",
        '''
$stateful
class _MountedState extends State<Mounted> {
  int _count = 0;
  @override
  Widget build(BuildContext context) => Column(children: [
        Tap(onTap: () => setState(() => _count++), child: const Text('more')),
        Text('\$_count'),
      ]);
}
''',
        ['class _MountedSurfaceState', 'setState(() => _count++)'],
        <String>[],
      ),
      (
        'a lifted State keeps its constructions and reads this',
        '''
class Again extends StatelessWidget {
  const Again({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox();
}

$stateful
class _MountedState extends State<Mounted> {
  final ScrollController _scroll = ScrollController();
  void _again() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const Again()));
  @override
  Widget build(BuildContext context) => ListView(
        controller: this._scroll,
        children: [Tap(onTap: _again, child: Text(widget.title))],
      );
}
''',
        [
          'const Again()',
          "controller: _restageRecording.native( '<wireKey>', this._scroll, type: "
              "'flutter.ScrollController', nullable: false, )",
        ],
        <String>[],
      ),
      (
        'an id that is not an identifier names its islands one to one',
        '''
@Paywall(id: '2024-sale')
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) =>
      Column(children: [Tinted(tint: 2, child: const Text('a'))]);
}
''',
        ["'Island_d2024_x2d_sale_Tinted_0'"],
        <String>[],
      ),
      (
        'a read promoted without a guard keeps its type',
        '''
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, this.name});
  final String? name;
  @override
  Widget build(BuildContext context) {
    final n = name;
    return Column(children: [
      Text(n!),
      Tinted(tint: n.length, child: const Text('a')),
    ]);
  }
}
''',
        [
          'final n = _restageArgument1; return _restageDesign(',
          "Text(_restageRecording.value('<wireKey>', n!)), _restageRecording.island( 'mounted_Tinted_0', _restageRecording.built( Tinted(tint: n.length, child: const Text('a')),",
        ],
        <String>[],
      ),
      (
        'a bare this reads the surface instance',
        '''
int describe(Mounted surface) => surface.title.length;

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Column(children: [
        Tinted(tint: describe(this), child: const Text('a')),
      ]);
}
''',
        [
          'final _restageSurface = _restageSurfaces[this] ??= Mounted( '
              'title: _restageArgument1, );',
          "_restageRecording.island( 'mounted_Tinted_0', _restageRecording.built( Tinted(tint: describe(_restageSurface), child: const Text('a')),",
        ],
        <String>[],
      ),
      (
        'a lifted State renames only covariant parameter types',
        '''
$stateful
class _MountedState extends State<Mounted> {
  final ScrollController _scroll = ScrollController();
  int _changes = 0;
  void _note(Mounted? other) => _changes++;
  @override
  void didUpdateWidget(covariant Mounted oldWidget) {
    super.didUpdateWidget(oldWidget);
    _note(null);
  }

  @override
  Widget build(BuildContext context) => ListView(
        controller: _scroll,
        children: [Text('\${widget.title} \$_changes')],
      );
}
''',
        [
          'didUpdateWidget(covariant MountedSurface oldWidget)',
          'Mounted oldWidget, MountedSurface _restageOldWidget,',
          'super.didUpdateWidget(_restageOldWidget)',
          '_note(Mounted? other)',
        ],
        <String>[],
      ),
      (
        'a State override inherits its covariant parameter',
        '''
$stateful
class _MountedState extends State<Mounted> {
  final ScrollController _scroll = ScrollController();
  int _changes = 0;
  @override
  void didUpdateWidget(Mounted oldWidget) {
    super.didUpdateWidget(oldWidget);
    _changes++;
  }

  @override
  Widget build(BuildContext context) =>
      ListView(controller: _scroll, children: [Text('\${widget.title} \$_changes')]);
}
''',
        ['Mounted oldWidget, MountedSurface _restageOldWidget,'],
        <String>[],
      ),
      (
        'a guard inside an island keeps its own promotion',
        '''
class Premium extends Plan {
  const Premium({required super.id, required super.rank, required this.badge});
  final String badge;
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans});
  final List<Plan> plans;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final p in plans)
          Tinted(
            tint: p is Premium ? p.badge.length : 0,
            child: Text(p.id),
          ),
      ]);
}
''',
        [
          "_restageRecording.island( 'mounted_Tinted_0', _restageRecording.built( Tinted( tint: p is Premium ? p.badge.length : 0, child: Text(p.id), ),",
          "items: 'plans', ),",
        ],
        <String>[],
      ),
      for (final (name, guard) in [
        ('an inner condition', 'p.rank > 0 ? p.badge.length : 0'),
        ('a closure', 'plans.any((q) => q.id == p.id) ? p.badge.length : 0'),
      ])
        (
          'an outer guard with $name inside an island keeps its promotion',
          '''
class Premium extends Plan {
  const Premium({required super.id, required super.rank, required this.badge});
  final String badge;
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans});
  final List<Plan> plans;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final p in plans)
          if (p is Premium) Tinted(tint: $guard, child: Text(p.id)),
      ]);
}
''',
          [
            "if (p is Premium) ..._restageRecording.mark('<wireKey>', true, [ "
                "_restageRecording.island( 'mounted_Tinted_0', "
                // A guard with a closure is computed once, ahead of the widget.
                '${guard.contains('=>') ? "restageOnce<(int,), Widget>( ( ${guard.replaceAll('plans', '_restageArgument1')}, ), (_restageArgs) => _restageRecording.built( Tinted(tint: _restageArgs.\$1, child: Text(p.id))," : "_restageRecording.built( Tinted( tint: ${guard.replaceAll('plans', '_restageArgument1')}, child: Text(p.id), ),"}',
          ],
          <String>[],
        ),
      (
        "a stateless surface's members are read from an instance of it",
        '''
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.title});
  final String title;
  int get _count => title.length;
  Widget _row(String label) {
    if (label.isEmpty) return const SizedBox();
    return Text(label);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Tinted(tint: _count + 1, child: const Text('a')),
        _row('b'),
      ]);
}
''',
        [
          'final _restageSurface = _restageSurfaces[this] ??= Mounted( '
              'title: _restageArgument1, );',
          r"_restageRecording.island( 'mounted_Tinted_0', restageOnce<(int,), Widget>( (_restageSurface._count + 1,), (_restageArgs) => _restageRecording.built( Tinted(tint: _restageArgs.$1, child: const Text('a')),",
          "_restageRecording.island( 'mounted__row_0', _restageSurface._row('b'), events: true, )",
        ],
        <String>[],
      ),
      (
        'app wrappers above a builder stay in the app and the design starts below them',
        r'''
class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

class Count extends StatelessWidget {
  const Count({super.key, required this.builder});
  final Widget Function(BuildContext context, int n) builder;
  @override
  Widget build(BuildContext context) => builder(context, 1);
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Tinted(
      child: SafeArea(
        child: Hears(
          onContext: (context) => Navigator.of(context).maybePop(),
          child: Count(
            builder: (context, n) => Column(children: [
              Text('$n'),
              Tinted(tint: width.round(), child: const Text('a')),
            ]),
          ),
        ),
      ),
    );
  }
}
''',
        [
          "return (() { final width = MediaQuery.sizeOf(context).width; "
              'return Tinted( child: SafeArea( child: Hears( onContext: '
              '(context) => Navigator.of(context).maybePop(), child: Count( '
              'builder: (context, n) => (_restageRecording..frame(0)).exposing( '
              "{'<wireKey>': n}, _restageDesign( Column(",
        ],
        // The delivered path starts below the app's wrappers; the listener is
        // the app's own and is written once.
        ['widget Paywall = Column(children: [Text(text: data.context._h'],
      ),
      (
        'a lifted State reads the surface through widget and didUpdateWidget',
        r'''
$stateful
class _MountedState extends State<Mounted> {
  final ScrollController _scroll = ScrollController();
  late String _seen = widget.title;
  int _changes = 0;
  @override
  void didUpdateWidget(Mounted oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title) _changes++;
    _seen = widget.title;
  }

  @override
  Widget build(BuildContext context) => ListView(
        controller: _scroll,
        children: [Text('$_seen $_changes ${widget.title.length}')],
      );
}
'''
            .replaceAll(r'$stateful', stateful),
        [
          'late Mounted _restageWidget = Mounted(title: widget._restageArgument1);',
          'late String _seen = _restageWidget.title;',
          'final _restagePrevious = _restageWidget;',
          '_restageDidUpdateWidget(_restagePrevious, oldWidget);',
          'if (oldWidget.title != _restageWidget.title) _changes++;',
        ],
        <String>[],
      ),
      (
        'each island has a mount-free form for previews',
        r'''
class Needs extends StatelessWidget {
  const Needs({super.key, required this.count, required this.child});
  final int count;
  final Widget child;
  @override
  Widget build(BuildContext context) => ColoredBox(color: Color(0xFF000000 + count), child: child);
}

class Scrolly extends StatelessWidget {
  const Scrolly({super.key, required this.children, this.shrinkWrap = false});
  final List<Widget> children;
  final bool shrinkWrap;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: null, child: Column(children: children));
}

$stateful
class _MountedState extends State<Mounted> {
  int _count = 0;
  @override
  Widget build(BuildContext context) => Column(children: [
        Scrolly(shrinkWrap: true, children: [const Text('a')]),
        Tap(onTap: () => setState(() => _count++), child: const Text('b')),
        Needs(count: _count, child: Text(widget.title)),
        Tinted(tint: 2, child: const Text('c')),
      ]);
}
'''
            .replaceAll(r'$stateful', stateful),
        [
          r'Widget restagePreview$mounted_Scrolly_0( BuildContext '
              'restageContext, DataSource restageSource, ) => Scrolly( '
              'shrinkWrap: (RestageValueBinding',
          r'restagePreview$mounted_Tap_0',
          'Tap(onTap: () {}, child:',
          "RestageIslandPlaceholder( label: 'Needs', children: [ "
              "restageSource.child(const <Object>['child']), ], )",
          'return RestageIslandScope(',
        ],
        <String>[],
      ),
      (
        "a mount takes its surface's own base kind",
        r'''
abstract class Counted extends StatelessWidget {
  const Counted({super.key});
  @override
  StatelessElement createElement() => StatelessElement(this);
}

@Paywall()
final class Mounted extends Counted {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) =>
      Column(children: [Tinted(tint: 1, child: const Text('a'))]);
}
''',
        ['final class MountedSurface extends Counted {'],
        <String>[],
      ),
      (
        "a lifted State keeps a base that needs its surface's base kind",
        r'''
abstract class Scoped extends StatefulWidget {
  const Scoped({super.key});
  @override
  ScopedState<Scoped> createState();
}

abstract class ScopedState<T extends Scoped> extends State<T> {
  int get ref => 1;
}

@Paywall()
final class Mounted extends Scoped {
  const Mounted({super.key, required this.title});
  final String title;
  @override
  ScopedState<Mounted> createState() => _MountedState();
}

class _MountedState extends ScopedState<Mounted> {
  final ScrollController _scroll = ScrollController();
  @override
  Widget build(BuildContext context) =>
      ListView(controller: _scroll, children: [Text('${widget.title} $ref')]);
}
''',
        [
          'final class MountedSurface extends Scoped {',
          '_MountedSurfaceState createState() => _MountedSurfaceState();',
          'extends ScopedState<MountedSurface>',
        ],
        <String>[],
      ),
      (
        'a build prelude that calls code runs once in the mount',
        r'''
int _calls = 0;
int count() => ++_calls;

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) {
    final n = count();
    return Column(children: [
      Tinted(tint: n, child: const Text('a')),
      Text('${n + 1}'),
    ]);
  }
}
''',
        ['final n = count();', 'tint: n,'],
        <String>[],
      ),
      (
        'a State that reads widget outside build moves into the mount',
        r'''
$stateful
class _MountedState extends State<Mounted> {
  final ScrollController _scroll = ScrollController();
  late int _length;
  @override
  void initState() {
    super.initState();
    _length = widget.title.length;
  }

  @override
  Widget build(BuildContext context) =>
      ListView(controller: _scroll, children: [Text('$_length')]);
}
'''
            .replaceAll(r'$stateful', stateful),
        ['_length = _restageWidget.title.length;'],
        <String>[],
      ),
      (
        'a build with statements runs them once in the mount',
        r'''
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.names});
  final List<String> names;
  @override
  Widget build(BuildContext context) {
    var count = 0;
    for (final name in names) {
      if (name.isNotEmpty) count++;
    }
    return Column(children: [
      Text('$count'),
      Tinted(tint: count, child: const Text('a')),
    ]);
  }
}
''',
        ['var count = 0;', 'for (final name in ', 'tint: count,'],
        <String>[],
      ),
      (
        'a build with several returns delivers the one its mount took',
        r'''
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.names});
  final List<String> names;
  @override
  Widget build(BuildContext context) {
    final n = names.length;
    if (n == 0) {
      return GestureDetector(onTap: () => buy(), child: const Text('none'));
    }
    if (n > 3) return Tinted(tint: n, child: const Text('many'));
    return Column(children: [for (final name in names) Text(name)]);
  }
}
''',
        [
          "final n = _restageArgument1.length; if (n == 0) { return _restageDesign( _restageRecording.branch( '<wireKey>', 0, GestureDetector(onTap: () => buy(), child: const Text('none')), ), ); } if (n > 3) return _restageDesign( _restageRecording.branch( '<wireKey>', 1, _restageRecording.island( 'mounted_Tinted_0',",
          "'<wireKey>', 2, Column(children: [for (final name in _restageArgument1) Text(name)]),",
        ],
        ['switch data.context._h', 'default: Column('],
      ),
      (
        'behavior among delivered siblings is an island built around the delivered child',
        r'''
class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          Text(title),
          Hears(
            onContext: (context) => Navigator.of(context).maybePop(),
            child: Text(title),
          ),
        ]),
      );
}
''',
        [
          'Padding( padding: const EdgeInsets.all(8), child: Column( '
              "children: [ Text(_restageArgument1), _restageRecording.island( "
              "'mounted_Hears_0', _restageRecording.built( Hears( onContext: (context) => "
              'Navigator.of(context).maybePop(), child: '
              'Text(_restageArgument1), ), (_restageContext, '
              '_restageSource) => Hears( onContext: (context) => '
              'Navigator.of(context).maybePop(), child: '
              "_restageSource.child(const <Object>['child']),",
        ],
        ['Padding(padding:', 'mounted_Hears_0(child: Text(text: '],
      ),
      (
        "an island that reads a State's field moves the State into the mount",
        '''
$stateful
class _MountedState extends State<Mounted> {
  int _count = 0;
  @override
  Widget build(BuildContext context) => Column(children: [
        Tinted(tint: _count + 1, child: Text(widget.title)),
        GestureDetector(
          onTap: () => setState(() => _count++),
          child: const Text('more'),
        ),
      ]);
}
''',
        ['class _MountedSurfaceState', 'setState(() => _count++)'],
        <String>[],
      ),
      (
        'the fallback keys an island as the mount does',
        r'''
class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) => Hears(
        onContext: (context) => Navigator.of(context).maybePop(),
        child: Column(children: [
          const Text('Go'),
          Tinted(tint: 2, child: const Text('held')),
        ]),
      );
}
''',
        [
          "return (() => Hears( onContext: (context) => Navigator.of(context).maybePop(), child: _restageDesign( Column( children: [ const Text('Go'), _restageRecording.island( 'mounted_Tinted_0', _restageRecording.built( Tinted(tint: 2, child: const Text('held')),",
        ],
        <String>[],
      ),
    ]) {
      test(name, () async {
        final generated = await _generatedPart(
          '$header$body',
          'mounted',
          warningFree: true,
          paywallText: text.isEmpty
              ? null
              : (payload) {
                  for (final fragment in text) {
                    expect(payload, contains(fragment));
                  }
                },
        );
        final flat = generated.replaceAll(RegExp(r'\s+'), ' ');
        for (final fragment in expected) {
          _expectTemplate(flat, fragment);
        }
        _readableTextsOf(generated).forEach(_expectReadable);
        // One mount per surface: no builder repeats it.
        expect(
          'RestagePaywall('.allMatches(generated).length,
          '@Paywall('.allMatches(body).length,
        );
      });
    }

    test(
      'a widget local that calls code is computed once for its placements',
      () async {
        final generated = await _generatedPart(
          '''
$header
var calls = 0;

Widget makeCard() {
  calls++;
  return Tinted(tint: calls, child: const Text('x'));
}

class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans});
  final List<Plan> plans;
  @override
  Widget build(BuildContext context) {
    final card = makeCard();
    return Hears(
      onContext: (context) => Navigator.of(context).maybePop(),
      child: Column(children: [card, card]),
    );
  }
}
''',
          'mounted',
          warningFree: true,
          paywallText: (payload) => expect(
            payload,
            contains(
              'Column(children: [mounted_card0_makeCard_0(), '
              'mounted_card1_makeCard_0()])',
            ),
          ),
        );
        final flat = generated.replaceAll(RegExp(r'\s+'), ' ');
        // The build calls it once; each placement reads the local.
        expect(_callsIn(generated, 'makeCard'), 1);
        expect(flat, contains('final card = makeCard();'));
        _expectTemplate(
          flat,
          "_restageRecording.island('mounted_card0_makeCard_0', card)",
        );
        _expectTemplate(
          flat,
          "_restageRecording.island('mounted_card1_makeCard_0', card)",
        );
      },
    );
  });

  test('a preview never copies a value that reads a builder local', () async {
    final part = await _generatedPart(
      '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/legal.restage.g.dart';

class Count extends StatelessWidget {
  const Count({super.key, required this.builder});
  final Widget Function(BuildContext context, int n) builder;
  @override
  Widget build(BuildContext context) => builder(context, 1);
}

class Legal extends StatelessWidget {
  const Legal({super.key, required this.heading, required this.lines});
  final String heading;
  final List<String> lines;
  @override
  Widget build(BuildContext context) =>
      GestureDetector(onTap: () => debugPrint(heading), child: Text(lines.join()));
}

String note(List<String> products) => products.join(', ');

const free = 'Free';

@Paywall()
final class Terms extends StatelessWidget {
  const Terms({super.key});
  @override
  Widget build(BuildContext context) => Count(builder: (context, n) {
        final products = ['a', 'b'];
        return Column(children: [
          Legal(heading: 'Subscription terms', lines: [free, note(products)]),
          Legal(heading: 'Free terms', lines: const [free]),
        ]);
      });
}
''',
      'legal',
      warningFree: true,
    );
    final flat = part.replaceAll(RegExp(r'\s+'), '');
    // The closed value is copied; the one reading `products` is not.
    expect(flat, contains("??const[free]"));
    expect(
      RegExp(r'restagePreview\$[^;]*note\(products\)').hasMatch(flat),
      isFalse,
    );
  });

  test(
    'a recorded mount publishes where its build produces a guarded value',
    () async {
      final part = await _generatedPart(
        '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/guarded.restage.g.dart';

String describe(String o) => o.toUpperCase();

@Paywall()
final class Guarded extends StatelessWidget {
  const Guarded({super.key, this.offer});
  final String? offer;
  @override
  Widget build(BuildContext context) => Column(children: [
        if (offer != null) Text(describe(offer!)),
      ]);
}
''',
        'guarded',
        warningFree: true,
      );
      final flat = part.replaceAll(RegExp(r'\s+'), '');
      expect(flat, contains("'layouts':<String,Object?>{'domains':"));
      expect(flat, contains("'values':<String,Object?>{'_h"));
    },
  );

  // A builder closure runs only when Flutter calls it, so what its body
  // computes is recorded by that closure: a kept builder or an island slot.
  for (final (id, body, check) in <(String, String, void Function(String, String))>[
    (
      'acme_root',
      'SafeArea(child: Listen(listener: (context, state) => calls.add("l"), '
          'child: Signal(builder: (context, state) { final c = ink(); '
          'return Padding(padding: const EdgeInsets.all(8), child: ListView('
          'controller: _scroll, children: [Text("n \$state", style: TextStyle(color: c))])); })))',
      (part, text) {
        expect(
          part,
          matches(
            RegExp(
              r'Signal\(\s*builder: \(context, state\) \{[^]*return _restageDesign\(\s*Padding\(',
            ),
          ),
        );
        expect(text, contains('widget Paywall = Padding('));
      },
    ),
    (
      'acme_slot',
      'Column(children: [const Text("head"), Expanded(child: Signal('
          'builder: (context, state) { final c = ink(); '
          'return ListView(controller: _scroll, children: [Text("n \$state", style: TextStyle(color: c))]); }))])',
      // An installed value in the body keeps the builder whole in its island.
      (part, text) {
        expect(
          part,
          contains(
            "_restageRecording.island(\n              'acme__slot_Signal_0',",
          ),
        );
        expect(text, contains('child: acme__slot_Signal_0()'));
        expect(text, isNot(contains('data.context')));
      },
    ),
    (
      'once_tween',
      'Column(children: [TweenAnimationBuilder<double>(tween: Tween(begin: 0, '
          'end: end()), duration: const Duration(seconds: 1), builder: '
          '(context, value, child) => Text("t \${value.round()}"))])',
      // A shared argument keeps the type its parameter infers.
      (part, text) {
        expect(
          part,
          matches(RegExp(r'restageOnce<\(Tween<double>,\s*\),\s*Widget>\(')),
        );
        expect(RegExp(r'\bend\(\)').allMatches(part), hasLength(2));
      },
    ),
    (
      'slot_flag',
      '{ final shown = flagNow(); return Column(children: [const Text("h"), '
          'ValueListenableBuilder<int>(valueListenable: counter, builder: '
          '(context, count, child) => Visibility(visible: shown, child: Text("n \$count")))]); }',
      // The slot records the condition into its own recording.
      (part, text) {
        expect(part, contains('_restageSlotRecording.'));
        expect(part, isNot(contains('_restageRecording.mark(')));
        expect(text, isNot(contains('data.context._h')));
      },
    ),
    (
      'slot_if',
      '{ final shown = flagNow(); return Column(children: [const Text("h"), '
          'ValueListenableBuilder<int>(valueListenable: counter, builder: '
          '(context, count, child) => Column(children: [if (shown) Text("n \$count")]))]); }',
      // The slot records the condition into its own recording.
      (part, text) {
        expect(part, contains('_restageSlotRecording.'));
        expect(part, isNot(contains('_restageRecording.mark(')));
        expect(text, isNot(contains('data.context._h')));
      },
    ),
    (
      'slot_and',
      '{ final shown = flagNow(); return Column(children: [const Text("h"), '
          'ValueListenableBuilder<int>(valueListenable: counter, builder: '
          '(context, count, child) => Column(children: [if (shown && count > 0) Text("n \$count")]))]); }',
      // The slot records the condition into its own recording.
      (part, text) {
        expect(part, contains('_restageSlotRecording.'));
        expect(part, isNot(contains('_restageRecording.mark(')));
        expect(text, isNot(contains('data.context._h')));
      },
    ),
  ]) {
    test('app builder rows: $id', () async {
      final source =
          """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/$id.restage.g.dart';

final calls = <String>[];

class Listen extends StatelessWidget {
  const Listen({super.key, required this.listener, required this.child});
  final void Function(BuildContext context, int state) listener;
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

class Signal extends StatelessWidget {
  const Signal({super.key, required this.builder});
  final Widget Function(BuildContext context, int state) builder;
  @override
  Widget build(BuildContext context) => builder(context, 2);
}

double end() {
  calls.add('end');
  return 100;
}

final counter = ValueNotifier<int>(1);

bool flagNow() {
  calls.add('flag');
  return true;
}

Color ink() {
  calls.add('ink');
  return const Color(0xFF112233);
}

@Paywall(id: '$id')
final class Shape extends StatefulWidget {
  const Shape({super.key});
  @override
  State<Shape> createState() => _ShapeState();
}

class _ShapeState extends State<Shape> {
  final ScrollController _scroll = ScrollController();

  @override
  Widget build(BuildContext context) ${body.startsWith('{') ? body : '=> $body;'}
}
""";
      late String text;
      final part = await _generatedPart(
        source,
        id,
        paywallText: (t) => text = t,
      );
      check(part, text);
    });
  }

  // A value only an app builder slot records belongs to that slot: a design
  // that reads it at the top of the surface doesn't fit.
  test('a top-level read of a slot-only value is refused by fit', () async {
    const id = 'slot_only';
    late RestageSurfacePublicationBundle bundle;
    final part = await _generatedPart(
      '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/$id.restage.g.dart';

final counter = ValueNotifier<int>(1);

String shout(String text) => text.toUpperCase();

@Paywall(id: '$id')
final class Shape extends StatelessWidget {
  const Shape({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final shown = shout(label);
    return Column(children: [
      const Text('h'),
      ValueListenableBuilder<int>(
        valueListenable: counter,
        builder: (context, count, child) => Text('\$shown \$count'),
      ),
    ]);
  }
}
''',
      id,
      handoff: (b) => bundle = b,
    );
    final key = RegExp(
      r"_restageSlotRecording\.value\('(_h\w+)'",
    ).firstMatch(part)![1]!;
    final host = _hostContractOf(part, '');
    expect(host.providedContext.inputs.keys, isNot(contains(key)));
    final own = bundle.manifest!.publications
        .singleWhere((entry) => entry.publication.slug == id)
        .publication
        .fitRequirement!;
    // The context failures of [requirement] against the surface's contract.
    List<String> fit(SurfaceFitRequirementV1 requirement) => [
      for (final failure in SurfaceFitEvaluator.evaluate(
        host: host,
        requirement: requirement,
        installed: InstalledCapability(
          builtInCatalogVersion: 1 << 20,
          installedLibraries: const [],
        ),
      ).failures)
        if (failure.path.startsWith(r'$.requiredContext')) failure.code.name,
    ];
    expect(fit(own), isEmpty);
    final topLevel = SurfaceFitRequirementV1(
      hosting: own.hosting,
      requiredContext: SurfaceScreenHostDataSchema({
        ...own.requiredContext.inputs,
        key: const SurfaceScreenHostDataScalarShapeV1(
          SurfaceScreenHostDataScalarKind.string,
        ),
      }),
      emittedEvents: own.emittedEvents,
      capabilities: own.capabilities,
      requiredVocabulary: own.requiredVocabulary,
      flowBoundary: own.flowBoundary,
      requiredIslands: own.requiredIslands,
      islandLabels: own.islandLabels,
      layoutReads: own.layoutReads,
    );
    expect(fit(topLevel), contains('missingHostField'));
  });

  group('source placement shapes compile as the app runs them', () {
    String shell(String child) =>
        'return Hears(onContext: (context) => Navigator.of(context).maybePop(), '
        'child: $child);';
    const local = "final card = makeCard();\n    ";
    // Each call's count in the part: the copy of the app's build writes
    // every call once where the app writes it (an inlined helper's body takes
    // the helper's place); previews and string literals are not calls.
    for (final (id, body, counts) in <(String, String, Map<String, int>)>[
      (
        'A01 call local placed twice',
        local + shell('Column(children: [card, card])'),
        {'makeCard': 1},
      ),
      (
        'A02 call local placed once and read once',
        local + shell(r"Column(children: [card, Text('${card.key}')])"),
        {'makeCard': 1},
      ),
      (
        'A03 call local placed once in a loop',
        local +
            shell(
              'Column(children: [for (final p in plans) Row(children: [Text(p.name), card])])',
            ),
        {'makeCard': 1},
      ),
      (
        'A04 call local in exclusive arms',
        local +
            shell('flag ? Column(children: [card]) : Row(children: [card])'),
        {'makeCard': 1},
      ),
      (
        'A05 helper places a call argument twice',
        shell('Column(children: [twice(makeCard())])'),
        {'makeCard': 1},
      ),
      (
        'A06 helper twice per item',
        shell('Column(children: [for (final p in plans) twice(makeFor(p))])'),
        {'makeFor': 1},
      ),
      (
        'A07 guarded helper twice',
        shell('Column(children: [if (flag) twice(makeCard())])'),
        {'makeCard': 1},
      ),
      (
        'A08 code guard',
        shell('Column(children: [if (eligible()) twice(makeCard())])'),
        {'makeCard': 1, 'eligible': 1},
      ),
      (
        'A09 code guard per item',
        shell(
          'Column(children: [for (final p in plans) if (okFor(p)) twice(makeFor(p))])',
        ),
        {'makeFor': 1, 'okFor': 1},
      ),
      (
        'A10 one code guard over two arguments',
        shell('cond() ? twice(makeA()) : twice(makeB())'),
        {'makeA': 1, 'makeB': 1, 'cond': 1},
      ),
      (
        'A11 helper inside a helper',
        shell('Column(children: [outer()])'),
        {'makeCard': 1},
      ),
      (
        'A12 helper places once and reads once',
        shell('Column(children: [show(makeCard())])'),
        {'makeCard': 1},
      ),
      (
        'A13 iterable that runs code',
        shell(
          'Column(children: [for (final p in loadPlans()) twice(makeFor(p))])',
        ),
        {'makeFor': 1, 'loadPlans': 1},
      ),
      (
        'A15 source order of preludes',
        "final a = logA();\n    " +
            shell(
              'Column(children: [twice(makeCard()), Text(a), Text(logC())])',
            ),
        {'makeCard': 1, 'logA': 1, 'logC': 1},
      ),
      (
        'A17 call local passed to a helper',
        local + shell('Column(children: [twice(card)])'),
        {'makeCard': 1},
      ),
      (
        'A18 argument through another helper',
        shell('Column(children: [twice(wrap(makeCard()))])'),
        {'makeCard': 1},
      ),
      (
        'A19 shorthand pattern loop',
        shell(
          'Column(children: [for (final Plan(:name) in plans) twice(makeNamed(name))])',
        ),
        {'makeNamed': 1},
      ),
      (
        'A20 literal-list loop',
        shell(
          "Column(children: [for (final s in const ['a', 'b']) twice(makeLabel(s))])",
        ),
        {'makeLabel': 1},
      ),
      (
        'A21 getter guard per item',
        shell(
          'Column(children: [for (final p in plans) if (p.name.isNotEmpty) twice(makeFor(p))])',
        ),
        {'makeFor': 1},
      ),
      (
        'A22 conditional per item',
        shell(
          'Column(children: [for (final p in plans) p.name.isEmpty ? const SizedBox() : twice(makeFor(p))])',
        ),
        {'makeFor': 1},
      ),
      (
        'A23 nested loops',
        shell(
          'Column(children: [for (final p in plans) Column(children: [for (final t in tags) twice(make2(p, t))])])',
        ),
        {'make2': 1},
      ),
      (
        'A24 code guard outside a loop',
        shell(
          'Column(children: [if (eligible()) for (final p in plans) twice(makeFor(p))])',
        ),
        {'makeFor': 1, 'eligible': 1},
      ),
      (
        'A25 code guard with an else arm',
        shell(
          "Column(children: [if (eligible()) twice(makeA()) else const Text('no')])",
        ),
        {'makeA': 1, 'eligible': 1},
      ),
      (
        'A27 helper call in a local initializer',
        "final pair = twice(makeCard());\n    " +
            shell('Column(children: [pair])'),
        {'makeCard': 1},
      ),
      (
        'A28 two helpers with one call each',
        shell('Column(children: [twice(makeA()), twice(makeB())])'),
        {'makeA': 1, 'makeB': 1},
      ),
      (
        'A30 code conditional',
        shell('Column(children: [cond() ? twice(makeA()) : const SizedBox()])'),
        {'makeA': 1, 'cond': 1},
      ),
      (
        'A31 code conditional per item',
        shell(
          'Column(children: [for (final p in plans) okFor(p) ? twice(makeFor(p)) : const SizedBox()])',
        ),
        {'makeFor': 1, 'okFor': 1},
      ),
      (
        'A32 code if with calls in both arms',
        shell(
          'Column(children: [if (cond()) twice(makeA()) else twice(makeB())])',
        ),
        {'makeA': 1, 'makeB': 1, 'cond': 1},
      ),
      (
        'A33 nested guards, inner runs code',
        shell(
          'Column(children: [if (flag) if (eligible()) twice(makeCard())])',
        ),
        {'makeCard': 1, 'eligible': 1},
      ),
      (
        'A36 helper inside a helper, const argument',
        shell('Column(children: [outerConst()])'),
        <String, int>{},
      ),
      (
        'A37 list parameter spread twice',
        shell('twiceList([makeCard()])'),
        {'makeCard': 1},
      ),
      (
        'A38 code conditional, call in the else arm',
        shell('Column(children: [cond() ? const SizedBox() : twice(makeA())])'),
        {'makeA': 1, 'cond': 1},
      ),
      (
        'A40 call local in exclusive arms and twice in one',
        local +
            shell(
              'flag ? Column(children: [card]) : Row(children: [card, card])',
            ),
        {'makeCard': 1},
      ),
      (
        'A41 pattern loop with a named field',
        shell(
          'Column(children: [for (final Plan(name: n) in plans) twice(makeNamed(n))])',
        ),
        {'makeNamed': 1},
      ),
      (
        'A42 shorthand pattern, value read outside too',
        shell(
          'Column(children: [for (final Plan(:name) in plans) Row(children: [Text(name), twice(makeNamed(name))])])',
        ),
        {'makeNamed': 1},
      ),
      (
        'A44 a value before a helper call',
        shell('Column(children: [Text(logC()), twice(makeCard())])'),
        {'makeCard': 1, 'logC': 1},
      ),
      (
        'A45 a helper twice inside a helper twice',
        shell('Column(children: [twice(twice(makeCard()))])'),
        {'makeCard': 1},
      ),
      (
        'K4c list local spread twice',
        "final cards = <Widget>[Opaque(child: const SizedBox())];\n    " +
            shell('Column(children: [...cards, ...cards])'),
        <String, int>{},
      ),
      (
        'K4d const local twice in a const list',
        "const card = Opaque(child: SizedBox());\n    " +
            shell('Column(children: const [card, card])'),
        <String, int>{},
      ),
      (
        'N1 helper beside an if element',
        shell(
          "Column(children: [cardFor(const Plan('a')), Opaque(child: const SizedBox()), if (flag) const Text('x')])",
        ),
        <String, int>{},
      ),
      (
        'G11 list helper spread',
        shell('Column(children: [...twiceItems(makeCard())])'),
        {'makeCard': 1},
      ),
      (
        'G12 list helper as children',
        shell('Column(children: twiceItems(makeCard()))'),
        {'makeCard': 1},
      ),
      (
        'G8 two loops over one computed list',
        shell(
          'Column(children: [for (final p in loadPlans()) Text(p.name), for (final q in loadPlans()) Text(q.name)])',
        ),
        {'loadPlans': 2},
      ),
      (
        'G1 loop under a null check',
        shell(
          'Column(children: [if (offer != null) for (final f in offer!.features) Text(f)])',
        ),
        <String, int>{},
      ),
      (
        'G2 loop under a length check, list empty',
        shell(
          'Column(children: [if (tagged.isNotEmpty) for (final t in tagged.first.tags) Text(t)])',
        ),
        <String, int>{},
      ),
      (
        'G5 code list under a code guard',
        shell(
          'Column(children: [if (eligible()) for (final p in loadPlans()) Text(p.name)])',
        ),
        {'eligible': 1, 'loadPlans': 1},
      ),
      (
        'G9 condition over a nullable string',
        shell(
          "Column(children: [if (title != null) for (final c in title!.split(',')) Text(c)])",
        ),
        <String, int>{},
      ),
      (
        'G10 collection condition beside a local',
        "final card = Opaque(child: const SizedBox());\n    " +
            shell('Column(children: [card, if (plans.isEmpty) card])'),
        <String, int>{},
      ),
      (
        'H8 early return before a guarded list',
        "if (offer == null) return const Text('none');\n    " +
            shell(
              'Column(children: [for (final f in offer!.features) Text(f)])',
            ),
        <String, int>{},
      ),
      (
        'X1 return inside an if block before a guarded list',
        "if (offer != null) {\n      " +
            shell(
              'Column(children: [for (final f in offer!.features) Text(f)])',
            ) +
            "\n    }\n    return const Text('none');",
        <String, int>{},
      ),
      (
        'X2 return inside an if without braces',
        "if (offer != null) " +
            shell(
              'Column(children: [for (final f in offer!.features) Text(f)])',
            ) +
            "\n    return const Text('none');",
        <String, int>{},
      ),
      (
        'X3 return two ifs deep',
        "if (flag) {\n      if (offer != null) {\n        " +
            shell(
              'Column(children: [for (final f in offer!.features) Text(f)])',
            ) +
            "\n      }\n    }\n    return const Text('none');",
        <String, int>{},
      ),
      (
        'H12 top-level list under a per-item check',
        shell(
          'Column(children: [for (final p in plans) if (p.name.isNotEmpty) for (final f in offer!.features) Text(f)])',
        ),
        <String, int>{},
      ),
      (
        'H15 guard at a helper call',
        shell('Column(children: [if (offer != null) featuresOf(offer!)])'),
        {'featuresOf': 0},
      ),
      (
        'H16 nested code guard',
        shell(
          'Column(children: [if (offer != null) if (hasFeatures(offer!)) for (final f in offer!.features) Text(f)])',
        ),
        {'hasFeatures': 1},
      ),
      (
        'H17 code guard under a flag',
        shell(
          'Column(children: [if (flag) if (eligible()) for (final p in loadPlans()) Text(p.name)])',
        ),
        {'eligible': 1, 'loadPlans': 1},
      ),
      (
        'H19 conditional at a helper call',
        shell('offer == null ? const SizedBox() : featuresOf(offer!)'),
        {'featuresOf': 0},
      ),
      (
        'H21 early return before a computed list',
        "if (plans.isEmpty) return const Text('none');\n    " +
            shell(
              'Column(children: [for (final p in loadPlans()) Text(p.name)])',
            ),
        {'loadPlans': 1},
      ),
      (
        'H22 guard at a helper call with a computed list',
        shell('Column(children: [if (flag) planList()])'),
        {'loadPlans': 1, 'planList': 0},
      ),
      (
        'C3 right operand of a null check',
        shell(
          "Column(children: [if (title != null && title!.isNotEmpty) const Text('titled')])",
        ),
        <String, int>{},
      ),
      (
        'I1 per-item value under a per-item null check',
        shell(
          'Column(children: [for (final h in holders) if (h.offer != null) Text(describe(h.offer!))])',
        ),
        {'describe': 1},
      ),
      (
        'I2 per-item value under a per-item check that calls code',
        shell(
          'Column(children: [for (final h in holders) if (h.offer != null && hasFeatures(h.offer!)) Text(describe(h.offer!))])',
        ),
        {'describe': 1, 'hasFeatures': 1},
      ),
      (
        'D1a per-item list under a per-item check that calls code',
        shell(
          'Column(children: [for (final h in holders) if (h.offer != null && hasFeatures(h.offer!)) for (final f in h.offer!.features) Text(f)])',
        ),
        {'hasFeatures': 1},
      ),
      (
        'D1b per-item list under a per-item call alone',
        shell(
          'Column(children: [for (final h in holders) if (hasFeatures(h.offer!)) for (final f in h.offer!.features) Text(f)])',
        ),
        {'hasFeatures': 1},
      ),
      (
        'K30a block local read in an app-rendered widget',
        "if (offer != null) {\n      final features = offer!.features;\n      " +
            shell('Opaque(child: Text(features.first))') +
            "\n    }\n    return const Text('none');",
        <String, int>{},
      ),
      (
        'K30b block local looped over',
        "if (offer != null) {\n      final features = offer!.features;\n      " +
            shell('Column(children: [for (final f in features) Text(f)])') +
            "\n    }\n    return const Text('none');",
        <String, int>{},
      ),
      (
        'K30c block local read in a Text',
        "if (offer != null) {\n      final features = offer!.features;\n      " +
            shell('Text(features.first)') +
            "\n    }\n    return const Text('none');",
        <String, int>{},
      ),
      (
        'K30d the same name declared in two branches',
        "if (offer != null) {\n      final label = offer!.features.first;\n      " +
            shell('Text(label)') +
            "\n    }\n    if (title != null) {\n      final label = title!;\n      " +
            shell('Text(label)') +
            "\n    }\n    return const Text('none');",
        <String, int>{},
      ),
      (
        'K30e a block local shadowing a top-level local',
        "final label = describeAll();\n    if (offer != null) {\n      final label = offer!.features.first;\n      " +
            shell('Text(label)') +
            "\n    }\n    " +
            shell('Text(label)'),
        {'describeAll': 1},
      ),
      (
        'X15a if-case variable read in a Text',
        "if (offer case final o?) {\n      " +
            shell('Text(o.features.first)') +
            "\n    }\n    return const Text('none');",
        <String, int>{},
      ),
      (
        'X15b if-case variable read in an app-rendered widget',
        "if (offer case final o?) {\n      " +
            shell('Opaque(child: Text(o.features.first))') +
            "\n    }\n    return const Text('none');",
        <String, int>{},
      ),
      (
        'X15c if-case variable looped over',
        "if (offer case final o?) {\n      " +
            shell('Column(children: [for (final f in o.features) Text(f)])') +
            "\n    }\n    return const Text('none');",
        <String, int>{},
      ),
      (
        'X15d if-case variable under a when guard',
        "if (offer case final o? when o.features.isNotEmpty) {\n      " +
            shell('Text(o.features.first)') +
            "\n    }\n    return const Text('none');",
        <String, int>{},
      ),
      (
        'R4 loop body local read by a conditional return',
        "for (final p in plans) {\n      final n = p.name;\n      if (n.isNotEmpty) " +
            shell('Text(n)') +
            "\n    }\n    return const Text('none');",
        <String, int>{},
      ),
      (
        'R5 loop variable read by a return',
        "for (final p in plans) {\n      if (p.name.isNotEmpty) " +
            shell('Text(p.name)') +
            "\n    }\n    return const Text('none');",
        <String, int>{},
      ),
      (
        'Q9 nested-loop key from the inner item',
        shell(
          'Column(children: [for (final p in tagged) for (final t in p.tags) ElevatedButton(key: ValueKey(t), onPressed: null, child: Text(t))])',
        ),
        <String, int>{},
      ),
      (
        'Q3 nested-loop key from both items',
        shell(
          "Column(children: [for (final p in tagged) for (final t in p.tags) ElevatedButton(key: ValueKey('\${p.tags.first}/\$t'), onPressed: null, child: Text(t))])",
        ),
        <String, int>{},
      ),
      (
        'Z1 block local named like a top-level function the build calls',
        "if (flag) {\n      final headline = 'block';\n      " +
            shell('Text(headline)') +
            "\n    }\n    " +
            shell('Text(headline())'),
        {'headline': 1},
      ),
      (
        'Z2 block local named like a top-level final the build reads',
        "if (flag) {\n      final kBanner = 'block';\n      " +
            shell('Text(kBanner)') +
            "\n    }\n    " +
            shell('Text(kBanner)'),
        <String, int>{},
      ),
      (
        'Z2c block local named like a top-level const the build reads',
        "if (flag) {\n      final kConst = 'block';\n      " +
            shell('Text(kConst)') +
            "\n    }\n    " +
            shell('Text(kConst)'),
        <String, int>{},
      ),
      (
        'Z4 block local named context',
        "if (flag) {\n      final context = 'block';\n      " +
            shell('Text(context)') +
            "\n    }\n    return const Text('none');",
        <String, int>{},
      ),
      (
        'Z5 block local named like a mount field',
        "if (flag) {\n      final resolver = 'block';\n      " +
            shell('Text(resolver)') +
            "\n    }\n    return const Text('none');",
        <String, int>{},
      ),
      (
        'Z7 destructuring declaration in a block',
        "if (offer != null) {\n      final (count, first) = (offer!.features.length, offer!.features.first);\n      " +
            shell('Text(first.padLeft(count))') +
            "\n    }\n    return const Text('none');",
        <String, int>{},
      ),
      (
        'T1 classic loop index read by a return',
        "for (var i = 0; i < plans.length; i++) {\n      if (plans[i].name.isNotEmpty) " +
            shell('Text(plans[i].name)') +
            "\n    }\n    return const Text('none');",
        <String, int>{},
      ),
      (
        'T3b try block local read by a return',
        "try {\n      final t = describe(offer!);\n      " +
            shell('Text(t)') +
            "\n    } on Object {\n      // The offer may be missing.\n    }\n    return const Text('none');",
        {'describe': 1},
      ),
      (
        'XC3 switch statement whose cases return',
        "switch (flag) {\n      case true:\n        " +
            shell("const Text('on')") +
            "\n      case false:\n        return const Text('off');\n    }",
        <String, int>{},
      ),
      (
        'S1 pattern switch statement with a guard that binds',
        "switch (offer) {\n      case Offer(features: [final first, ...]) when first.isNotEmpty:\n        " +
            shell('Text(first)') +
            "\n      case _:\n        return const Text('none');\n    }",
        <String, int>{},
      ),
      (
        'W13 pattern loop variables read by a return',
        "for (final (i, p) in plans.indexed) {\n      if (i == 1) " +
            shell('Text(p.name)') +
            "\n    }\n    return const Text('none');",
        <String, int>{},
      ),
      (
        'T2 root switch expression whose arm binds',
        "return switch (offer) {\n      Offer(:final features) => Hears(onContext: (context) => Navigator.of(context).maybePop(), child: Column(children: [for (final f in features) Text(f)])),\n      _ => const Text('none'),\n    };",
        <String, int>{},
      ),
      (
        'T2g root switch expression with a guard that binds',
        "return switch (offer) {\n      Offer(:final features) when features.isNotEmpty => Hears(onContext: (context) => Navigator.of(context).maybePop(), child: Text(features.first)),\n      _ => const Text('none'),\n    };",
        <String, int>{},
      ),
      (
        'SW1 sealed switch expression with a guard over a computed subject',
        "return switch (tierOf(flag)) {\n      Paid(:final plan) when plan.isNotEmpty => Hears(onContext: (context) => Navigator.of(context).maybePop(), child: Text(plan)),\n      Paid() => const Text('paid'),\n      Free() => const Text('free'),\n    };",
        {'tierOf': 1},
      ),
      (
        'SW2 sealed switch statement over a computed subject',
        "switch (tierOf(flag)) {\n      case Paid(:final plan):\n        return Hears(onContext: (context) => Navigator.of(context).maybePop(), child: Text(plan));\n      case Free():\n        return const Text('free');\n    }",
        {'tierOf': 1},
      ),
      (
        'T4 catch parameters read by a return',
        "try {\n      final d = describe(offer!);\n      " +
            shell('Text(d)') +
            "\n    } on TypeError catch (e, s) {\n      " +
            shell("Text('\${e.runtimeType} \${s.toString().isNotEmpty}')") +
            "\n    }",
        {'describe': 1},
      ),
      (
        'K21 per-item key over an input list',
        shell(
          'Column(children: [for (final p in plans) ElevatedButton(key: ValueKey(p.name), onPressed: null, child: Text(p.name))])',
        ),
        <String, int>{},
      ),
      (
        'K22 per-item key over a guarded computed list',
        shell(
          'Column(children: [if (offer != null) for (final f in offer!.features) ElevatedButton(key: ValueKey(f), onPressed: null, child: Text(f))])',
        ),
        <String, int>{},
      ),
      (
        'K43 per-item key over a computed list',
        shell(
          'Column(children: [for (final p in loadPlans()) ElevatedButton(key: ValueKey(p.name), onPressed: null, child: Text(p.name))])',
        ),
        {'loadPlans': 1},
      ),
      (
        'K46 per-item callbacks over a guarded computed list',
        shell(
          'Column(children: [if (offer != null) for (final f in offer!.features) TextButton(onPressed: () => calls.add(f), child: Text(f))])',
        ),
        <String, int>{},
      ),
      (
        'I3 per-item check that also tests a top-level call',
        shell(
          'Column(children: [for (final h in holders) if (eligible() && h.offer != null) Text(describe(h.offer!))])',
        ),
        {'eligible': 1, 'describe': 1},
      ),
      (
        'I4 top-level call as the only per-item check',
        shell(
          'Column(children: [for (final h in holders) if (eligible()) Text(describe(h.offer!))])',
        ),
        {'eligible': 1, 'describe': 1},
      ),
      (
        'G6 list under a conditional',
        shell(
          "Column(children: [offer != null ? Column(children: [for (final f in offer!.features) Text(f)]) : const Text('none')])",
        ),
        <String, int>{},
      ),
    ]) {
      test(id, () async {
        final source =
            """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/probed.restage.g.dart';

final calls = <String>[];

class Plan {
  const Plan(this.name);
  final String name;
}

Widget makeCard() {
  calls.add('card');
  return Opaque(child: const SizedBox());
}

Widget makeA() {
  calls.add('a');
  return Opaque(tint: 1, child: const SizedBox());
}

Widget makeB() {
  calls.add('b');
  return Opaque(tint: 2, child: const SizedBox());
}

Widget makeFor(Plan p) {
  calls.add('for');
  return Opaque(child: Text(p.name));
}

Widget make2(Plan p, String t) {
  calls.add('two');
  return Opaque(child: Text(t));
}

Widget makeNamed(String name) {
  calls.add('named');
  return Opaque(child: Text(name));
}

Widget makeLabel(String s) {
  calls.add('label');
  return Opaque(child: Text(s));
}

bool eligible() {
  calls.add('eligible');
  return true;
}

bool okFor(Plan p) {
  calls.add('ok');
  return true;
}

bool cond() {
  calls.add('cond');
  return true;
}

List<Plan> loadPlans() {
  calls.add('load');
  return [for (var i = 0; i < calls.length; i++) Plan('\$i')];
}

String logA() {
  calls.add('logA');
  return 'a';
}

String logC() {
  calls.add('logC');
  return 'c';
}

Widget twice(Widget w) => Row(children: [w, w]);

Widget cardFor(Plan p) => Opaque(child: Text(p.name));

Widget outer() => twice(makeCard());

Widget show(Widget w) => Column(children: [w, Text('\${w.key}')]);

Widget wrap(Widget w) => Padding(padding: EdgeInsets.zero, child: w);

Widget outerConst() => twice(Opaque(child: const SizedBox()));

Widget twiceList(List<Widget> ws) => Column(children: [...ws, ...ws]);

List<Widget> twiceItems(Widget w) => [w, w];

Widget featuresOf(Offer o) => Column(children: [for (final f in o.features) Text(f)]);

bool hasFeatures(Offer o) {
  calls.add('has');
  return o.features.isNotEmpty;
}

Widget planList() => Column(children: [for (final p in loadPlans()) Text(p.name)]);

final class Holder {
  const Holder(this.offer);
  final Offer? offer;
}

sealed class Tier {
  const Tier();
}

final class Free extends Tier {
  const Free();
}

final class Paid extends Tier {
  const Paid(this.plan);
  final String plan;
}

Tier tierOf(bool flag) {
  calls.add('tierOf');
  return flag ? const Paid('pro') : const Free();
}

String headline() {
  calls.add('headline');
  return 'top';
}

final kBanner = 'top';

const kConst = 'top';

String describeAll() {
  calls.add('describeAll');
  return 'all';
}

String describe(Offer o) {
  calls.add('describe');
  return o.features.join(', ');
}

final class Offer {
  const Offer(this.features);
  final List<String> features;
}

final class Tagged {
  const Tagged(this.tags);
  final List<String> tags;
}

class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

class Opaque extends StatelessWidget {
  const Opaque({super.key, required this.child, this.tint = 0});
  final Widget child;
  final int tint;
  @override
  Widget build(BuildContext context) => ColoredBox(color: Color(0xFF000000 + tint), child: child);
}

@Paywall()
final class Probed extends StatelessWidget {
  const Probed({super.key, required this.plans, this.tags = const [], this.flag = false, this.offer, this.tagged = const [], this.title, this.holders = const []});
  final List<Plan> plans;
  final List<String> tags;
  final bool flag;
  final Offer? offer;
  final List<Tagged> tagged;
  final String? title;
  final List<Holder> holders;
  @override
  Widget build(BuildContext context) {
    $body
  }
}
""";
        final messages = <String>[];
        String? payload;
        final part = await _generatedPart(
          source,
          'probed',
          warningFree: true,
          warned: messages.addAll,
          paywallText: (text) => payload = text,
        );
        // A switch resolves its key as data, never as a program.
        expect(payload, isNot(contains('switch { version: 1')));
        final spaced = part.replaceAll(RegExp(r'\s+'), ' ');
        expect(messages.join('\n'), isNot(contains('This design places')));
        // No helper argument is computed ahead of the build, and nothing of
        // the old lifted machinery is left.
        for (final old in const [
          '_restageShared',
          '_restageItems',
          '_restageLocal_',
          'restageBound',
          'restageBranch',
          'case true)',
        ]) {
          expect(part, isNot(contains(old)));
        }
        // The app's build runs once per build; each call is written once
        // where the app writes it, and a previewed island's copy is not a call.
        expect({
          for (final call in counts.keys) call: _callsIn(part, call),
        }, counts);
        final copy = spaced.substring(spaced.indexOf('return (() {'));
        void copies(String template) => _expectTemplate(copy, template);

        // The statements and guards the app writes, with the recording around
        // each value, list, guard and return.
        switch (id.split(' ').first) {
          case 'A13':
            copies(
              "for (final p in _restageRecording.items( '<wireKey>', loadPlans(), "
              "null, ['<wireKey>'], )) _restageRecording.island( 'probed_twice_0', "
              'twice(makeFor(p)),',
            );
          case 'A15':
            copies(
              'return (() { final a = logA(); return '
              '_restageRecording.withEvents( Hears(',
            );
            copies(
              "_restageRecording.island( 'probed_twice_0', "
              'twice(makeCard()), events: true, ), '
              "Text(_restageRecording.value('<wireKey>', a)), "
              "Text(_restageRecording.value('<wireKey>', logC())),",
            );
          case 'A44':
            copies(
              "Text(_restageRecording.value('<wireKey>', logC())), "
              "_restageRecording.island( 'probed_twice_0', "
              'twice(makeCard()), events: true, ),',
            );
          case 'G1':
            copies(
              "if (_restageArgument4 != null) ..._restageRecording.mark("
              "'<wireKey>', true, [ for (final f in _restageRecording.items( '<wireKey>', "
              '_restageArgument4!.features, )) Text(',
            );
            copies(
              "else ..._restageRecording.mark('<wireKey>', false, const [])",
            );
          case 'G2':
            copies(
              'if (_restageArgument5.isNotEmpty) ..._restageRecording.mark('
              "'<wireKey>', true, [ for (final t in _restageRecording.items( '<wireKey>', "
              '_restageArgument5.first.tags, ))',
            );
          case 'G5':
            copies(
              "if (eligible()) ..._restageRecording.mark('<wireKey>', true, [ "
              "for (final p in _restageRecording.items( '<wireKey>', loadPlans(), ))",
            );
          case 'G8':
            copies(
              "for (final p in _restageRecording.items( '<wireKey>', "
              "loadPlans(), )) Text( _restageRecording.value( '<wireKey>', p.name, "
              "'<wireKey>', ), ), for (final q in _restageRecording.items( '<wireKey>', "
              'loadPlans(), ))',
            );
          case 'X1':
            copies(
              'if (_restageArgument4 != null) { return _restageDesign( '
              "_restageRecording.branch( '<wireKey>', 0,",
            );
            copies(
              "return _restageDesign( _restageRecording.branch('<wireKey>', 1, "
              "const Text('none')), );",
            );
          case 'X2':
            copies(
              'if (_restageArgument4 != null) return _restageDesign( '
              "_restageRecording.branch( '<wireKey>', 0,",
            );
          case 'X3':
            copies(
              'if (_restageArgument3) { if (_restageArgument4 != null) { '
              "return _restageDesign( _restageRecording.branch( '<wireKey>', 0,",
            );
          case 'H8':
            copies(
              'if (_restageArgument4 == null) return _restageDesign( '
              "_restageRecording.branch('<wireKey>', 0, const Text('none')), ); "
              "return _restageDesign( _restageRecording.branch( '<wireKey>', 1,",
            );
          case 'H12':
            // The list is read only under the app's own guard.
            copies(
              "for (final p in _restageRecording.items( 'plans', "
              '_restageArgument1, )) if (p.name.isNotEmpty) '
              "..._restageRecording.mark('<wireKey>', true, [ for (final f in "
              "_restageRecording.items( '<wireKey>', _restageArgument4!.features,",
            );
          case 'H15':
            copies(
              'if (_restageArgument4 != null) ..._restageRecording.mark('
              "'<wireKey>', true, [ ((Offer o) => Column(",
            );
            copies('))(_restageArgument4!), ]) else');
          case 'H22':
            copies(
              'if (_restageArgument3) ..._restageRecording.mark('
              "'<wireKey>', true, [ (() => Column(",
            );
          case 'H16':
            copies(
              'if (_restageArgument4 != null) ..._restageRecording.mark('
              "'<wireKey>', true, [ if (hasFeatures(_restageArgument4!)) "
              "..._restageRecording.mark('<wireKey>', true, [ for (final f in",
            );
          case 'H17':
            copies(
              'if (_restageArgument3) ..._restageRecording.mark('
              "'<wireKey>', true, [ if (eligible()) ..._restageRecording.mark('<wireKey>', "
              'true, [ for (final p in',
            );
          case 'H19':
            copies(
              "_restageArgument4 == null ? _restageRecording.taken( '<wireKey>', "
              "true, const SizedBox(), ) : _restageRecording.taken( '<wireKey>', "
              'false, ((Offer o) => Column(',
            );
          case 'H21':
            copies(
              'if (_restageArgument1.isEmpty) return _restageDesign( '
              "_restageRecording.branch('<wireKey>', 0, const Text('none')), );",
            );
            copies(
              "for (final p in _restageRecording.items( '<wireKey>', "
              'loadPlans(), ))',
            );
          case 'I1':
            copies(
              "for (final h in _restageRecording.items( '<wireKey>', "
              '_restageArgument7, )) if (h.offer != null) '
              "..._restageRecording.mark('<wireKey>', true, [ Text( "
              "_restageRecording.value( '<wireKey>', describe(h.offer!), '<wireKey>', ), ), "
              "], '<wireKey>') else",
            );
          case 'I2':
            copies(
              'if (((h.offer != null || (_restageRecording.value( '
              "'<wireKey>', false, '<wireKey>', ) && false)) && (_restageRecording.value( "
              "'<wireKey>', true, '<wireKey>', ) || true)) && ((hasFeatures(h.offer!) || "
              "(_restageRecording.value( '<wireKey>', false, '<wireKey>', ) && false)) && "
              "(_restageRecording.value( '<wireKey>', true, '<wireKey>', ) || true))) Text(",
            );
          case 'D1a':
            copies(
              'if (((h.offer != null || (_restageRecording.value( '
              "'<wireKey>', false, '<wireKey>', ) && false)) && (_restageRecording.value( "
              "'<wireKey>', true, '<wireKey>', ) || true)) && ((hasFeatures(h.offer!) || "
              "(_restageRecording.value( '<wireKey>', false, '<wireKey>', ) && false)) && "
              "(_restageRecording.value( '<wireKey>', true, '<wireKey>', ) || true))) for "
              "(final f in _restageRecording.items( '<wireKey>', h.offer!.features,",
            );
          case 'D1b':
            copies(
              'if (hasFeatures(h.offer!)) ..._restageRecording.mark('
              "'<wireKey>', true, [ for (final f in _restageRecording.items( '<wireKey>', "
              "h.offer!.features, '<wireKey>', ))",
            );
          case 'I3':
            copies(
              "if (((eligible() || (_restageRecording.value('<wireKey>', false) "
              "&& false)) && (_restageRecording.value('<wireKey>', true) || true)) "
              '&& ((h.offer != null ||',
            );
          case 'I4':
            copies(
              "for (final h in _restageRecording.items( '<wireKey>', "
              '_restageArgument7, )) if (eligible()) '
              "..._restageRecording.mark('<wireKey>', true, [ Text(",
            );
          case 'C3':
            copies(
              'if (((_restageArgument6 != null || '
              "(_restageRecording.value('<wireKey>', false) && false)) && "
              "(_restageRecording.value('<wireKey>', true) || true)) && "
              '((_restageArgument6!.isNotEmpty || '
              "(_restageRecording.value('<wireKey>', false) && false)) && "
              "(_restageRecording.value('<wireKey>', true) || true))) const "
              "Text('titled')",
            );
          case 'K21':
            expect(payload, contains('ElevatedButton(key: p._h'));
            copies(
              "key: _restageRecording.native( '<wireKey>', ValueKey(p.name), "
              "items: 'plans', type: 'flutter.Key', nullable: false, )",
            );
          case 'K22':
            expect(payload, contains('ElevatedButton(key: f._h'));
            copies(
              "key: _restageRecording.native( '<wireKey>', ValueKey(f), items: "
              "'<wireKey>', type: 'flutter.Key', nullable: false, )",
            );
          case 'K43':
            expect(payload, contains('ElevatedButton(key: p._h'));
            copies(
              "key: _restageRecording.native( '<wireKey>', ValueKey(p.name), "
              "items: '<wireKey>', type: 'flutter.Key', nullable: false, )",
            );
          case 'K46':
            copies(
              "onPressed: _restageRecording.native( '<wireKey>', () => "
              "calls.add(f), items: '<wireKey>', type: '()->void', nullable: "
              'false, )',
            );
          case 'K30a' || 'K30b' || 'K30c':
            // The block's local is declared and assigned as the app writes it.
            copies(
              'if (_restageArgument4 != null) { final features = '
              '_restageArgument4!.features; return _restageDesign( '
              "_restageRecording.branch( '<wireKey>', 0,",
            );
          case 'K30d':
            copies(
              '{ final label = _restageArgument4!.features.first; '
              'return _restageDesign(',
            );
            copies(
              '{ final label = _restageArgument6!; return _restageDesign(',
            );
            // Two branches' reads of one name are two recorded values.
            final keys = {
              for (final m in RegExp(
                r"value\('(_h\w+)', label\)",
              ).allMatches(copy))
                m[1],
            };
            expect(keys, hasLength(2));
          case 'K30e':
            copies(
              'return (() { final label = describeAll(); '
              'if (_restageArgument4 != null) { final label = '
              '_restageArgument4!.features.first; return',
            );
          case 'X15a' || 'X15b' || 'X15c':
            copies(
              'if (_restageArgument4 case final o?) { return '
              "_restageDesign( _restageRecording.branch( '<wireKey>', 0,",
            );
          case 'X15d':
            copies(
              'if (_restageArgument4 case final o? when '
              'o.features.isNotEmpty) { return _restageDesign(',
            );
          case 'R4':
            copies(
              'for (final p in _restageArgument1) { final n = p.name; '
              'if (n.isNotEmpty) return _restageDesign( '
              "_restageRecording.branch( '<wireKey>', 0,",
            );
          case 'R5':
            copies(
              'for (final p in _restageArgument1) { '
              'if (p.name.isNotEmpty) return _restageDesign(',
            );
          case 'Z1':
            copies(
              "if (_restageArgument3) { final headline = 'block'; "
              'return _restageDesign(',
            );
            copies("Text(_restageRecording.value('<wireKey>', headline()))");
          case 'Z2':
            copies(
              "if (_restageArgument3) { final kBanner = 'block'; "
              'return _restageDesign(',
            );
          case 'Z2c':
            copies(
              "if (_restageArgument3) { final kConst = 'block'; "
              'return _restageDesign(',
            );
            // A constant is read as the constant, not recorded.
            copies('child: Text(kConst)');
          case 'Z4':
            copies(
              "if (_restageArgument3) { final context = 'block'; "
              'return _restageDesign(',
            );
          case 'Z5':
            copies(
              "if (_restageArgument3) { final resolver = 'block'; "
              'return _restageDesign(',
            );
          case 'Q9' || 'Q3':
            // A nested list publishes its items so each item's key crosses.
            expect(payload, contains('ElevatedButton(key: t._h'));
            copies(
              "for (final p in _restageRecording.items( '<wireKey>', "
              "_restageArgument5, )) for (final t in "
              "_restageRecording.items( '<wireKey>', p.tags, '<wireKey>', )) "
              'ElevatedButton(',
            );
          case 'Z7':
            copies(
              'final (count, first) = ( _restageArgument4!.features'
              '.length, _restageArgument4!.features.first, );',
            );
          case 'T1':
            copies(
              'for (var i = 0; i < _restageArgument1.length; i++) { '
              'if (_restageArgument1[i].name.isNotEmpty) return '
              '_restageDesign(',
            );
          case 'T3b':
            copies(
              'try { final t = describe(_restageArgument4!); return '
              "_restageDesign( _restageRecording.branch( '<wireKey>', 0,",
            );
            copies('} on Object {');
          case 'T4':
            copies(
              'try { final d = describe(_restageArgument4!); return '
              '_restageDesign(',
            );
            copies('} on TypeError catch (e, s) { return _restageDesign(');
          case 'XC3':
            copies(
              'switch (_restageArgument3) { case true: return '
              "_restageDesign( _restageRecording.branch( '<wireKey>', 0,",
            );
            copies(
              "case false: return _restageDesign( "
              "_restageRecording.branch('<wireKey>', 1,",
            );
          case 'S1':
            copies(
              'switch (_restageArgument4) { case Offer(features: '
              '[final first, ...]) when first.isNotEmpty: return '
              '_restageDesign(',
            );
          case 'W13':
            copies(
              'for (final (i, p) in _restageArgument1.indexed) { '
              'if (i == 1) return _restageDesign(',
            );
          case 'T2':
            copies(
              'return switch (_restageArgument4) { Offer(:final '
              "features) => _restageDesign( _restageRecording.branch( '<wireKey>', "
              '0,',
            );
          case 'T2g':
            copies(
              'Offer(:final features) when features.isNotEmpty => '
              '_restageDesign(',
            );
          case 'SW1':
            copies(
              'return switch (tierOf(_restageArgument3)) { Paid(:final '
              'plan) when plan.isNotEmpty => _restageDesign(',
            );
          case 'SW2':
            copies(
              'switch (tierOf(_restageArgument3)) { case Paid(:final '
              'plan): return _restageDesign(',
            );
        }
      });
    }
  });

  group('developer messages', () {
    const header = """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/mounted.restage.g.dart';

class Tinted extends StatelessWidget {
  const Tinted({super.key, required this.child, this.tint = 0});
  final Widget child;
  final int tint;
  @override
  Widget build(BuildContext context) => ColoredBox(color: Color(0xFF000000 + tint), child: child);
}
""";
    const stateful = """
@Paywall()
final class Mounted extends StatefulWidget {
  const Mounted({super.key});
  @override
  State<Mounted> createState() => _MountedState();
}
""";
    // Each row is a surface and the exact message a developer reads, from
    // the build or, for a build that succeeds, from the generated part.
    final rows = <(String, String, String)>[
      for (final (name, base, message) in [
        (
          'a base that needs constructor arguments',
          'const Counted(this.tint, {super.key}); final int tint;',
          "`MountedSurface` wasn't generated because `Counted` requires "
              'constructor arguments. Try extending `StatelessWidget` '
              'directly.',
        ),
        (
          'a base that leaves a member unimplemented',
          'const Counted({super.key}); int get tint;',
          "`MountedSurface` wasn't generated because `Counted` leaves `tint` "
              'without a body. Try extending `StatelessWidget` directly.',
        ),
      ])
        (
          name,
          """
abstract class Counted extends StatelessWidget {
  $base
  @override
  StatelessElement createElement() => StatelessElement(this);
}

@Paywall()
final class Mounted extends Counted {
  const Mounted({super.key})${base.contains('this.tint') ? ' : super(1)' : ''};
${base.contains('this.tint') ? '' : '  @override\n  int get tint => 1;\n'}
  @override
  Widget build(BuildContext context) => const Text('a');
}
""",
          message,
        ),
      (
        'a build with several returns',
        """
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, this.empty = false});
  final bool empty;
  @override
  Widget build(BuildContext context) {
    if (empty) return const Text('none');
    return Column(children: [Tinted(tint: 1, child: const Text('a'))]);
  }
}
""",
        '  which return Mounted.build takes',
      ),
      (
        'a surface that has no build of its own',
        """
@Paywall()
final class Mounted extends SingleChildRenderObjectWidget {
  const Mounted({super.key});
  @override
  RenderObject createRenderObject(BuildContext context) => RenderProxyBox();
}
""",
        '@Paywall Mounted must resolve to a Flutter StatelessWidget or '
            'StatefulWidget.',
      ),
      (
        'an island that reads what only the screen has',
        """
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) => Column(
      children: [Tinted(tint: super.hashCode, child: const Text('a'))]);
}
""",
        '`Column(children: [Tinted(tint: super.hashCode, child: const…` '
            '(lib/mounted.dart:17:41): uses `super`, which only exists inside '
            "`Mounted`. Try passing it in through the screen's constructor.",
      ),
      (
        'an opt-out the generated widget cannot keep',
        """
@RenderInApp()
class Pill extends StatelessWidget {
  const Pill({super.key, required this.tint});
  final int tint;
  @override
  Widget build(BuildContext context) => Text('\$tint');
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) =>
      Column(children: [Pill(tint: super.hashCode)]);
}
""",
        "The generated widget can't build `Pill` (lib/mounted.dart:26:25) "
            'in app code as `@RenderInApp` asks because `Pill` uses `super`, '
            "which the generated widget can't reach. Try removing "
            '`@RenderInApp`, or passing what `Pill` uses in through the '
            "screen's constructor.",
      ),
      (
        'a State whose screen the generated surface cannot copy',
        """
$stateful
class _MountedState extends State<Mounted> {
  final ScrollController _scroll = ScrollController();
  @override
  Widget build(BuildContext context) => ListView(
      controller: _scroll, children: [Text('\${super.hashCode}')]);
}
""",
        "`_MountedState` can't be used in the generated `MountedSurface` "
            'because its build reads `super.hashCode` (lib/mounted.dart:24:47). '
            'Try reading the value through a member of `_MountedState`.',
      ),
      (
        'a State whose build calls a restricted lookup',
        """
import 'package:intl/intl.dart';
$stateful
class _MountedState extends State<Mounted> {
  final ScrollController _scroll = ScrollController();
  @override
  Widget build(BuildContext context) => ListView(
      controller: _scroll,
      children: [Text(Intl.message('Hi', name: 'hi')),
        Tinted(tint: 1, child: const Text('a'))]);
}
""",
        // The State moves into the mount, and the lookup runs where the app
        // calls it.
        "`Tinted` (lib/mounted.dart:27:9) needs app code that only "
            '`MountedSurface` provides. Try using `MountedSurface` to build '
            'this screen.',
      ),
      (
        'a State whose build calls a method on a restricted lookup',
        """
import 'package:intl/intl.dart';
$stateful
class _MountedState extends State<Mounted> {
  final ScrollController _scroll = ScrollController();
  @override
  Widget build(BuildContext context) => ListView(
      controller: _scroll,
      children: [Text(Intl.message('Hi', name: 'hi').toUpperCase()),
        Tinted(tint: 1, child: const Text('a'))]);
}
""",
        // The State moves into the mount, and the lookup runs where the app
        // calls it.
        "`Tinted` (lib/mounted.dart:27:9) needs app code that only "
            '`MountedSurface` provides. Try using `MountedSurface` to build '
            'this screen.',
      ),
      (
        'a State whose build calls a function by its bare name',
        """
$stateful
String label(int taps) => 'taps \$taps';
class _MountedState extends State<Mounted> {
  int taps = 0;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label(taps)),
        Tinted(tint: taps, child: const Text('a')),
      ]);
}
""",
        // The State moves into the mount, which calls it as the app does.
        "`Tinted` (lib/mounted.dart:26:9) needs app code that only "
            '`MountedSurface` provides. Try using `MountedSurface` to build '
            'this screen.',
      ),
      (
        'a State whose base accepts only its screen',
        """
$stateful
abstract class MountedBase<T extends Mounted> extends State<T> {}
class _MountedState extends MountedBase<Mounted> {
  final ScrollController _scroll = ScrollController();
  @override
  Widget build(BuildContext context) => ListView(
      controller: _scroll, children: [Tinted(tint: 1, child: const Text('a'))]);
}
""",
        "`_MountedState` can't be used in the generated `MountedSurface`. Its "
            'base class `MountedBase` only accepts `Mounted` as its widget. '
            "Try loosening the bound on `MountedBase`'s type parameter.",
      ),
      (
        'a build statement the generated surface cannot copy',
        """
$stateful
class _MountedState extends State<Mounted>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [Tinted(tint: 1, child: const Text('a'))]);
  }
}
""",
        "`_MountedState` can't be used in the generated `MountedSurface` "
            'because its build calls `super.build(context)` '
            '(lib/mounted.dart:26:5). Try calling it through a member of '
            '`_MountedState`.',
      ),
      (
        'an island on a screen with no generated surface',
        """
final class MountedSurface {}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) =>
      Column(children: [Tinted(tint: 2, child: const Text('a'))]);
}
""",
        "`Tinted(tint: 2, child: const Text('a'))` (lib/mounted.dart:20:25) "
            "runs app code, which needs the generated `MountedSurface`, and "
            "Restage didn't "
            'generate it because `MountedSurface` already exists in '
            'lib/mounted.dart. Try renaming `MountedSurface` in '
            'lib/mounted.dart.',
      ),
      (
        'a loop island on a screen with no generated surface',
        """
final class MountedSurface {}

class Plan {
  const Plan({required this.id, required this.rank});
  final String id;
  final int rank;
}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.plans});
  final List<Plan> plans;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final p in plans) Tinted(tint: p.rank, child: Text(p.id)),
      ]);
}
""",
        '`Tinted(tint: p.rank, child: Text(p.id))` (lib/mounted.dart:27:32) '
            "runs app code, which needs the generated `MountedSurface`, and "
            "Restage didn't "
            'generate it because `MountedSurface` already exists in '
            'lib/mounted.dart. Try renaming `MountedSurface` in '
            'lib/mounted.dart.',
      ),
      (
        'a value on a screen with no generated surface',
        """
final class MountedSurface {}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context) =>
      Column(children: [Text(name.toUpperCase())]);
}
""",
        '`name.toUpperCase()` (lib/mounted.dart:21:30) runs app code, '
            "which needs the generated `MountedSurface`, and Restage didn't "
            'generate it because `MountedSurface` already exists in '
            'lib/mounted.dart. Try renaming `MountedSurface` in '
            'lib/mounted.dart.',
      ),
      (
        'a State on a screen with no generated surface',
        """
final class MountedSurface {}
$stateful
class _MountedState extends State<Mounted> {
  int taps = 0;
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: () => setState(() => taps++),
      child: Column(children: [Tinted(tint: taps, child: const Text('a'))]));
}
""",
        "`_MountedState` (lib/mounted.dart:21:1) holds the screen's state in "
            "app code, which needs the generated `MountedSurface`, and Restage "
            "didn't "
            'generate it because `MountedSurface` already exists in '
            'lib/mounted.dart. Try renaming `MountedSurface` in '
            'lib/mounted.dart.',
      ),
      (
        'a screen whose generated surface is left out',
        """
final class MountedSurface {}

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Column(children: [Text(name)]);
}
""",
        "`MountedSurface` wasn't generated because `MountedSurface` already "
            'exists in lib/mounted.dart. Try renaming `MountedSurface` in '
            'lib/mounted.dart.',
      ),
      (
        'an import prefix that clashes with the generated surface',
        """
import 'dart:math' as resolver;
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Column(children: [Text(name)]);
}
""",
        "`MountedSurface` wasn't generated because the import prefix "
            '`resolver` clashes with a name the generated `MountedSurface` '
            'uses. Try renaming the prefix.',
      ),
    ];
    test('a Restage bug links to a pre-filled bug report', () {
      final issue = islandNameConflictIssue('Tinted', 'lib/mounted.dart:3:4');
      expect(
        issue.message,
        'Tinted at lib/mounted.dart:3:4 compiled to two different '
        'app-rendered widgets under one name. Report this as a Restage bug.',
      );
      _expectReadable(issue.message);
      final log = issue.toLogString();
      final link = Uri.parse(
        log.split('\nReport this Restage bug: ').last.trim(),
      );
      expect(link.path, endsWith('/issues/new'));
      expect(
        link.queryParameters['title'],
        '[restage_codegen] Bug: islandNameConflict',
      );
      expect(link.queryParameters['labels'], 'codegen-bug');
      expect(link.queryParameters['body'], contains('restage.codegen.bug.v1'));
    });

    for (final (name, body, message) in rows) {
      test(name, () async {
        final messages = <String>[];
        // A runtime message, a warning and a value's label come from a build
        // that succeeds.
        final builds =
            message.contains('needs app code that only') ||
            message.contains("wasn't generated") ||
            message.trimLeft().startsWith('which return ');
        // A row's own imports go before the header's part directive.
        final imports = [
          for (final line in body.split('\n'))
            if (line.startsWith('import ')) line,
        ];
        final source =
            header.replaceFirst(
              "part '",
              '${imports.map((line) => '$line\n').join()}part \'',
            ) +
            body
                .split('\n')
                .where((line) => !line.startsWith('import '))
                .join('\n');
        final part = await _generatedPart(
          source,
          'mounted',
          warned: (warnings) => messages.addAll([
            for (final warning in warnings) ...warning.split('\n'),
          ]),
          expectPart: !message.contains("wasn't generated"),
          refused: builds
              ? null
              : (errors) => messages.addAll(errors.map(_issueMessage)),
        );
        messages.addAll(_readableTextsOf(part));
        expect(messages, contains(message));
        messages.forEach(_expectReadable);
      });
    }
  });

  group('a flow step that needs the app', () {
    String step(
      String fields,
      String body, {
      bool flow = true,
      String combinator = '',
      String prelude = '',
    }) =>
        """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart'$combinator;

part 'restage.generated/${flow ? 'first_run' : 'welcome'}.restage.g.dart';

final _held = GlobalKey();

class Tinted extends StatelessWidget {
  const Tinted({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ColoredBox(color: const Color(0xFF000000), child: child);
}

@Screen(id: 'welcome')
final class Welcome extends StatelessWidget {
  $fields

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) {
    $prelude
    return Column(children: [
        $body,
        FilledButton(onPressed: surfaceEvent(next), child: const Text('Go')),
      ]);
  }
}

${flow ? '''
@FlowGraph(id: 'first_run', surface: Surface.onboarding)
const firstRun = FlowDefinition(
  start: Welcome,
  transitions: [Transition.complete(Welcome.next)],
);
''' : ''}""";

    test('a categorized step that needs the app gets a mount', () async {
      final flat = (await _generatedPart(
        step(
          'const Welcome({super.key, required this.title});\n'
              'final String title;',
          'Text(title.toUpperCase())',
        ).replaceFirst(
          "@Screen(id: 'welcome')",
          "@Screen(id: 'welcome', surface: Surface.onboarding)",
        ),
        'first_run',
      )).replaceAll(RegExp(r'\s+'), '');
      expect(flat, contains(r'restageStepMount$welcome('));
      expect(flat, contains(r"stepMounts:{'welcome':restageStepMount$welcome"));
    });

    test('gets a mount the flow names', () async {
      final flat = (await _generatedPart(
        step(
          'const Welcome({super.key, required this.title});\n'
              'final String title;',
          'Text(title.toUpperCase()), '
              "KeyedSubtree(key: _held, child: const Text('held'))",
        ),
        'first_run',
      )).replaceAll(RegExp(r'\s+'), '');
      for (final part in [
        r'final_restageStepOwner$welcome=Object();',
        r'WidgetrestageStepMount$welcome(BuildContextcontext,'
            'Widget_restageChild,Widget_restageOriginal,){',
        'final_restageSurface=_restageOriginalasWelcome;',
        'RestageStepValues(built:_restageBuilt,values:',
        "_restageRecording.value('_h",
        '_restageSurface.title.toUpperCase(),',
        r'RestageIslandScope(owner:RestageIslandScope.hostOf(context)??'
            r'_restageStepOwner$welcome,',
        r"stepMounts:{'welcome':restageStepMount$welcome",
        "surfaceWidget:'FirstRunSurface'",
        r'libraries:[restageIslands$welcome_KeyedSubtree_0]',
        'needsappcodethatonly`FirstRunSurface`provides.Tryusing'
            '`FirstRunSurface`tobuildthisflow.',
      ]) {
        expect(flat, contains(part));
      }
      // The flow installs the step's islands before any step runs.
      expect(flat, isNot(contains('addToInstalled')));
    });

    test("fits a build by its steps' islands", () async {
      late RestageSurfacePublicationBundle bundle;
      final part = await _generatedPart(
        step(
          'const Welcome({super.key});',
          "KeyedSubtree(key: _held, child: const Text('held'))",
        ),
        'first_run',
        handoff: (b) => bundle = b,
      );
      final requirement = bundle.manifest!.publications
          .singleWhere((entry) => entry.publication.slug == 'first_run')
          .publication
          .fitRequirement!;
      expect(requirement.requiredIslands, hasLength(1));
      final host = _hostContractOf(part, 'firstRun');
      expect(host.islands, requirement.requiredIslands);
      // The handoff records the same islands for the flow's previews and
      // push report.
      expect(
        bundle.surfaceIslands['onboarding/first_run'],
        requirement.requiredIslands.keys,
      );
      final name = requirement.requiredIslands.keys.single;
      for (final (row, islands, codes) in [
        ('its own build', host.islands, <String>[]),
        ('a changed island', {name: 'w1'}, ['changedIsland']),
        ('a build without it', <String, String>{}, ['missingIsland']),
      ]) {
        final verdict = SurfaceFitEvaluator.evaluate(
          host: SurfaceHostContractV1(
            hosting: host.hosting,
            providedContext: host.providedContext,
            handledEvents: host.handledEvents,
            flowBoundary: host.flowBoundary,
            islands: islands,
          ),
          requirement: requirement,
          installed: InstalledCapability(
            builtInCatalogVersion: 1 << 20,
            installedLibraries: const [],
          ),
        );
        expect(
          [
            for (final failure in verdict.failures)
              if (failure.path.startsWith(r'$.requiredIslands.'))
                failure.code.name,
          ],
          codes,
          reason: row,
        );
      }
    });

    // The step's build reads the field its input is kept in.
    for (final (name, body) in [
      ('a value', 'Text(label.toUpperCase())'),
      ('a widget', "Tinted(child: const Text('held'))"),
    ]) {
      test('compiles $name when an input is kept under another name', () async {
        final part = await _generatedPart(
          step(
            'Welcome({super.key, required String title}) : label = title;\n'
            'final String label;\n'
            'Key get held => _held;',
            body,
          ),
          'first_run',
          warningFree: true,
        );
        // A constant widget needs nothing from the app.
        if (name == 'a value') {
          expect(part, contains(r'restageStepMount$welcome'));
        }
      });
    }

    test('a stateful step gets a widget that holds its State', () async {
      const source = """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/first_run.restage.g.dart';

class Tap extends StatelessWidget {
  const Tap({super.key, required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: child);
}

@Screen(id: 'welcome', surface: Surface.onboarding)
final class Welcome extends StatefulWidget {
  const Welcome({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  State<Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<Welcome> {
  int _count = 0;

  void _bump() => setState(() => _count++);

  @override
  Widget build(BuildContext context) => Column(children: [
        Text('\$_count'),
        Tap(onTap: _bump, child: const Text('More')),
      ]);
}

@FlowGraph(id: 'first_run', surface: Surface.onboarding)
const firstRun = FlowDefinition(
  start: Welcome,
  transitions: [Transition.complete(Welcome.next)],
);
""";
      final flat = (await _generatedPart(
        source,
        'first_run',
        warningFree: true,
      )).replaceAll(RegExp(r'\s+'), '');
      for (final part in [
        r'restageStepMount$welcome(BuildContextcontext,Widget_restageChild,'
            r'Widget_restageOriginal,)=>_restageStepWidget$welcome(',
        r'finalclass_restageStepWidget$welcomeextendsStatefulWidget{',
        r'extendsState<_restageStepWidget$welcome>{',
        'Welcomeget_restageWidget=>widget.original;',
        'int_count=0;',
        'RestageStepValues(built:_restageBuilt,',
        'child:widget.child',
      ]) {
        expect(flat, contains(part));
      }
    });

    test(
      'compiles when its own surface keeps the State its island needs',
      () async {
        const source = """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/first_run.restage.g.dart';

class Tap extends StatelessWidget {
  const Tap({super.key, required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: child);
}

@Screen(id: 'welcome', surface: Surface.onboarding)
final class Welcome extends StatefulWidget {
  const Welcome({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  State<Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<Welcome> {
  int _count = 0;

  void _bump() => setState(() => _count++);

  @override
  Widget build(BuildContext context) => Column(children: [
        Text('\$_count'),
        Tap(onTap: _bump, child: const Text('More')),
      ]);
}

@FlowGraph(id: 'first_run', surface: Surface.onboarding)
const firstRun = FlowDefinition(
  start: Welcome,
  transitions: [Transition.complete(Welcome.next)],
);
""";
        await _generatedPart(source, 'first_run', warningFree: true);
      },
    );

    test(
      'compiles when its own surface keeps the State a value needs',
      () async {
        const source = """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/first_run.restage.g.dart';

@Screen(id: 'welcome', surface: Surface.onboarding)
final class Welcome extends StatefulWidget {
  const Welcome({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  State<Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<Welcome> {
  int _count = 0;

  String _label() {
    final count = _count;
    return 'Seen \$count times';
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(_label()),
        TextButton(
          onPressed: () => setState(() => _count++),
          child: const Text('More'),
        ),
      ]);
}

@FlowGraph(id: 'first_run', surface: Surface.onboarding)
const firstRun = FlowDefinition(
  start: Welcome,
  transitions: [Transition.complete(Welcome.next)],
);
""";
        await _generatedPart(source, 'first_run', warningFree: true);
      },
    );

    test(
      'runs the build local its design reads once, as the app writes it',
      () async {
        final part = await _generatedPart(
          step(
            'const Welcome({super.key});',
            'Container(color: dark ? Colors.black : Colors.white), '
                "KeyedSubtree(key: _held, child: const Text('held'))",
            prelude:
                'final dark = Theme.of(context).brightness == '
                'Brightness.dark;',
          ),
          'first_run',
        );
        expect(part, contains(r'restageStepMount$welcome'));
        expect('final dark ='.allMatches(part).length, 1);
        final flat = part.replaceAll(RegExp(r'\s+'), ' ');
        expect(
          flat,
          contains(
            'return (() { final dark = Theme.of(context).brightness == '
            'Brightness.dark; return _restageDesign( Column( children: [ '
            'Container(color: dark ? Colors.black : Colors.white),',
          ),
        );
      },
    );

    test('is refused when its flow gets no generated widget', () async {
      await _generatedPart(
        step(
          'const Welcome({super.key, required this.title});\n'
              'final String title;',
          'Text(title.toUpperCase())',
          combinator: ' hide RestageFlowGraph',
        ),
        'first_run',
        refused: (errors) {
          final found = errors.map(_issueMessage).toList();
          expect(
            found,
            contains(
              "Restage can't generate the widget for flow `firstRun`. Try "
              'importing `package:restage/restage.dart` without `show` or '
              '`hide` in lib/first_run.dart.',
            ),
          );
          found.forEach(_expectReadable);
        },
      );
    });

    test('is refused when its flow cannot refer to its mount', () async {
      await _generatedPart(
        """
import 'package:restage/restage.dart';
import 'welcome.dart' show Welcome;

part 'restage.generated/first_run.restage.g.dart';

@FlowGraph(id: 'first_run', surface: Surface.onboarding)
const firstRun = FlowDefinition(
  start: Welcome,
  transitions: [Transition.complete(Welcome.next)],
);
""",
        'first_run',
        otherFiles: {
          'apps_examples|lib/welcome.dart': step(
            'const Welcome({super.key, required this.title});\n'
                'final String title;',
            'Text(title.toUpperCase())',
            flow: false,
          ),
        },
        refused: (errors) {
          final found = errors.map(_issueMessage).toList();
          expect(
            found,
            contains(
              "`FirstRunSurface` can't refer to the generated code for "
              'step `Welcome`. Try importing the library that declares '
              '`Welcome` in the library that declares the flow.',
            ),
          );
          found.forEach(_expectReadable);
        },
      );
    });
  });

  group('a helper from another library', () {
    const helpers = {
      'apps_examples|lib/palette.dart': """
import 'package:flutter/widgets.dart';

class Palette extends InheritedWidget {
  const Palette({super.key, required super.child, required this.ink});
  final Color ink;
  static Palette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Palette>()!;
  @override
  bool updateShouldNotify(Palette old) => ink != old.ink;
}
""",
      'apps_examples|lib/leaf.dart': """
import 'package:flutter/widgets.dart';
import 'palette.dart';

Color leafInk(BuildContext context) => Palette.of(context).ink;

Widget leafArt(BuildContext context) =>
    ColoredBox(color: Palette.of(context).ink);
""",
    };

    String screen(String body) =>
        """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'leaf.dart';

part 'restage.generated/leafy.restage.g.dart';

@Screen(id: 'leafy', surface: Surface.onboarding)
final class Leafy extends StatelessWidget {
  const Leafy({super.key});
  @override
  Widget build(BuildContext context) => $body;
}
""";

    test('is evaluated as the call the screen wrote', () async {
      final generated = await _generatedPart(
        screen('ColoredBox(color: leafInk(context))'),
        'leafy',
        otherFiles: helpers,
      );
      expect(
        generated.replaceAll(RegExp(r'\s+'), ' '),
        contains(
          "_restageRecording.native( '_hf6b1c00000', "
          "leafInk(context), type: 'flutter.Color', nullable: false, )",
        ),
      );
    });

    test(
      'that builds a widget the screen cannot name renders from the app',
      () async {
        final generated = await _generatedPart(
          screen('Center(child: leafArt(context))'),
          'leafy',
          otherFiles: helpers,
        );
        final flat = generated.replaceAll(RegExp(r'\s+'), ' ');
        expect(flat, contains(r'Widget _restageIsland$leafy_leafArt_0('));
        expect(flat, contains('leafArt(context)'));
      },
    );
  });

  test('refuses an app-only value when the screen has no mount', () async {
    const source = """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/plain.restage.g.dart';

class Palette extends InheritedWidget {
  const Palette({super.key, required super.child, required this.ink});
  final Color ink;
  static Palette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Palette>()!;
  @override
  bool updateShouldNotify(Palette old) => ink != old.ink;
}

@Screen(id: 'plain', surface: Surface.onboarding)
final class Plain extends StatelessWidget {
  const Plain({super.key, this.resolver = 'local'});
  final String resolver;
  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Palette.of(context).ink);
}
""";
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final records = <LogRecord>[];
    await testBuilders(
      [
        restageSourceRosterBuilder(
          const BuilderOptions({'bundled_runtime': true}, isRoot: true),
        ),
        userCatalogJsonBuilder(BuilderOptions.empty),
        restagePackageSurfaceCompilerBuilder(
          const BuilderOptions({'bundled_runtime': true}, isRoot: true),
        ),
      ],
      {'apps_examples|lib/plain.dart': source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
      onLog: records.add,
    );
    expect(
      records.map((record) => record.message).join('\n'),
      contains(
        "`Palette.of(context).ink` (lib/plain.dart:21:25) runs app code, "
        'which needs the generated `PlainSurface`, and Restage didn\'t '
        "generate it because `Plain`'s constructor parameter `resolver` "
        'uses a name the generated code needs.',
      ),
    );
  });

  test(
    'compiles colocated explicit paywalls without a generated part',
    () async {
      const paywalls = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall(id: 'upgrade_offer')
final class FirstOffer extends StatelessWidget {
  const FirstOffer({super.key});

  @override
  Widget build(BuildContext context) => const Text('Upgrade');
}

@Paywall(id: 'retention_offer')
final class SecondOffer extends StatelessWidget {
  const SecondOffer({super.key});

  @override
  Widget build(BuildContext context) => const Text('Stay');
}
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        const <String, String>{
          'apps_examples|lib/features/commerce/offers.dart': paywalls,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final bundle = _readBundle(readerWriter);
      expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
      expect(
        bundle.manifest!.publications
            .map((entry) => entry.publication.slug)
            .toList(),
        orderedEquals(['retention_offer', 'upgrade_offer']),
      );
      expect(
        bundle.ownedOutputs.keys.where((path) => path.endsWith('.g.dart')),
        isEmpty,
      );
      expect(
        bundle.artifacts.keys,
        containsAll(<String>[
          'assets/paywalls/retention_offer.rfw',
          'assets/paywalls/upgrade_offer.rfw',
        ]),
      );
    },
  );

  test(
    'lowers canonical paywall navigation through roster-owned identities',
    () async {
      const entry = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../relocated/offer.dart';

@Paywall()
final class EntryPaywall extends StatelessWidget {
  const EntryPaywall({super.key});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ElevatedButton(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const PublishedOffer(),
          ),
        ),
        child: const Text('Choose'),
      ),
      ElevatedButton(
        onPressed: paywallEvent('skip'),
        child: const Text('Skip'),
      ),
    ],
  );
}
''';
      const relocated = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall(id: 'published_offer')
final class PublishedOffer extends StatelessWidget {
  const PublishedOffer({super.key});

  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: () => Navigator.pop(context),
    child: const Text('Back'),
  );
}
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        const <String, String>{
          'apps_examples|lib/paywalls/entry.dart': entry,
          'apps_examples|lib/relocated/offer.dart': relocated,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final bundle = _readBundle(readerWriter);
      expect(
        bundle.manifest!.publications
            .map((entry) => entry.publication.slug)
            .toList(),
        ['entry'],
        reason: 'the pushed adapter is part of the entry flow closure only',
      );
      expect(
        bundle.ownedOutputs.keys,
        containsAll(<String>{
          'assets/paywalls/entry.rfw',
          'assets/paywalls/entry.capability.json',
        }),
        reason: 'a navigation paywall retains its specialized standalone pair',
      );
      expect(
        bundle.artifacts.keys,
        isNot(
          contains(
            'assets/paywalls/entry.rfw',
          ),
        ),
        reason: 'the standalone pair is not part of the selected flow closure',
      );
      final navigationPlan =
          jsonDecode(
                utf8.decode(
                  bundle.ownedOutputs['assets/paywalls/entry.navplan.json']!,
                ),
              )
              as Map<String, Object?>;
      expect(navigationPlan['entryId'], 'entry');
      expect(
        (navigationPlan['transitions']! as List<Object?>).single,
        <String, Object?>{
          'event': 'restageNav0',
          'pushedId': 'published_offer',
        },
      );
      final document = FlowDocumentCodec.decodeJson(
        utf8.decode(bundle.artifacts['assets/paywalls/entry.flow.json']!),
      );
      expect(document.screenArtifacts, contains('paywall_published_offer'));
    },
  );

  test('rejects an orphan adapter-only canonical paywall', () async {
    const orphan = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall()
final class OrphanPaywall extends StatelessWidget {
  const OrphanPaywall({super.key});

  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: () => Navigator.pop(context),
    child: const Text('Back'),
  );
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/paywalls/orphan.dart': orphan,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains(
        'Adapter-only paywall orphan is not referenced by a generated '
        'paywall flow closure.',
      ),
    );
  });

  test('a screen reached only through a re-export does not resolve', () async {
    // Documents a real limitation, found while asking whether the handle
    // spelling weakened cross-library resolution. It did not — but neither
    // spelling handles a barrel: screen discovery walks the flow's DIRECT
    // imports, so a screen re-exported through another library is never a
    // candidate and the build fails with `found 0`.
    //
    // Asserted as current behaviour rather than left as a passing-looking
    // gap. It fails loudly, which is the right failure; it is the diagnostic
    // that is unhelpful, since nothing tells the author a barrel is the
    // problem.
    const screen = """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
part 'restage.generated/welcome.restage.g.dart';

@Screen()
final class Welcome extends StatelessWidget {
  const Welcome({super.key});
  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Welcome');
}
""";
    const barrel = "export 'welcome.dart';";
    const flow = """
import 'package:restage/restage.dart';
import '../shared/barrel.dart';
part 'restage.generated/complex.restage.g.dart';

@FlowGraph(surface: Surface.general)
final class Complex extends RestageFlow {
  const Complex();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: welcomeRef,
      states: [
        screen(welcomeRef).on(Welcome.finish).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
""";
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/shared/welcome.dart': screen,
        'apps_examples|lib/shared/barrel.dart': barrel,
        'apps_examples|lib/journeys/complex.dart': flow,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('must resolve through one analyzer-authored library'),
      reason:
          'the limitation must stay loud; if this starts passing, '
          're-exports became supported and this pin should be retired',
    );
  });

  test('a same-named screen in another library does not capture a modern '
      'handle reference', () async {
    // Screen references match by CLASS NAME, so two classes both called
    // `Welcome` are both candidates and only the owning library separates
    // them. The deprecated holder spelling got that discrimination from its
    // `ClassElement`; the 2.0 handle is a top-level variable with none, so it
    // carries its library identifier instead.
    //
    // This is the modern `@Screen()` + `@FlowGraph` path, which resolves
    // through this compiler — not the legacy map lookup.
    //
    // Measured, because the obvious reading is wrong: deleting the
    // `libraryIdentifier` branch does NOT fail this test. Resolution then
    // falls through to `_isImportedScreen`, which admits a screen only from
    // the flow's own library or one it actually imports — so the decoy is
    // excluded either way. Two independent mechanisms give the same answer,
    // and the newer one is defensive rather than load-bearing. This test
    // guards the OUTCOME (the right screen wins), not either mechanism.
    const screen = """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
part 'restage.generated/welcome.restage.g.dart';

@Screen()
final class Welcome extends StatelessWidget {
  const Welcome({super.key});
  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Welcome');
}
""";
    // Same CLASS NAME, different library and a distinct id, never imported by
    // the flow. A distinct id matters: two `@Screen()` classes in same-named
    // files derive the same id and the build refuses them as a duplicate
    // identity before resolution runs — so that case cannot reach the
    // disambiguation at all. This one can: both declare `Welcome`, so both
    // carry `WelcomeDescriptor` as their descriptor name and both generate a
    // top-level `welcomeRef` in their own library.
    const decoy = """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
part 'restage.generated/sidebar.restage.g.dart';

@Screen()
final class Welcome extends StatelessWidget {
  const Welcome({super.key});
  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Decoy');
}
""";
    const flow = """
import 'package:restage/restage.dart';
import '../shared/welcome.dart';
part 'restage.generated/complex.restage.g.dart';

@FlowGraph(surface: Surface.general)
final class Complex extends RestageFlow {
  const Complex();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: welcomeRef,
      states: [
        screen(welcomeRef).on(Welcome.finish).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
""";
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/shared/welcome.dart': screen,
        'apps_examples|lib/decoy/sidebar.dart': decoy,
        'apps_examples|lib/journeys/complex.dart': flow,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(
      result.succeeded,
      isTrue,
      reason:
          'a same-named screen the flow never imports must not make the '
          'reference ambiguous:\n${result.errors.join('\n')}',
    );
    expect(
      result.errors.join('\n'),
      isNot(contains('must resolve through one analyzer-authored library')),
    );
  });

  test('publishes a canonical class-shaped advanced flow', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
part 'restage.generated/welcome.restage.g.dart';

@Screen()
final class Welcome extends StatelessWidget {
  const Welcome({super.key});
  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Welcome');
}
''';
    const flow = '''
import 'package:restage/restage.dart';
import '../shared/welcome.dart';
part 'restage.generated/complex.restage.g.dart';

@FlowGraph(surface: Surface.general)
final class Complex extends RestageFlow {
  const Complex();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: welcomeRef,
      states: [
        screen(welcomeRef).on(Welcome.finish).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/shared/welcome.dart': screen,
        'apps_examples|lib/journeys/complex.dart': flow,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
    expect(
      bundle.manifest!.publications.single.publication.slug,
      'complex',
    );
    expect(
      utf8.decode(bundle.artifacts['assets/general/flows/complex.flow.json']!),
      contains('"flow":"complex"'),
    );
    expect(
      utf8.decode(
        bundle
            .ownedOutputs['lib/journeys/restage.generated/complex.restage.g.dart']!,
      ),
      contains('SurfaceFlowRef<ComplexResult>'),
    );
  });

  test('adapts a legacy-only package as borrowed exact artifacts', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
part 'restage.generated/welcome.restage.g.dart';

@ScreenSource(id: 'welcome', version: 1, minClient: 1)
final class Welcome extends StatelessWidget {
  const Welcome({super.key});
  static const finish = OnboardingEvent<String>('finish');

  @override
  Widget build(BuildContext context) => const Text('Welcome');
}
''';
    const flow = '''
import 'package:restage/restage.dart';
import '../screens/welcome.dart';
part 'restage.generated/welcome_flow.restage.g.dart';

@FlowSource(id: 'welcome_flow', version: 1, minClient: 1)
final class WelcomeFlow extends RestageFlow {
  const WelcomeFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: welcomeRef,
      states: [
        screen(welcomeRef).on(Welcome.finish).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilders(
      [
        onboardingScreenBuilder(BuilderOptions.empty),
        onboardingFlowBuilder(BuilderOptions.empty),
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      ],
      const <String, String>{
        'apps_examples|lib/onboarding/screens/welcome.dart': screen,
        'apps_examples|lib/onboarding/flows/welcome_flow.dart': flow,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
    expect(bundle.artifacts, isEmpty);
    expect(
      bundle.borrowedArtifacts.keys,
      containsAll(<String>['assets/onboarding/flows/welcome_flow.flow.json']),
      reason:
          'the aggregate validates legacy closure bytes without '
          'claiming a second writer',
    );
    expect(
      bundle.manifest!.publications
          .map((entry) => entry.publication.slug)
          .toList(),
      orderedEquals(['welcome', 'welcome_flow']),
    );
    // Legacy standalone screens and precompiled flows are assembled through
    // their own code paths, so their authoring sources need their own proof:
    // a canonical-only assertion elsewhere leaves both blind.
    expect(
      {
        for (final entry in bundle.manifest!.publications)
          entry.publication.slug: entry.sources,
      },
      <String, List<String>>{
        'welcome': ['lib/onboarding/screens/welcome.dart'],
        'welcome_flow': [
          'lib/onboarding/flows/welcome_flow.dart',
          'lib/onboarding/screens/welcome.dart',
        ],
      },
    );

    final legacyScreen = bundle.manifest!.publications.singleWhere(
      (entry) => entry.publication.slug == 'welcome',
    );
    expect(
      legacyScreen.publication.eventContract!.events.single.arguments,
      isA<SurfaceScreenEventValueArguments>().having(
        (arguments) => arguments.shape,
        'shape',
        isA<SurfaceScreenEventScalarShapeV1>().having(
          (shape) => shape.kind,
          'kind',
          SurfaceScreenEventScalarKind.string,
        ),
      ),
      reason: 'typedef-resolved legacy events retain the strict schema',
    );
  });

  test('keeps same-named advanced-flow screens distinct by resolved library '
      'and surface', () async {
    const onboardingScreen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/onboarding_welcome.restage.g.dart';

@Screen(id: 'welcome', surface: Surface.onboarding)
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Onboarding welcome');
}
''';
    const messageScreen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/message_welcome.restage.g.dart';

@Screen(id: 'welcome', surface: Surface.message)
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Message welcome');
}
''';
    const onboardingFlow = '''
import 'package:restage/restage.dart';

import '../screens/onboarding_welcome.dart' as onboarding;

part 'restage.generated/onboarding_advanced.restage.g.dart';

@FlowGraph(id: 'onboarding_advanced', surface: Surface.onboarding)
final class OnboardingAdvanced extends RestageFlow {
  const OnboardingAdvanced();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: onboarding.welcomeRef,
      states: [
        screen(onboarding.welcomeRef)
            .on(onboarding.Welcome.finish)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
    const messageFlow = '''
import 'package:restage/restage.dart';

import '../screens/message_welcome.dart' as message;

part 'restage.generated/message_advanced.restage.g.dart';

@FlowGraph(id: 'message_advanced', surface: Surface.message)
final class MessageAdvanced extends RestageFlow {
  const MessageAdvanced();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: message.welcomeRef,
      states: [
        screen(message.welcomeRef)
            .on(message.Welcome.finish)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/screens/onboarding_welcome.dart': onboardingScreen,
        'apps_examples|lib/screens/message_welcome.dart': messageScreen,
        'apps_examples|lib/flows/onboarding_advanced.dart': onboardingFlow,
        'apps_examples|lib/flows/message_advanced.dart': messageFlow,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    const onboardingBlob = 'assets/onboarding/screens/welcome.rfw';
    const messageBlob = 'assets/message/screens/welcome.rfw';
    final onboardingVariants = variantBytes(bundle.artifacts, onboardingBlob);
    final messageVariants = variantBytes(bundle.artifacts, messageBlob);
    expect(onboardingVariants, isNotEmpty);
    expect(messageVariants, isNotEmpty);
    expect(
      onboardingVariants.intersection(messageVariants),
      isEmpty,
      reason: 'a same-named screen in two surfaces must not share bytes',
    );
    final onboardingDocument = FlowDocumentCodec.decodeJson(
      utf8.decode(
        bundle
            .artifacts['assets/onboarding/flows/onboarding_advanced.flow.json']!,
      ),
    );
    final messageDocument = FlowDocumentCodec.decodeJson(
      utf8.decode(
        bundle.artifacts['assets/message/flows/message_advanced.flow.json']!,
      ),
    );
    expect(onboardingDocument.screenArtifacts.keys, orderedEquals(['welcome']));
    expect(messageDocument.screenArtifacts.keys, orderedEquals(['welcome']));
    expect(
      onboardingDocument.screenArtifacts['welcome']!.contentHash,
      isNot(equals(messageDocument.screenArtifacts['welcome']!.contentHash)),
    );
  });

  test('admits canonical libraries under generated while excluding generated '
      'and story Dart', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/notice.restage.g.dart';

@Screen(id: 'generated_notice', surface: Surface.general)
final class GeneratedNotice extends StatelessWidget {
  const GeneratedNotice({super.key});

  @override
  Widget build(BuildContext context) => const Text('Retained authored source');
}
''';
    const ignored = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Screen(id: 'ignored', surface: Surface.general)
final class Ignored extends StatelessWidget {
  const Ignored({super.key});

  @override
  Widget build(BuildContext context) => const Text('This must not be scanned');
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/generated/notice.dart': screen,
        'apps_examples|lib/generated/ignored.g.dart': ignored,
        'apps_examples|lib/generated/ignored.stories.dart': ignored,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    expect(
      bundle.manifest!.publications
          .map((entry) => entry.publication.slug)
          .toList(),
      orderedEquals(['generated_notice']),
    );
    expect(
      bundle.artifacts,
      contains('assets/general/screens/generated_notice.rfw'),
    );
    expect(
      bundle.artifacts,
      isNot(contains('assets/general/screens/ignored.rfw')),
    );
  });

  test('propagates authored standalone minClient above a derived floor', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/minimum_notice.restage.g.dart';

@Screen(id: 'minimum_notice', surface: Surface.general, minClient: 3)
final class MinimumNotice extends StatelessWidget {
  const MinimumNotice({super.key});

  @override
  Widget build(BuildContext context) => const Text('Minimum client');
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/features/minimum_notice.dart': screen,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    final publication = bundle.manifest!.publications.single.publication;
    expect(publication.capabilities!.builtInFloor, 3);
    final sidecar =
        jsonDecode(
              utf8.decode(
                bundle
                    .artifacts['assets/general/screens/minimum_notice.capability.json']!,
              ),
            )
            as Map<String, Object?>;
    expect((sidecar['manifest']! as Map<Object?, Object?>)['builtInFloor'], 3);
    final generatedPart = utf8.decode(
      bundle
          .ownedOutputs['lib/features/restage.generated/minimum_notice.restage.g.dart']!,
    );
    expect(generatedPart, contains('builtInFloor: 3'));
    // A categorized screen carries its authored floor on the handle's
    // provenance, not on an in-flow neutral reference — that reference is no
    // longer generated for a categorized screen. Same authored value, read
    // where it now lives.
    expect(generatedPart, contains('builtInFloor: 3'));
  });

  test(
    'propagates authored embedded-screen minClient into the flow document',
    () async {
      const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/minimum_notice.restage.g.dart';

@Screen(id: 'minimum_notice', minClient: 3)
final class MinimumNotice extends StatelessWidget {
  const MinimumNotice({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Minimum client');
}
''';
      const flow = '''
import 'package:restage/restage.dart';

import '../screens/minimum_notice.dart' as notice;

part 'restage.generated/minimum_flow.restage.g.dart';

@FlowGraph(id: 'minimum_flow', surface: Surface.general, minClient: 3)
final class MinimumFlow extends RestageFlow {
  const MinimumFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: notice.minimumNoticeRef,
      states: [
        screen(notice.minimumNoticeRef)
            .on(notice.MinimumNotice.finish)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        const <String, String>{
          'apps_examples|lib/screens/minimum_notice.dart': screen,
          'apps_examples|lib/flows/minimum_flow.dart': flow,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final bundle = _readBundle(readerWriter);
      final document = FlowDocumentCodec.decodeJson(
        utf8.decode(
          bundle.artifacts['assets/general/flows/minimum_flow.flow.json']!,
        ),
      );
      expect(document.minClient, 3);
      expect(document.screenArtifacts['minimum_notice']!.minClient, 3);
      final sidecar =
          jsonDecode(
                utf8.decode(
                  bundle
                      .artifacts['assets/general/screens/minimum_notice.capability.json']!,
                ),
              )
              as Map<String, Object?>;
      expect(
        (sidecar['manifest']! as Map<Object?, Object?>)['builtInFloor'],
        3,
      );
    },
  );

  test('scheduler accepts a flat flow whose aggregate floor exceeds its '
      'authored screen reference floor', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/derived_floor.restage.g.dart';

@Screen(id: 'derived_floor', minClient: 1)
final class DerivedFloor extends StatelessWidget {
  const DerivedFloor({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) =>
      const Offstage(child: Text('Derived floor'));
}
''';
    const flatFlow = '''
import 'package:restage/restage.dart';

import '../screens/derived_floor.dart';

part 'restage.generated/flat_floor.restage.g.dart';

@FlowGraph(id: 'flat_floor', surface: Surface.general, minClient: 1)
const flatFloor = FlowDefinition(
  start: DerivedFloor,
  transitions: [Transition.complete(DerivedFloor.next)],
);
''';
    const advancedFlow = '''
import 'package:restage/restage.dart';

import '../screens/derived_floor.dart';

part 'restage.generated/advanced_trigger.restage.g.dart';

@FlowGraph(id: 'advanced_trigger', surface: Surface.general, minClient: 5)
final class AdvancedTrigger extends RestageFlow {
  const AdvancedTrigger();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: derivedFloorRef,
      states: [
        screen(derivedFloorRef)
            .on(DerivedFloor.next)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/screens/derived_floor.dart': screen,
        'apps_examples|lib/flows/flat_floor.dart': flatFlow,
        'apps_examples|lib/flows/advanced_trigger.dart': advancedFlow,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    final sidecar =
        jsonDecode(
              utf8.decode(
                base64Decode(
                  variantBytes(
                    bundle.artifacts,
                    'assets/general/screens/derived_floor.capability.json',
                  ).first,
                ),
              ),
            )
            as Map<String, Object?>;
    final effectiveFloor =
        (sidecar['manifest']! as Map<Object?, Object?>)['builtInFloor']! as int;
    expect(effectiveFloor, greaterThan(1));
    final flatDocument = FlowDocumentCodec.decodeJson(
      utf8.decode(
        bundle.artifacts['assets/general/flows/flat_floor.flow.json']!,
      ),
    );
    expect(flatDocument.minClient, effectiveFloor);
    expect(
      flatDocument.screenArtifacts['derived_floor']!.minClient,
      effectiveFloor,
    );
    expect(
      bundle.manifest!.publications
          .map((entry) => entry.publication.slug)
          .toList(),
      orderedEquals(['advanced_trigger', 'flat_floor']),
    );
    expect(
      bundle.artifacts,
      contains('assets/general/flows/flat_floor.flow.json'),
    );
  });

  test('advanced parent consumes an arbitrary-path canonical flat child '
      'document by normalized identity', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/shared_entry.restage.g.dart';

@Screen(id: 'shared_entry')
final class SharedEntry extends StatelessWidget {
  const SharedEntry({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => const Text('Shared entry');
}
''';
    const child = '''
import 'package:restage/restage.dart';

import '../ui/shared_entry.dart';

part 'restage.generated/flat_leaf.restage.g.dart';

@FlowGraph(id: 'flat_leaf', surface: Surface.general)
const flatLeaf = FlowDefinition(
  start: SharedEntry,
  transitions: [Transition.complete(SharedEntry.next)],
);
''';
    const parent = '''
import 'package:restage/restage.dart';

import '../ui/shared_entry.dart';

part 'restage.generated/flat_parent.restage.g.dart';

Map<String, Object?> _decodeFlatLeaf(Map<String, Object?> result) => result;

const flatLeafRef = SurfaceFlowRef<Map<String, Object?>>(
  id: 'flat_leaf',
  version: 1,
  minClient: 1,
  surface: Surface.general,
  decodeResult: _decodeFlatLeaf,
);

@FlowGraph(id: 'flat_parent', surface: Surface.general)
final class FlatParent extends RestageFlow {
  const FlatParent();

  @override
  FlowDef buildFlow() {
    final child = flowNode('child');
    final done = endState('done');
    return flow(
      initial: sharedEntryRef,
      states: [
        screen(sharedEntryRef).on(SharedEntry.next).goTo(child),
        subFlow(
          child,
          flow: flatLeafRef,
          input: const {},
          onComplete: [
            flowBranch(
              when: const FlowBranchPredicate(fields: {}),
              target: done,
            ),
          ],
          defaultBranch: flowBranchTarget(done),
        ),
        end(done, result: {}),
      ],
    );
  }
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      <String, String>{
        'apps_examples|lib/ui/shared_entry.dart': screen,
        'apps_examples|lib/z_children/flat_leaf.dart': child,
        'apps_examples|lib/z_children/other_leaf.dart': child
            .replaceAll(
              'Surface.general',
              'Surface.onboarding, version: 9',
            )
            .replaceAll(
              'flat_leaf.restage.g.dart',
              'other_leaf.restage.g.dart',
            ),
        'apps_examples|lib/a_parents/flat_parent.dart': parent,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    final childBytes =
        bundle.artifacts['assets/general/flows/flat_leaf.flow.json']!;
    final parentDocument = FlowDocumentCodec.decodeJson(
      utf8.decode(
        bundle.artifacts['assets/general/flows/flat_parent.flow.json']!,
      ),
    );
    final childState = parentDocument.states['child']! as SubFlowState;
    expect(childState.flow, 'flat_leaf');
    expect(childState.contentHash, FlowContentHash.compute(childBytes));
    final generated = utf8.decode(
      bundle
          .ownedOutputs['lib/a_parents/restage.generated/flat_parent.restage.g.dart']!,
    );
    final compiledDocuments = RegExp(r"documentJson:\s*'((?:\\.|[^'\\])*)'")
        .allMatches(generated)
        .map(
          (match) => FlowDocumentCodec.decodeJson(
            match
                .group(1)!
                .replaceAllMapped(
                  RegExp(r'\\(.)'),
                  (escape) => escape.group(1)!,
                ),
          ),
        )
        .toList();
    final compiledChild = compiledDocuments.singleWhere(
      (document) => document.flow == 'flat_leaf',
    );
    final compiledParent = compiledDocuments.singleWhere(
      (document) => document.flow == 'flat_parent',
    );
    expect(compiledChild.version, 1);
    expect(
      (compiledParent.states['child']! as SubFlowState).contentHash,
      FlowContentHash.compute(
        FlowDocumentCodec.encodeCanonicalJson(compiledChild),
      ),
    );
  });

  test('advanced parent consumes an arbitrary-path canonical advanced child '
      'document by normalized identity', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/advanced_entry.restage.g.dart';

@Screen(id: 'advanced_entry')
final class AdvancedEntry extends StatelessWidget {
  const AdvancedEntry({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => const Text('Advanced entry');
}
''';
    const child = '''
import 'package:restage/restage.dart';

import '../ui/advanced_entry.dart';

part 'restage.generated/advanced_leaf.restage.g.dart';

@FlowGraph(id: 'advanced_leaf', surface: Surface.general)
final class AdvancedLeaf extends RestageFlow {
  const AdvancedLeaf();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: advancedEntryRef,
      states: [
        screen(advancedEntryRef)
            .on(AdvancedEntry.next)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
    const parent = '''
import 'package:restage/restage.dart';

import '../ui/advanced_entry.dart';

part 'restage.generated/advanced_parent.restage.g.dart';

Map<String, Object?> _decodeAdvancedLeaf(Map<String, Object?> result) => result;

const advancedLeafRef = SurfaceFlowRef<Map<String, Object?>>(
  id: 'advanced_leaf',
  version: 1,
  minClient: 1,
  surface: Surface.general,
  decodeResult: _decodeAdvancedLeaf,
);

@FlowGraph(id: 'advanced_parent', surface: Surface.general)
final class AdvancedParent extends RestageFlow {
  const AdvancedParent();

  @override
  FlowDef buildFlow() {
    final child = flowNode('child');
    final done = endState('done');
    return flow(
      initial: advancedEntryRef,
      states: [
        screen(advancedEntryRef).on(AdvancedEntry.next).goTo(child),
        subFlow(
          child,
          flow: advancedLeafRef,
          input: const {},
          onComplete: [
            flowBranch(
              when: const FlowBranchPredicate(fields: {}),
              target: done,
            ),
          ],
          defaultBranch: flowBranchTarget(done),
        ),
        end(done, result: {}),
      ],
    );
  }
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/ui/advanced_entry.dart': screen,
        'apps_examples|lib/z_arbitrary/advanced_leaf.dart': child,
        'apps_examples|lib/a_arbitrary/advanced_parent.dart': parent,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    final childBytes =
        bundle.artifacts['assets/general/flows/advanced_leaf.flow.json']!;
    final parentDocument = FlowDocumentCodec.decodeJson(
      utf8.decode(
        bundle.artifacts['assets/general/flows/advanced_parent.flow.json']!,
      ),
    );
    final childState = parentDocument.states['child']! as SubFlowState;
    expect(childState.flow, 'advanced_leaf');
    expect(childState.contentHash, FlowContentHash.compute(childBytes));
  });

  test(
    'rejects a same-id cross-surface child from an advanced parent',
    () async {
      const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/cross_surface_entry.restage.g.dart';

@Screen(id: 'cross_surface_entry')
final class CrossSurfaceEntry extends StatelessWidget {
  const CrossSurfaceEntry({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => const Text('Cross surface entry');
}
''';
      const onboardingChild = '''
import 'package:restage/restage.dart';
import 'shared/cross_surface_entry.dart';
part 'restage.generated/onboarding_child.restage.g.dart';

@FlowGraph(id: 'shared_child', surface: Surface.onboarding)
const onboardingChild = FlowDefinition(
  start: CrossSurfaceEntry,
  transitions: [Transition.complete(CrossSurfaceEntry.next)],
);
''';
      const messageChild = '''
import 'package:restage/restage.dart';
import 'shared/cross_surface_entry.dart';
part 'restage.generated/message_child.restage.g.dart';

@FlowGraph(id: 'shared_child', surface: Surface.message)
const messageChild = FlowDefinition(
  start: CrossSurfaceEntry,
  transitions: [Transition.complete(CrossSurfaceEntry.next)],
);
''';
      const parent = '''
import 'package:restage/restage.dart';
import 'shared/cross_surface_entry.dart';
part 'restage.generated/cross_surface_parent.restage.g.dart';

Map<String, Object?> _decodeChild(Map<String, Object?> result) => result;

const messageChildRef = SurfaceFlowRef<Map<String, Object?>>(
  id: 'shared_child',
  version: 1,
  minClient: 1,
  surface: Surface.message,
  decodeResult: _decodeChild,
);

@FlowGraph(id: 'cross_surface_parent', surface: Surface.onboarding)
final class CrossSurfaceParent extends RestageFlow {
  const CrossSurfaceParent();

  @override
  FlowDef buildFlow() {
    final child = flowNode('child');
    final done = endState('done');
    return flow(
      initial: crossSurfaceEntryRef,
      states: [
        screen(crossSurfaceEntryRef)
            .on(CrossSurfaceEntry.next)
            .goTo(child),
        subFlow(
          child,
          flow: messageChildRef,
          input: const {},
          onComplete: [
            flowBranch(
              when: const FlowBranchPredicate(fields: {}),
              target: done,
            ),
          ],
          defaultBranch: flowBranchTarget(done),
        ),
        end(done, result: {}),
      ],
    );
  }
}
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        const <String, String>{
          'apps_examples|lib/shared/cross_surface_entry.dart': screen,
          'apps_examples|lib/onboarding_child.dart': onboardingChild,
          'apps_examples|lib/message_child.dart': messageChild,
          'apps_examples|lib/cross_surface_parent.dart': parent,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        contains(
          'Subflow child message/shared_child cannot be included in a '
          'onboarding flow.',
        ),
      );
    },
  );

  test('canonical class flow embeds an arbitrary-path roster paywall exact '
      'aggregate artifact', () async {
    const paywall = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall(id: 'premium_offer')
final class PremiumOffer extends StatelessWidget {
  const PremiumOffer({super.key});

  static const complete = SurfaceEvent<void>('complete');

  @override
  Widget build(BuildContext context) => const Text('Premium offer');
}
''';
    const flow = '''
import 'package:restage/restage.dart';

import '../arbitrary/commerce/premium_offer.dart';

part 'restage.generated/offer_gate.restage.g.dart';

@FlowGraph(id: 'offer_gate', surface: Surface.general)
final class OfferGate extends RestageFlow {
  const OfferGate();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: paywallScreen('premium_offer'),
      states: [
        screen(paywallScreen('premium_offer'))
            .on(PremiumOffer.complete)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/arbitrary/commerce/premium_offer.dart': paywall,
        'apps_examples|lib/journeys/offer_gate.dart': flow,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    const adapterBlobPath = 'assets/paywalls/screens/paywall_premium_offer.rfw';
    const adapterSidecarPath =
        'assets/paywalls/screens/paywall_premium_offer.capability.json';
    final adapterBlob = bundle.artifacts[adapterBlobPath]!;
    final sidecar =
        jsonDecode(
              utf8.decode(bundle.artifacts[adapterSidecarPath]!),
            )
            as Map<String, Object?>;
    final builtInFloor =
        (sidecar['manifest']! as Map<Object?, Object?>)['builtInFloor']! as int;
    final document = FlowDocumentCodec.decodeJson(
      utf8.decode(
        bundle.artifacts['assets/general/flows/offer_gate.flow.json']!,
      ),
    );
    final embedded = document.screenArtifacts['paywall_premium_offer']!;
    expect(embedded.path, 'paywall_premium_offer.rfw');
    expect(embedded.version, 1);
    expect(embedded.minClient, builtInFloor);
    expect(embedded.contentHash, FlowContentHash.compute(adapterBlob));
    expect(document.minClient, greaterThanOrEqualTo(embedded.minClient));
  });
}

const _policyProbeSource = '';

final _alternateMeasurementPolicy =
    MeasurementCompilerPolicyInput.fromBuilderOptions(
      const BuilderOptions({
        kMeasurementMinimumClientOption: 2,
        kMeasurementPrivacyPolicyRevisionOption: 'privacy.test-v2',
        kMeasurementCollectionBudgetRevisionOption: 'budget.test-v2',
      }),
    );

/// The message of a build error, without its code and location prefix.
String _issueMessage(String error) =>
    error.split('\n').first.replaceFirst(RegExp(r'^\[\w+\] [^ ]*: '), '');

/// Every text a generated part shows a developer: debug value labels,
/// native value labels and the messages its island lookups throw.
List<String> _readableTextsOf(String part) {
  const literal = r"""('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")""";
  String text(String source) => source
      .substring(1, source.length - 1)
      .replaceAll(r"\'", "'")
      .replaceAll(r'\"', '"')
      .replaceAll(r'\$', r'$');
  final labels =
      RegExp(
            r"labels: const bool\.fromEnvironment\('dart\.vm\.product'\)"
            r'\s*\?\s*const <String, String>\{\}\s*:\s*const <String, String>\{([^}]*)\}',
          )
          .allMatches(part)
          .expand(
            (match) => RegExp(
              '$literal\\s*:\\s*$literal',
            ).allMatches(match[1]!).map((entry) => text(entry[2]!)),
          );
  return [
    for (final match in RegExp(
      r"'dart\.vm\.product'\)\s*\?\s*''\s*:\s*" + literal,
    ).allMatches(part))
      text(match[1]!),
    ...labels,
    for (final match in RegExp(
      r'\.build\(\s*' + literal + r',\s*' + literal,
    ).allMatches(part))
      text(match[2]!),
  ];
}

/// Fails when [message] shows a developer anything they did not write.
void _expectReadable(String message) {
  // Source a message quotes in backticks is the developer's own code.
  final prose = message.replaceAll(RegExp('`[^`]*`'), '``');
  // A quoted app name may be one Restage reserves, which the message names.
  for (final unreadable in [
    RegExp(r'(?<![=!]=\s)(?<!\?\?\s)\bnull\b'),
    RegExp(r'restage[A-Z_$]'),
    // A literal in the developer's own code may be hex; a leaked hash is not.
    RegExp('0x[0-9a-fA-F]+'),
  ]) {
    expect(prose, isNot(contains(unreadable)), reason: message);
  }
  for (final unreadable in [
    RegExp('_h[0-9a-f]{6,}'),
    RegExp('Instance of'),
    RegExp('[\u0000-\u0006]'),
    RegExp(r'(^|[\s(])/[A-Za-z]'),
    RegExp('file:///'),
    RegExp(r'offset \d'),
    RegExp('<unknown>'),
    RegExp(r'\bmount\b'),
    RegExp(r'\w+\.\w+(>\w+)*/[\w.]+#\d+'),
    RegExp(r'\b[A-Z]\w*(Expression|Invocation)\b'),
  ]) {
    expect(message, isNot(contains(unreadable)), reason: message);
  }
}

/// Expects [text] to contain [template], where `<wireKey>` stands for a wire key.
void _expectTemplate(String text, String template) {
  final pattern = RegExp(
    RegExp.escape(template).replaceAll('<wireKey>', r'_h[0-9a-f]{10}'),
  );
  expect(pattern.hasMatch(text), isTrue, reason: 'Missing: $template');
}

/// Calls to [name] the part writes as code: no string literals, and no
/// island previews, which never run in a build.
int _callsIn(String part, String name) => RegExp("(?<!['\\w])$name\\(")
    .allMatches(
      part
          .replaceAll(RegExp(r"'''[\s\S]*?'''"), "''")
          .replaceAll(RegExp(r"'(?:[^'\\\n]|\\.)*'"), "''")
          .replaceAll(
            RegExp(r'Widget restagePreview\$\w+\([^)]*\)\s*=>[^;]*;'),
            '',
          ),
    )
    .length;

Future<String> _generatedPart(
  String source,
  String name, {
  Map<String, String> otherFiles = const {},
  int? expectedFloor,
  void Function(String text)? paywallText,
  void Function(List<String> errors)? refused,
  void Function(List<String> warnings)? warned,
  void Function(List<String> logs)? logged,
  void Function(RestageSurfacePublicationBundle bundle)? handoff,
  void Function(Catalog catalog)? renderCatalog,
  bool warningFree = false,
  bool expectPart = true,
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final warnings = <String>[];
  final logs = <String>[];
  final result = await testBuilders(
    [
      restageSourceRosterBuilder(
        const BuilderOptions({'bundled_runtime': true}, isRoot: true),
      ),
      userCatalogJsonBuilder(BuilderOptions.empty),
      restagePackageSurfaceCompilerBuilder(
        const BuilderOptions({'bundled_runtime': true}, isRoot: true),
      ),
      restageGeneratedDartBuilder(
        const BuilderOptions({'bundled_runtime': true}),
      ),
      restageOutputsBuilder(
        const BuilderOptions({'bundled_runtime': true}),
      ),
      if (renderCatalog != null) const RenderCatalogBuilder(),
    ],
    {'apps_examples|lib/$name.dart': source, ...otherFiles},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) {
      logs.add(record.message);
      if (record.level == Level.WARNING) warnings.add(record.message);
    },
  );
  warned?.call(warnings);
  logged?.call(logs);
  // Every error and warning a developer reads names what they wrote.
  for (final message in [...result.errors.map(_issueMessage), ...warnings]) {
    message.split('\n').forEach(_expectReadable);
  }

  if (refused != null) {
    expect(result.succeeded, isFalse);
    refused(result.errors.toList());
    return '';
  }
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  handoff?.call(_readBundle(readerWriter));
  renderCatalog?.call(
    decodeCatalog(
      readerWriter.testing.readString(
        AssetId('apps_examples', kRenderCatalogPath),
      ),
    ),
  );

  if (!expectPart) return '';
  if (expectedFloor != null) {
    final bytes = _readBundle(
      readerWriter,
    ).artifacts['assets/onboarding/screens/$name.capability.json'];
    expect(bytes, isNotNull);
    final sidecar = CapabilitySidecar.fromJson(
      jsonDecode(utf8.decode(bytes!)) as Map<String, Object?>,
    );
    expect(sidecar.manifest.builtInFloor, expectedFloor);
  }
  final descriptor = readerWriter.testing.readString(
    AssetId(
      'apps_examples',
      'lib/restage.generated/$name.restage.g.dart',
    ),
  );
  expect(descriptor, isNotEmpty);
  if (paywallText != null) {
    final text = _readBundle(
      readerWriter,
    ).ownedOutputs['assets/paywalls/$name.rfwtxt'];
    paywallText(utf8.decode(text!));
  }
  await _expectAnalyzesClean({
    'apps_examples|lib/$name.dart': source,
    'apps_examples|lib/restage.generated/$name.restage.g.dart': descriptor,
    ...otherFiles,
  }, warningFree: warningFree);
  return descriptor;
}

Future<void> _expectAnalyzesClean(
  Map<String, String> sources, {
  bool warningFree = false,
}) async {
  final entry = sources.keys.first;
  await resolveWorkspaceSources(
    sources,
    (resolver) async {
      final library = await resolver.libraryFor(AssetId.parse(entry));
      final resolved = await library.session.getResolvedLibraryByElement(
        library,
      );
      if (resolved is! ResolvedLibraryResult) {
        throw StateError('$entry did not resolve.');
      }
      final errors = [
        for (final unit in resolved.units)
          for (final diagnostic in unit.diagnostics)
            if (diagnostic.severity == Severity.error ||
                warningFree && diagnostic.severity == Severity.warning)
              '${unit.path}: ${diagnostic.message}',
      ];
      expect(errors, isEmpty, reason: 'the generated part must analyze clean');
    },
    resolverFor: entry,
    rootPackage: 'apps_examples',
  );
}

Future<Map<String, List<TrackedPackageSurfaceCompilation>>> _runPolicyProbe(
  Map<String, List<MeasurementCompilerPolicyInput>> policies,
) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final compilations = <String, List<TrackedPackageSurfaceCompilation>>{};
  final result = await testBuilder(
    _PolicyProbe(policies, compilations),
    {
      for (final package in policies.keys)
        '$package|lib/measurement_policy_probe.dart': _policyProbeSource,
    },
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  return compilations;
}

final class _PolicyProbe implements Builder {
  const _PolicyProbe(this._policies, this._compilations);

  final Map<String, List<MeasurementCompilerPolicyInput>> _policies;
  final Map<String, List<TrackedPackageSurfaceCompilation>> _compilations;

  @override
  Map<String, List<String>> get buildExtensions => const {
    r'$package$': ['lib/measurement_policy_probe.txt'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    final compilations = <TrackedPackageSurfaceCompilation>[];
    _compilations[package] = compilations;
    for (final policy in _policies[package]!) {
      compilations.add(
        await compileTrackedPackageSurfaces(
          buildStep,
          builderKey:
              'restage_codegen:measurement_policy_${compilations.length}',
          measurementPolicy: policy,
        ),
      );
    }
    await buildStep.writeAsString(
      AssetId(package, 'lib/measurement_policy_probe.txt'),
      '',
    );
  }
}

RestageSurfacePublicationBundle _readBundle(TestReaderWriter readerWriter) =>
    RestageSurfacePublicationBundle.fromJson(
      jsonDecode(
        readerWriter.testing.readString(
          AssetId(
            'apps_examples',
            kRestageSurfacePublicationCompilerBundlePath,
          ),
        ),
      ),
    );

/// The declarative text one emitted blob decodes to.
String _declarativeText(List<int> blob) =>
    fmt.decodeLibraryBlob(Uint8List.fromList(blob)).toString();

/// [source] with Measurement route identity elided.
///
/// Two publications of one screen agree on everything a client renders, so
/// eliding only the identity keeps the rest of the comparison exact.
String _withoutMeasurementIdentity(String source) => source
    .replaceAll(RegExp(r'carriers: \[[^\]]*\]'), 'carriers: [...]')
    .replaceAll(RegExp(r'pointTokens: \[[^\]]*\]'), 'pointTokens: [...]');

/// The host contract the generated placement definition of [declaration] in
/// [part] declares.
SurfaceHostContractV1 _hostContractOf(String part, String declaration) {
  final start = part.indexOf('hostContractJson: ', part.indexOf(declaration));
  var depth = 0;
  var end = part.indexOf('{', start);
  final open = end;
  do {
    if (part[end] == '{' || part[end] == '[') depth++;
    if (part[end] == '}' || part[end] == ']') depth--;
    end++;
  } while (depth > 0);
  final json = part
      .substring(open, end)
      .replaceAll('<String, Object?>', '')
      .replaceAll('<Object?>', '')
      .replaceAll("'", '"')
      .replaceAllMapped(RegExp(r',(\s*[}\]])'), (m) => m[1]!);
  return SurfaceHostContractV1.fromJson(jsonDecode(json));
}
