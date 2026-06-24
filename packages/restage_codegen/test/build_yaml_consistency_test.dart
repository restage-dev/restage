import 'dart:io';

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// build.yaml declares each builder's `build_extensions` so build_runner can
/// plan the build graph; the Builder instance's `buildExtensions` getter is the
/// runtime source of truth for what it is allowed to write. The two MUST agree,
/// or a builder can silently drift — an output the getter writes but build.yaml
/// omits is exactly the class of bug that hid the capability sidecar from the
/// build graph. This test pins them together so any future drift fails loud.
void main() {
  group('build.yaml ↔ Builder.buildExtensions', () {
    // Each builder factory the package exposes, keyed by its build.yaml name.
    final factories = <String, Builder Function(BuilderOptions)>{
      'paywall_codegen': restageCodegenBuilder,
      'paywall_flow_codegen': paywallFlowBuilder,
      'onboarding_screen_codegen': onboardingScreenBuilder,
      'onboarding_flow_codegen': onboardingFlowBuilder,
      'user_catalog': userCatalogBuilder,
      'factory_functions': factoryFunctionBuilder,
      'user_factories': userFactoryBuilder,
    };

    late Map<String, Map<String, List<String>>> declared;

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
    });

    test('build.yaml declares exactly the builders the package exposes', () {
      expect(declared.keys.toSet(), factories.keys.toSet());
    });

    for (final name in factories.keys) {
      test('$name: build.yaml build_extensions match the getter', () {
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
  });
}
