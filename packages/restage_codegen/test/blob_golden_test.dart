import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:test/test.dart';

import '../tool/src/codegen_fixture_roster.dart';
import 'helpers.dart';
import 'support/blob_fixture_generation.dart';

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
/// the input shape the six do not exercise. See [blobNavigationSourceIds].
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
const List<String> _paywallIds = blobStandaloneFixtureIds;

const _goldenDir = 'test/fixtures/goldens';

void main() {
  final regen = Platform.environment['REGEN_CODEGEN_GOLDENS'] == '1';
  late TestBuilderResult result;
  late TestBuilderResult navFlowResult;

  setUpAll(() async {
    result = await buildBlobFixtures(_paywallIds);
    navFlowResult = await buildBlobFixtures(
      blobNavigationSourceIds,
      navigation: true,
    );
  });

  test('the production builder emits all corpus artifacts cleanly', () {
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    expect(result.errors, isEmpty);
    // Each source emits 5 artifacts (.rfwtxt + .rfw + .capability.json +
    // onboarding paywall_<id>.rfw + its paywall_<id>.capability.json sidecar).
    expect(result.outputs.length, _paywallIds.length * 5);
  });

  group('blob byte-goldens', () {
    for (final id in _paywallIds) {
      test('$id is byte-stable', () {
        _expectFixture(captureBlobFixture(result, id), regen: regen);
      });
    }
  });

  group('fluent-pro nav-lowered flow byte-goldens', () {
    test(
      'the production builders emit the navigation-flow artifacts cleanly',
      () {
        expect(
          navFlowResult.succeeded,
          isTrue,
          reason: navFlowResult.errors.join('\n'),
        );
        expect(navFlowResult.errors, isEmpty);
      },
    );

    test(
      'the entry blob + navplan sidecar + flow-screen blobs are byte-stable',
      () {
        _expectFixture(
          captureBlobFixture(navFlowResult, 'fluent_pro'),
          regen: regen,
        );
      },
    );

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
          asset('assets/paywalls/screens/paywall_fluent_pro_choose_plan.rfw'),
        ),
      );
    });
  });
}

void _expectFixture(Map<String, List<int>> artifacts, {required bool regen}) {
  for (final entry in artifacts.entries) {
    if (entry.key.endsWith('.rfw')) {
      _expectBytesGolden(entry.key, entry.value, regen: regen);
    } else {
      _expectStringGolden(entry.key, utf8.decode(entry.value), regen: regen);
    }
  }
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
    reason:
        'text golden "$name" moved — the production .rfwtxt changed. '
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
    reason:
        'binary golden "$name" moved — the production .rfw wire changed. '
        'Regenerate with REGEN_CODEGEN_GOLDENS=1 only when intended.',
  );
}
