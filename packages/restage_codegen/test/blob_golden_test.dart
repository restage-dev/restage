import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Whole-blob byte-goldens for the production codegen pipeline.
///
/// Every other codegen test asserts the emitted `.rfwtxt`/`.rfw` by substring or
/// by decoding the blob and checking a structural shape. None of them pins the
/// *whole* output, so a behaviour-preserving refactor of the translator could
/// move bytes nobody is watching. This test closes that gap: it feeds the real
/// example paywall sources through the **production builder** and asserts the
/// emitted artifacts are byte-identical to a committed golden.
///
/// ## The oracle is the production builder
///
/// The build is driven through `restageCodegenBuilder(BuilderOptions.empty)` —
/// the exact `Builder` the real codegen pass runs — via `build_test`'s
/// `testBuilders`. The translate → emit → parse → validate → encode chain is
/// the production one (`codegen_builder.dart`); this test assembles none of it
/// by hand. So a golden break means the *production* output moved, not a
/// test-assembled approximation.
///
/// ## The corpus
///
/// The six shipping standalone example paywalls in
/// `apps/examples/lib/paywalls/`. Between them they exercise the idiom surface
/// the translator decomposition must hold stable: modal-sheet lowering
/// (`ascend_premium`, `modal_sheet_lowering`,
/// `modal_sheet_lowering_cupertino`), a flat-tree value/gradient surface
/// (`pulse_premium`), and the branded example surfaces (`narrate_membership`,
/// `sentinel_protection`). Each source emits three artifacts the production
/// pass writes: `<id>.rfwtxt`, `<id>.rfw`, and the onboarding-screen
/// `paywall_<id>.rfw` (the distinct `emitRemoteWidgetLibrary` path).
///
/// A second corpus — the `fluent-pro nav-lowered flow byte-goldens` group —
/// covers the screen-navigation idiom (`Navigator.push` → a two-screen flow),
/// the input shape the six do not exercise. See [_navFlowIds].
///
/// ## Goldens + regeneration
///
/// Goldens live in `test/fixtures/goldens/`, self-contained in this package
/// (not coupled to `apps/examples/assets/`). `.rfwtxt` is asserted by string
/// equality (the human-diffable primary signal); `.rfw` and the onboarding blob
/// by byte equality (the wire belt-and-suspenders). Regenerate — only when the
/// output is *intended* to change — with:
///
///   REGEN_CODEGEN_GOLDENS=1 dart test test/blob_golden_test.dart
const _mountPackage = 'apps_examples';
const _examplePackage = 'restage_example';

/// Packages the base [readerWriterWithFilesystemSources] already seeds (with
/// their full source closures); the corpus re-home below skips re-walking them.
/// Notably `flutter`, whose closure is large and already cached by the base.
const _skipPackages = <String>{
  'flutter',
  'sky_engine',
  'restage',
  'restage_core',
  'restage_shared',
  'rfw',
  'rfw_catalog_schema',
  'intl',
};

/// The shipping example paywalls, in a stable order.
const _paywallIds = <String>[
  'ascend_premium',
  'modal_sheet_lowering',
  'modal_sheet_lowering_cupertino',
  'narrate_membership',
  'pulse_premium',
  'sentinel_protection',
];

/// The screen-navigation-lowered example paywall. `fluent_pro` authors a
/// `Navigator.push` to a second `@PaywallSource` (`fluent_pro_choose_plan`).
/// The codegen lowers it to a two-screen flow: the entry `.rfwtxt`/`.rfw`
/// blob, a `.flow.json` navplan sidecar, and the two flow-screen blobs
/// (`paywall_fluent_pro.rfw` + `paywall_fluent_pro_choose_plan.rfw`). The
/// pushed screen's standalone paywall artifact is intentionally suppressed (it
/// renders only as a flow screen). Both sources are seeded and both the per-
/// paywall builder and the navigation-flow builder run, so this group pins the
/// whole navigation-lowering byte surface — the input shape the six-paywall
/// corpus above does not exercise.
const _navFlowIds = <String>['fluent_pro', 'fluent_pro_choose_plan'];

const _goldenDir = 'test/fixtures/goldens';

