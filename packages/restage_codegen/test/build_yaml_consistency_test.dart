import 'dart:io';

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// build.yaml declares each builder's `build_extensions`, `builder_factories`,
/// and `runs_before` so build_runner can plan the build graph; the Builder
/// instance's `buildExtensions` getter is the runtime source of truth for what
/// it is allowed to write. These MUST agree, or a builder can silently drift —
/// an output the getter writes but build.yaml omits is exactly the class of
/// bug that hid the capability sidecar from the build graph, and a missing
/// `runs_before` edge is exactly the class that lets a screen builder race the
/// not-yet-written customer catalog (the catalog read swallows the miss, so
/// nothing fails loud at build time). This test pins extensions, factory
/// wiring, and the ordering graph together so any future drift fails loud —
/// and derives the ordering rules from the declared builder-name set, so a
/// NEW surface's builders cannot be forgotten.
void main() {
  group('build.yaml ↔ Builder.buildExtensions', () {
    // Each builder factory the package exposes, keyed by its build.yaml name.
    final factories = <String, Builder Function(BuilderOptions)>{
      'paywall_codegen': restageCodegenBuilder,
      'paywall_flow_codegen': paywallFlowBuilder,
      'onboarding_screen_codegen': onboardingScreenBuilder,
      'onboarding_flow_codegen': onboardingFlowBuilder,
      'message_screen_codegen': messageScreenBuilder,
      'message_flow_codegen': messageFlowBuilder,
      'survey_screen_codegen': surveyScreenBuilder,
      'survey_flow_codegen': surveyFlowBuilder,
      'restage_source_roster': restageSourceRosterBuilder,
      'restage_package_surface_compiler': restagePackageSurfaceCompilerBuilder,
      'outputs': restageOutputsBuilder,
      'generated_dart': restageGeneratedDartBuilder,
      'user_catalog': userCatalogBuilder,
      'user_catalog_json': userCatalogJsonBuilder,
      'factory_functions': factoryFunctionBuilder,
      'user_factories': userFactoryBuilder,
      'user_a2ui_catalog': userA2uiCatalogBuilder,
      'widgetbook_stories': widgetbookStoryBuilder,
    };

    // The factory FUNCTION each build.yaml entry must point at. build.yaml's
    // `builder_factories` strings are resolved by name at production
    // build-plan time only, so a copy-paste error (a message entry pointing
    // at a survey factory) is invisible to every in-package test that
    // constructs factories directly. Pinned here instead.
    const expectedFactoryNames = <String, String>{
      'paywall_codegen': 'restageCodegenBuilder',
      'paywall_flow_codegen': 'paywallFlowBuilder',
      'onboarding_screen_codegen': 'onboardingScreenBuilder',
      'onboarding_flow_codegen': 'onboardingFlowBuilder',
      'message_screen_codegen': 'messageScreenBuilder',
      'message_flow_codegen': 'messageFlowBuilder',
      'survey_screen_codegen': 'surveyScreenBuilder',
      'survey_flow_codegen': 'surveyFlowBuilder',
      'restage_source_roster': 'restageSourceRosterBuilder',
      'restage_package_surface_compiler':
          'restagePackageSurfaceCompilerBuilder',
      'outputs': 'restageOutputsBuilder',
      'generated_dart': 'restageGeneratedDartBuilder',
      'user_catalog': 'userCatalogBuilder',
      'user_catalog_json': 'userCatalogJsonBuilder',
      'factory_functions': 'factoryFunctionBuilder',
      'user_factories': 'userFactoryBuilder',
      'user_a2ui_catalog': 'userA2uiCatalogBuilder',
      'widgetbook_stories': 'widgetbookStoryBuilder',
    };

    late Map<String, Map<String, List<String>>> declared;
    late Map<String, List<String>> factoryNames;

    setUpAll(() {
      final root = loadYaml(File('build.yaml').readAsStringSync()) as YamlMap;
      final builders = root['builders'] as YamlMap;
      declared = {
        for (final builder in builders.entries)
          builder.key as String: {
            for (final ext
                in ((builder.value as YamlMap)['build_extensions'] as YamlMap)
                    .entries)
              ext.key as String: [
                for (final out in ext.value as YamlList) out as String,
              ],
          },
      };
      factoryNames = {
        for (final builder in builders.entries)
          builder.key as String: [
            for (final name
                in (builder.value as YamlMap)['builder_factories'] as YamlList)
              name as String,
          ],
      };
    });

    test('build.yaml declares exactly the builders the package exposes', () {
      expect(declared.keys.toSet(), factories.keys.toSet());
    });

    test('A2UI artifacts have one declared default generated path', () {
      // The declared family is the DEFAULT placement resolution. Both files
      // hang off the package step because a configured portable-output root
      // may sit outside lib/, which a lib-rooted extension cannot express.
      const expected = {
        r'$package$': [
          'lib/generated/restage_a2ui_catalog.g.dart',
          'lib/generated/restage_a2ui_catalog.a2ui.json',
        ],
      };
      expect(declared['user_a2ui_catalog'], expected);
      expect(
        factories['user_a2ui_catalog']!(BuilderOptions.empty).buildExtensions,
        expected,
      );
    });

    for (final name in factories.keys) {
      test('$name: build.yaml build_extensions match the getter', () {
        if (name == 'widgetbook_stories') {
          // Widgetbook story outputs are discovered from the consuming
          // package's syntax-broad source census at builder creation time. The
          // fixed unwritten sentinel keeps the package step scheduled when an
          // existing hand-authored story excludes its stem; analyzer-resolved
          // identities decide which remaining candidates are actually written.
          expect(
            declared[name],
            {
              r'$lib$': [
                'generated/.restage_widgetbook_story_builder',
                'restage.generated/promo_banner.stories.dart',
              ],
            },
          );
          return;
        }
        final getter = factories[name]!(BuilderOptions.empty).buildExtensions;
        expect(
          declared[name],
          getter,
          reason: 'build.yaml build_extensions for "$name" must exactly match '
              "the builder's buildExtensions getter — the production "
              'build_runner reads build.yaml; tests read the getter.',
        );
      });
    }

    test('builder_factories point at the intended factory functions', () {
      expect(factoryNames.keys.toSet(), expectedFactoryNames.keys.toSet());
      for (final entry in expectedFactoryNames.entries) {
        expect(
          factoryNames[entry.key],
          [entry.value],
          reason: 'build.yaml wires "${entry.key}" to the wrong factory — '
              'the string is resolved by name only at production '
              'build-plan time, so nothing else catches a mismatch.',
        );
      }
    });

    test(
        'the unified outputs builder is a normal builder with no '
        'post-process stage', () {
      final root = loadYaml(File('build.yaml').readAsStringSync()) as YamlMap;
      expect(
        root.containsKey('post_process_builders'),
        isFalse,
        reason: 'Generated-output materialization is a normal builder with '
            'statically predictable buildExtensions; a post-process builder '
            'cannot declare static outputs and is not permitted.',
      );
      final compilerOutputs = restagePackageSurfaceCompilerBuilder(
        BuilderOptions.empty,
      ).buildExtensions[r'$package$']!;
      expect(
        compilerOutputs,
        ['lib/src/surface_publication/surface_publication.compiler.json'],
      );
    });
  });

  group('build.yaml runs_before graph', () {
    late Map<String, List<String>> runsBefore;
    late Set<String> declaredNames;

    setUpAll(() {
      final root = loadYaml(File('build.yaml').readAsStringSync()) as YamlMap;
      final builders = root['builders'] as YamlMap;
      declaredNames = {for (final b in builders.entries) b.key as String};
      runsBefore = {
        for (final builder in builders.entries)
          builder.key as String: [
            for (final dep
                in ((builder.value as YamlMap)['runs_before'] as YamlList? ??
                    YamlList()))
              dep as String,
          ],
      };
    });

    test('every screen builder is ordered before its flow builder', () {
      // Derived from the declared name set: a new `<surface>_screen_codegen`
      // automatically joins this rule. A flow builder reading screen
      // descriptors/artifacts before the screen builder wrote them fails the
      // build with a missing-artifact issue — loud, but pointing at the flow,
      // not at the ordering. Pin the edge here instead.
      final screenBuilders =
          declaredNames.where((n) => n.endsWith('_screen_codegen')).toList();
      expect(screenBuilders, isNotEmpty);
      for (final screen in screenBuilders) {
        final flow = screen.replaceFirst('_screen_codegen', '_flow_codegen');
        expect(
          declaredNames,
          contains(flow),
          reason: '"$screen" has no matching "$flow" builder.',
        );
        expect(
          runsBefore[screen],
          contains('restage_codegen:$flow'),
          reason: '"$screen" must run before "$flow" — the flow builder reads '
              "the screen builder's emitted descriptors and artifacts.",
        );
      }
    });

    test('the paywall builder is ordered before the paywall flow builder', () {
      expect(
        runsBefore['paywall_codegen'],
        contains('restage_codegen:paywall_flow_codegen'),
      );
    });

    test('the package roster is ordered before every roster consumer', () {
      const consumers = <String>{
        'paywall_codegen',
        'paywall_flow_codegen',
        'onboarding_screen_codegen',
        'onboarding_flow_codegen',
        'message_screen_codegen',
        'message_flow_codegen',
        'survey_screen_codegen',
        'survey_flow_codegen',
        'restage_package_surface_compiler',
        'user_catalog',
        'user_catalog_json',
        'factory_functions',
        'user_factories',
        'outputs',
      };
      for (final consumer in consumers) {
        expect(
          runsBefore['restage_source_roster'],
          contains('restage_codegen:$consumer'),
          reason: 'the package roster must be complete before "$consumer" '
              'can consume or publish a Restage-owned source family.',
        );
      }
    });

    test('the fixed publication chain is compiler then unified outputs', () {
      expect(
        runsBefore['restage_package_surface_compiler'],
        contains('restage_codegen:outputs'),
      );
      expect(
        runsBefore['paywall_flow_codegen'],
        contains('restage_codegen:restage_package_surface_compiler'),
      );
      expect(
        runsBefore['user_catalog_json'],
        contains('restage_codegen:restage_package_surface_compiler'),
      );
    });

    test('the Widgetbook story builder runs before Widgetbook generation', () {
      expect(
        runsBefore['widgetbook_stories'],
        contains('widgetbook:story_builder'),
      );
    });

    test('the catalog JSON emitter is ordered before every catalog consumer',
        () {
      // Builders that resolve widgets against the merged customer catalog
      // must appear in user_catalog_json.runs_before. If the edge is missing,
      // the catalog read swallows the not-yet-written file and the consumer
      // silently resolves against an EMPTY customer catalog — a custom widget
      // then misclassifies with no build error naming the real cause. The
      // consumer set is derived from the declared names, so a new surface's
      // screen builder cannot be forgotten.
      final consumers = <String>{
        'paywall_codegen',
        'factory_functions',
        ...declaredNames.where((n) => n.endsWith('_screen_codegen')),
      };
      for (final consumer in consumers) {
        expect(
          runsBefore['user_catalog_json'],
          contains('restage_codegen:$consumer'),
          reason: '"$consumer" reads the merged customer catalog; '
              '"user_catalog_json" must be ordered before it.',
        );
      }
    });

    test('the wire-id log owner runs before the catalog JSON emitter', () {
      expect(
        runsBefore['user_catalog'],
        contains('restage_codegen:user_catalog_json'),
        reason: 'the JSON emitter must read a fully-appended wire-id log.',
      );
    });
  });
}
