import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:glob/glob.dart';
import 'package:restage_codegen/src/authored_library_predicate.dart';
import 'package:restage_codegen/src/restage_source_prefilter.dart';
import 'package:test/test.dart';

void main() {
  group('selectRestageCandidateLibraries', () {
    test('returns only the candidates whose raw source spells a token',
        () async {
      final selected = await _select(
        const {
          'lib/annotated.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget()
class Badge {}
''',
          'lib/plain.dart': '''
class Ordinary {}
''',
        },
        restageWidgetSourceTokens,
      );

      expect(selected, ['lib/annotated.dart']);
    });

    test('returns nothing for a package that spells no token', () async {
      final selected = await _select(
        const {
          'lib/a.dart': 'class A {}',
          'lib/b.dart': 'class B {}',
        },
        restageWidgetSourceTokens,
      );

      expect(selected, isEmpty);
    });

    test('does not treat a longer identifier as a surface token', () async {
      final selected = await _select(
        const {
          'lib/home.dart': '''
class HomeScreenController {}
class MyPaywallPresenter {}
''',
        },
        restageSurfaceSourceTokens,
      );

      expect(selected, isEmpty);
    });

    test('matches a deprecated surface spelling behind an import prefix',
        () async {
      final selected = await _select(
        const {
          'lib/legacy.dart': '''
import 'package:restage/restage.dart' as rs;

@rs.ScreenSource(id: 'legacy')
class LegacyScreen {}
''',
        },
        restageSurfaceSourceTokens,
      );

      expect(selected, ['lib/legacy.dart']);
    });

    test('matches the canonical const-instance spelling of an annotation',
        () async {
      final selected = await _select(
        const {
          'lib/instance.dart': '''
@screen
class Welcome {}
''',
        },
        restageSurfaceSourceTokens,
      );

      expect(selected, ['lib/instance.dart']);
    });

    test('adds the owning library of a token-bearing part named by URI',
        () async {
      final selected = await _select(
        const {
          'lib/onboarding/screens/host.dart': '''
library shared_screens;

import 'package:restage/restage.dart' as rs;

part '../../src/host_part.dart';
''',
          'lib/src/host_part.dart': '''
part of '../onboarding/screens/host.dart';

@rs.ScreenSource(id: 'host')
class HostScreen {}
''',
          // Present so a successful join is distinguishable from a full
          // fallback, which would return this file too.
          'lib/unrelated.dart': 'class Unrelated {}',
        },
        restageSurfaceSourceTokens,
      );

      expect(selected, [
        'lib/onboarding/screens/host.dart',
        'lib/src/host_part.dart',
      ]);
    });

    test(
        'adds the owning library of a token-bearing part named by library name',
        () async {
      final selected = await _select(
        const {
          'lib/named_host.dart': '''
library shared_screens;

import 'package:restage/restage.dart' as rs;

part 'src/named_part.dart';
''',
          'lib/src/named_part.dart': '''
part of shared_screens;

@rs.ScreenSource(id: 'named')
class NamedScreen {}
''',
          'lib/unrelated.dart': 'class Unrelated {}',
        },
        restageSurfaceSourceTokens,
      );

      expect(selected, [
        'lib/named_host.dart',
        'lib/src/named_part.dart',
      ]);
    });

    test('falls back to every candidate when a part owner cannot be joined',
        () async {
      final selected = await _select(
        const {
          'lib/orphan_part.dart': '''
part of nowhere_at_all;

@rs.ScreenSource(id: 'orphan')
class OrphanScreen {}
''',
          'lib/unrelated.dart': 'class Unrelated {}',
        },
        restageSurfaceSourceTokens,
      );

      expect(selected, [
        'lib/orphan_part.dart',
        'lib/unrelated.dart',
      ]);
    });

    test('does not fall back when a part is owned outside the walk', () async {
      final selected = await _select(
        const {
          'lib/foreign_part.dart': '''
part of 'package:some_other_package/host.dart';

@RestageWidget()
class Foreign {}
''',
          'lib/unrelated.dart': 'class Unrelated {}',
        },
        restageWidgetSourceTokens,
      );

      // Resolving every candidate would not reach the owner either, so the
      // full walk buys nothing and is not taken.
      expect(selected, ['lib/foreign_part.dart']);
    });

    test(
        'joins the owner of a token-bearing part the surface lane may not '
        'resolve', () async {
      // A `.g.dart` is not an authored library, so the surface lane never
      // resolves one — but it can still be a `part`, and the declaration it
      // carries belongs to an owner that spells nothing itself. Scanning has
      // to reach further than resolving does.
      final selected = await _selectSurfaceLane(const {
        'lib/screens/host.dart': '''
library acme_host;

import 'package:restage/restage.dart' as rs;

part 'greeting.g.dart';
''',
        'lib/screens/greeting.g.dart': '''
part of 'host.dart';

@rs.Screen(id: 'greeting')
class GreetingScreen {}
''',
        'lib/models/order.dart': 'class Order {}',
      });

      // The owner is resolved; the part itself is not an authored library and
      // is dropped, exactly as before this filter existed.
      expect(selected, ['lib/screens/host.dart']);
    });

    test('warns when a joined owner is one this walk will not resolve',
        () async {
      // The part is authored and carries the token; its owner is a generated
      // library the surface lane never resolves. The declaration is lost —
      // it was lost before this filter existed too — but silence is what made
      // it hard to find.
      final logs = await _laneLogs(const {
        'lib/host.g.dart': '''
library acme_host;

part 'card_part.dart';
''',
        'lib/card_part.dart': '''
part of 'host.g.dart';

@rs.Screen(id: 'greeting')
class GreetingScreen {}
''',
      });

      expect(
        logs.join('\n'),
        allOf(
          contains('WARNING'),
          contains('lib/host.g.dart'),
          contains('lib/card_part.dart'),
        ),
      );
    });

    test('names every part when one unresolvable owner has several', () async {
      // Each part's declaration is equally lost, so a warning that mentions
      // whichever happened to be seen last is a warning that hides one.
      final logs = await _laneLogs(const {
        'lib/host.g.dart': '''
library acme_host;

part 'a_part.dart';
part 'b_part.dart';
''',
        'lib/a_part.dart': '''
part of 'host.g.dart';

@rs.Screen(id: 'a')
class AScreen {}
''',
        'lib/b_part.dart': '''
part of 'host.g.dart';

@rs.Screen(id: 'b')
class BScreen {}
''',
      });

      final warnings =
          logs.where((log) => log.startsWith('WARNING')).join('\n');
      expect(warnings, contains('lib/a_part.dart'));
      expect(warnings, contains('lib/b_part.dart'));
      expect(warnings, contains('lib/host.g.dart'));
    });

    test(
        'does not warn for a token-bearing library that is merely not '
        'resolvable', () async {
      // Nothing joined this file; it carries a token of its own and simply is
      // not something the surface lane resolves. That is the ordinary case
      // and has always been silent.
      final logs = await _laneLogs(const {
        'lib/generated.g.dart': '''
@rs.Screen(id: 'generated')
class GeneratedScreen {}
''',
      });

      expect(logs.where((log) => log.startsWith('WARNING')), isEmpty);
    });

    test('narrows the full-fallback result too', () async {
      // The fallback returns every candidate. It still has to respect what the
      // caller said it will resolve — a walk that asked for authored
      // libraries must not be handed generated ones just because a `part of`
      // URI somewhere was unreadable.
      final selected = await _selectSurfaceLane(const {
        'lib/broken_part.dart': '''
part of 'dart:core';

@rs.Screen(id: 'broken')
class BrokenScreen {}
''',
        'lib/generated.g.dart': 'class Generated {}',
        'lib/plain.dart': 'class Plain {}',
      });

      expect(selected, isNot(contains('lib/generated.g.dart')));
      // `plain.dart` carries no token and appears only when the fallback
      // returned every candidate, so this is what pins that the path under
      // test was actually taken.
      expect(selected, contains('lib/plain.dart'));
    });

    test('narrows the orphan fallback too', () async {
      // The other fallback: a part whose owner no candidate declares. It must
      // respect `resolvable` for the same reason.
      final selected = await _selectSurfaceLane(const {
        'lib/orphan.dart': '''
part of nowhere_at_all;

@rs.Screen(id: 'orphan')
class OrphanScreen {}
''',
        'lib/generated.g.dart': 'class Generated {}',
        'lib/plain.dart': 'class Plain {}',
      });

      expect(selected, isNot(contains('lib/generated.g.dart')));
      expect(selected, contains('lib/plain.dart'));
    });

    test('follows a const alias declared in another file', () async {
      // The alias declaration spells the annotation class, so its own file is
      // always selected; the file that USES the alias spells nothing.
      final selected = await _select(
        const {
          'lib/annotations.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const card = RestageWidget(description: 'A card.');
''',
          'lib/widgets/card.dart': '''
import '../annotations.dart';

@card
class ProductCard {}
''',
          'lib/plain.dart': 'class Plain {}',
        },
        restageWidgetSourceTokens,
      );

      expect(selected, [
        'lib/annotations.dart',
        'lib/widgets/card.dart',
      ]);
    });

    test('follows a prefixed const alias', () async {
      final selected = await _select(
        const {
          'lib/annotations.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart' as rs;

const card = rs.RestageWidget(description: 'A card.');
''',
          'lib/widgets/card.dart': '''
import '../annotations.dart' as a;

@a.card
class ProductCard {}
''',
        },
        restageWidgetSourceTokens,
      );

      expect(selected, [
        'lib/annotations.dart',
        'lib/widgets/card.dart',
      ]);
    });

    test('follows a typedef alias', () async {
      final selected = await _select(
        const {
          'lib/annotations.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

typedef RW = RestageWidget;
''',
          'lib/widgets/card.dart': '''
import '../annotations.dart';

@RW(description: 'A card.')
class ProductCard {}
''',
        },
        restageWidgetSourceTokens,
      );

      expect(selected, [
        'lib/annotations.dart',
        'lib/widgets/card.dart',
      ]);
    });

    test('follows an alias declared as a class constant', () async {
      // `@Annotations.card` is an ordinary way to keep a set of annotation
      // constants together, and the use pattern already accepts the qualified
      // form — so reading only top-level declarations would find the use and
      // never learn the name.
      final selected = await _select(
        const {
          'lib/annotations.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

abstract final class Annotations {
  static const card = RestageWidget();
}
''',
          'lib/uses_alias.dart': '''
import 'annotations.dart';

@Annotations.card
class Badge {}
''',
          'lib/plain.dart': 'class Ordinary {}',
        },
        restageWidgetSourceTokens,
      );

      expect(selected, ['lib/annotations.dart', 'lib/uses_alias.dart']);
    });

    test('follows a class constant reached through an import prefix', () async {
      // `@p.Annotations.card` — the same class constant, with the holder
      // imported under a prefix. Two qualifying segments rather than one.
      final selected = await _select(
        const {
          'lib/annotations.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

abstract final class Annotations {
  static const card = RestageWidget();
}
''',
          'lib/uses_alias.dart': '''
import 'annotations.dart' as p;

@p.Annotations.card
class Badge {}
''',
          'lib/plain.dart': 'class Ordinary {}',
        },
        restageWidgetSourceTokens,
      );

      expect(selected, ['lib/annotations.dart', 'lib/uses_alias.dart']);
    });

    test('does not follow an alias declared in another package', () async {
      // The pass finds an alias by scanning the files it already selected, and
      // it only ever selects files from the package being walked. An alias
      // declared in a dependency is therefore invisible to it — while the
      // resolver, which does cross package boundaries, accepts the annotation
      // perfectly well. That gap is a real limit, and the README and CHANGELOG
      // say so; this pins it so it cannot drift into a silent one.
      final selected = await _select(
        const {
          'other_pkg|lib/annotations.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const card = RestageWidget(description: 'A card.');
''',
          'lib/uses_alias.dart': '''
import 'package:other_pkg/annotations.dart';

@card
class Badge {}
''',
        },
        restageWidgetSourceTokens,
      );

      expect(selected, isEmpty);
    });

    test('follows the same alias once it is declared in this package',
        () async {
      // The control for the test above: identical shape, alias moved into the
      // walked package. If this were to fail the same way, the test above
      // would be pinning a broken fixture rather than the package boundary.
      final selected = await _select(
        const {
          'lib/annotations.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const card = RestageWidget(description: 'A card.');
''',
          'lib/uses_alias.dart': '''
import 'annotations.dart';

@card
class Badge {}
''',
        },
        restageWidgetSourceTokens,
      );

      expect(selected, ['lib/annotations.dart', 'lib/uses_alias.dart']);
    });

    test('follows an alias of an alias', () async {
      final selected = await _select(
        const {
          'lib/annotations.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const card = RestageWidget(description: 'A card.');
''',
          'lib/second.dart': '''
import 'annotations.dart';

const alsoCard = card;
''',
          'lib/widgets/card.dart': '''
import '../second.dart';

@alsoCard
class ProductCard {}
''',
        },
        restageWidgetSourceTokens,
      );

      expect(selected, [
        'lib/annotations.dart',
        'lib/second.dart',
        'lib/widgets/card.dart',
      ]);
    });

    test('scans a file that is not valid UTF-8', () async {
      // A library saved as latin-1: one byte that is not valid UTF-8, sitting
      // in a comment above an annotated declaration. Reading it as a string
      // throws a FormatException that names an offset and no file, which
      // fails the build with nothing to act on. The scan reads bytes and
      // tolerates the damage, so the file keeps its place in the walk and any
      // real complaint comes from the resolver, which names it.
      final bytes = utf8
          .encode("// Copyright (c) 2026\n@rs.Screen(id: 'legacy')\n"
              'class LegacyScreen {}\n')
          .toList();
      bytes[13] = 0xA9;

      final selected = await _selectSurfaceLane({
        'lib/legacy_encoded.dart': bytes,
        'lib/plain.dart': 'class Plain {}',
      });

      expect(selected, ['lib/legacy_encoded.dart']);
    });

    test('returns a deterministic, duplicate-free, path-sorted selection',
        () async {
      final selected = await _select(
        const {
          'lib/z_host.dart': '''
library z_host;

part 'a_part.dart';
part 'm_part.dart';
''',
          'lib/a_part.dart': '''
part of 'z_host.dart';

@RestageWidget()
class A {}
''',
          'lib/m_part.dart': '''
part of 'z_host.dart';

@RestageWidget()
class M {}
''',
        },
        restageWidgetSourceTokens,
      );

      expect(selected, [
        'lib/a_part.dart',
        'lib/m_part.dart',
        'lib/z_host.dart',
      ]);
    });
  });

  group('selectRestageNativeScreenCandidates', () {
    test('does not admit a generated file at the deprecated screen path',
        () async {
      // The two rules this lane composes could contradict each other: it
      // examines every file at the deprecated screen path whatever it says,
      // and it declines to resolve a generated library. An ordinary code
      // generator writes `welcome.g.dart` next to an annotated screen, so
      // that pair is common rather than exotic. It is settled where the rules
      // are chosen — the file is never admitted — so nothing downstream has
      // to decide what a file admitted-and-unresolvable means, and no build
      // says anything about it.
      final result = await _runNativeScreenLane(const {
        'lib/onboarding/screens/welcome.g.dart': 'class Welcome {}',
      });

      expect(result.paths, isEmpty);
      expect(
        result.logs.where(
          (log) => log.startsWith('WARNING') || log.startsWith('SEVERE'),
        ),
        isEmpty,
      );
    });

    test('admits an unannotated file at the deprecated screen path', () async {
      // The admission itself: a file there is examined whatever it says, which
      // is where its syntax errors are reported.
      final result = await _runNativeScreenLane(const {
        'lib/onboarding/screens/foo.dart': 'class Foo {}',
      });

      expect(result.paths, ['lib/onboarding/screens/foo.dart']);
      expect(result.logs.where((log) => log.startsWith('WARNING')), isEmpty);
    });
  });
}

/// Runs one selection over [sources] inside a real build step, returning both
/// what it selected and what it logged.
///
/// [select] is the lane under test; every lane is a different answer to the
/// same question, so they share one probe rather than one probe each.
Future<({List<String> paths, List<String> logs})> _runLane(
  Future<List<AssetId>> Function(BuildStep) select,
  Map<String, Object> sources,
) async {
  var selected = <AssetId>[];
  final logs = <String>[];
  final result = await testBuilder(
    _LaneProbeBuilder(
      select: select,
      onSelected: (assets) => selected = assets,
    ),
    {
      // A key may name its own package (`other_pkg|lib/x.dart`); otherwise it
      // belongs to the package being walked.
      for (final entry in sources.entries)
        entry.key.contains('|') ? entry.key : 'apps_examples|${entry.key}':
            entry.value,
    },
    rootPackage: 'apps_examples',
    onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
  );
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  return (paths: [for (final asset in selected) asset.path], logs: logs);
}

/// The paths the surface lane selected for [sources].
Future<List<String>> _selectSurfaceLane(Map<String, Object> sources) async =>
    (await _runLane(selectRestageSurfaceCandidates, sources)).paths;

/// Everything the surface lane logged for [sources].
Future<List<String>> _laneLogs(Map<String, Object> sources) async =>
    (await _runLane(selectRestageSurfaceCandidates, sources)).logs;

/// Runs the native screen lane, the only one that admits a file on its
/// location as well as its text.
Future<({List<String> paths, List<String> logs})> _runNativeScreenLane(
  Map<String, Object> sources,
) =>
    _runLane(
      (buildStep) => selectRestageNativeScreenCandidates(
        buildStep,
        resolvable: isAuthoredDartLibraryAsset,
      ),
      sources,
    );

/// The paths the shared primitive selected for [sources] on [tokens].
Future<List<String>> _select(
  Map<String, Object> sources,
  RestageTokenSet tokens,
) async =>
    (await _runLane(
      (buildStep) async => selectRestageCandidateLibraries(
        buildStep,
        candidates: await buildStep.findAssets(Glob('lib/**.dart')).toList(),
        tokens: tokens,
      ),
      sources,
    ))
        .paths;

final class _LaneProbeBuilder implements Builder {
  const _LaneProbeBuilder({required this.select, required this.onSelected});

  final Future<List<AssetId>> Function(BuildStep) select;
  final void Function(List<AssetId>) onSelected;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$package$': ['restage.lane_probe'],
      };

  @override
  Future<void> build(BuildStep buildStep) async =>
      onSelected(await select(buildStep));
}