void main() {
  final regen = Platform.environment['REGEN_CODEGEN_GOLDENS'] == '1';
  late TestBuilderResult result;
  late TestBuilderResult navFlowResult;

  setUpAll(() async {
    final rw = await _seedRealCorpus(_paywallIds);
    final sources = <String, String>{
      for (final id in _paywallIds)
        '$_mountPackage|lib/paywalls/$id.dart': rw.testing
            .readString(AssetId(_mountPackage, 'lib/paywalls/$id.dart')),
    };
    result = await testBuilders(
      [restageCodegenBuilder(BuilderOptions.empty)],
      sources,
      rootPackage: _mountPackage,
      readerWriter: rw,
      flattenOutput: true,
    );

    // The navigation-lowered paywall runs through BOTH the per-paywall builder
    // (the `.rfwtxt`/`.rfw` + flow-screen blobs) and the navigation-flow builder
    // (the `.flow.json` navplan sidecar), over both flow sources.
    final navFlowRw = await _seedRealCorpus(_navFlowIds);
    final navFlowSources = <String, String>{
      for (final id in _navFlowIds)
        '$_mountPackage|lib/paywalls/$id.dart': navFlowRw.testing
            .readString(AssetId(_mountPackage, 'lib/paywalls/$id.dart')),
    };
    navFlowResult = await testBuilders(
      [
        restageCodegenBuilder(BuilderOptions.empty),
        paywallFlowBuilder(BuilderOptions.empty),
      ],
      navFlowSources,
      rootPackage: _mountPackage,
      readerWriter: navFlowRw,
      flattenOutput: true,
    );
  });

  test('the production builder emits all corpus artifacts cleanly', () {
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    expect(result.errors, isEmpty);
    // 8 sources x 4 artifacts (.rfwtxt + .rfw + .capability.json + onboarding
    // paywall_<id>.rfw).
    expect(result.outputs.length, _paywallIds.length * 4);
  });

  group('blob byte-goldens', () {
    for (final id in _paywallIds) {
      test('$id is byte-stable', () {
        final rw = result.readerWriter;
        final rfwtxt = rw.testing
            .readString(AssetId(_mountPackage, 'assets/paywalls/$id.rfwtxt'));
        final rfw = rw.testing
            .readBytes(AssetId(_mountPackage, 'assets/paywalls/$id.rfw'));
        final onboarding = rw.testing.readBytes(
          AssetId(
            _mountPackage,
            'assets/onboarding/screens/paywall_$id.rfw',
          ),
        );

        _expectStringGolden('$id.rfwtxt', rfwtxt, regen: regen);
        _expectBytesGolden('$id.rfw', rfw, regen: regen);
        _expectBytesGolden('paywall_$id.rfw', onboarding, regen: regen);
      });
    }
  });

  group('fluent-pro nav-lowered flow byte-goldens', () {
    test('the production builders emit the navigation-flow artifacts cleanly',
        () {
      expect(
        navFlowResult.succeeded,
        isTrue,
        reason: navFlowResult.errors.join('\n'),
      );
      expect(navFlowResult.errors, isEmpty);
    });

    test('the entry blob + navplan sidecar + flow-screen blobs are byte-stable',
        () {
      final rw = navFlowResult.readerWriter;
      String text(String path) =>
          rw.testing.readString(AssetId(_mountPackage, path));
      List<int> bytes(String path) =>
          rw.testing.readBytes(AssetId(_mountPackage, path));

      _expectStringGolden(
        'fluent_pro.rfwtxt',
        text('assets/paywalls/fluent_pro.rfwtxt'),
        regen: regen,
      );
      _expectBytesGolden(
        'fluent_pro.rfw',
        bytes('assets/paywalls/fluent_pro.rfw'),
        regen: regen,
      );
      // The navplan sidecar (the FlowDocument) — the navigation-specific
      // artifact a silent nav-drop would corrupt. JSON, so a text golden.
      _expectStringGolden(
        'fluent_pro.flow.json',
        text('assets/paywalls/fluent_pro.flow.json'),
        regen: regen,
      );
      _expectBytesGolden(
        'paywall_fluent_pro.rfw',
        bytes('assets/onboarding/screens/paywall_fluent_pro.rfw'),
        regen: regen,
      );
      _expectBytesGolden(
        'paywall_fluent_pro_choose_plan.rfw',
        bytes('assets/onboarding/screens/paywall_fluent_pro_choose_plan.rfw'),
        regen: regen,
      );
    });

    test('the pushed choose-a-plan screen suppresses its standalone blob', () {
      // The second screen uses an in-flow Navigator.pop (back), so its
      // standalone paywall artifact is intentionally not emitted — it renders
      // only as a flow screen. Pin that the suppression holds.
      AssetId asset(String path) => AssetId(_mountPackage, path);
      expect(
        navFlowResult.outputs,
        isNot(contains(asset('assets/paywalls/fluent_pro_choose_plan.rfw'))),
      );
      expect(
        navFlowResult.outputs,
        isNot(contains(asset('assets/paywalls/fluent_pro_choose_plan.rfwtxt'))),
      );
      // The flow-screen blob for the pushed screen IS emitted.
      expect(
        navFlowResult.outputs,
        contains(
          asset('assets/onboarding/screens/paywall_fluent_pro_choose_plan.rfw'),
        ),
      );
    });
  });
}

/// Assert [actual] equals the frozen text golden `$_goldenDir/$name`
/// byte-for-byte. With `REGEN_CODEGEN_GOLDENS=1` the golden is (re)written from
/// the current output first; the assertion then trivially holds, so a regen run
/// also self-checks the round-trip.
void _expectStringGolden(String name, String actual, {required bool regen}) {
  final file = File('$_goldenDir/$name');
  if (regen) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(actual);
  }
  expect(
    actual,
    file.readAsStringSync(),
    reason: 'text golden "$name" moved — the production .rfwtxt changed. '
        'Regenerate with REGEN_CODEGEN_GOLDENS=1 only when intended.',
  );
}

/// Assert [actual] equals the frozen binary golden `$_goldenDir/$name`
/// byte-for-byte. Regeneration semantics mirror [_expectStringGolden].
void _expectBytesGolden(String name, List<int> actual, {required bool regen}) {
  final file = File('$_goldenDir/$name');
  if (regen) {
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(actual);
  }
  expect(
    actual,
    orderedEquals(file.readAsBytesSync()),
    reason: 'binary golden "$name" moved — the production .rfw wire changed. '
        'Regenerate with REGEN_CODEGEN_GOLDENS=1 only when intended.',
  );
}

/// Builds a [TestReaderWriter] whose in-memory filesystem can resolve the real
/// example paywall sources end-to-end.
///
/// The base [readerWriterWithFilesystemSources] seeds `flutter`, `restage` (+
/// its transitive closure), `rfw_catalog_schema`, and the catalog data.
/// On top of that, this:
///   * seeds the `restage_material` source closure (the example sources import
///     it for `RestagePager` etc.), which the base does not reach; and
///   * re-homes the `restage_example|lib` files the paywalls reach — the four
///     `widgets/*_plan_selector.dart` selectors plus the paywalls themselves —
///     into the synthetic `apps_examples` package the harness mounts under, so
///     their relative `../widgets/...` imports resolve.
///
/// Cross-package directives into already-seeded packages ([_skipPackages]) are
/// not re-walked.
Future<TestReaderWriter> _seedRealCorpus(List<String> paywallIds) async {
  final rw = await readerWriterWithFilesystemSources(
    rootPackage: _mountPackage,
    includeFlutter: true,
  );
  final config = await loadPackageConfigUri((await Isolate.packageConfig)!);
  final reader = PackageAssetReader(config, 'restage_codegen');

  final seen = <AssetId>{};
  final queue = Queue<AssetId>()
    ..add(AssetId('restage_material', 'lib/restage_material.dart'))
    ..add(AssetId('restage_cupertino', 'lib/restage_cupertino.dart'));
  for (final id in paywallIds) {
    queue.add(AssetId(_examplePackage, 'lib/paywalls/$id.dart'));
  }

  while (queue.isNotEmpty) {
    final id = queue.removeFirst();
    if (!seen.add(id)) continue;
    if (_skipPackages.contains(id.package)) continue;
    if (!id.path.startsWith('lib/')) continue;
    if (!await reader.canRead(id)) continue;
    final bytes = await reader.readAsBytes(id);
    // The example package is re-homed under the synthetic mount package so its
    // relative imports resolve; every other package keeps its real id.
    final target =
        id.package == _examplePackage ? AssetId(_mountPackage, id.path) : id;
    rw.testing.writeBytes(target, bytes);
    if (!id.path.endsWith('.dart')) continue;
    _directiveDeps(id, utf8.decode(bytes)).forEach(queue.add);
  }
  return rw;
}

/// The `package:`/`asset:` Dart-file dependencies declared by [source]
/// (resolved against [from]). `dart:` imports and non-package schemes are
/// skipped — they need no seeding.
Iterable<AssetId> _directiveDeps(AssetId from, String source) sync* {
  final parsed =
      parseString(content: source, path: from.path, throwIfDiagnostics: false);
  for (final directive in parsed.unit.directives) {
    if (directive is! UriBasedDirective) continue;
    final uriText = directive.uri.stringValue;
    if (uriText == null) continue;
    final uri = Uri.tryParse(uriText);
    if (uri == null || uri.scheme == 'dart') continue;
    if (uri.hasScheme && uri.scheme != 'package' && uri.scheme != 'asset') {
      continue;
    }
    final id = AssetId.resolve(uri, from: from);
    if (id.path.endsWith('.dart')) yield id;
  }
}
