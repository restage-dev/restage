import 'package:restage_cli/src/init/build_yaml_editor.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

List<Object?> _listed(String source) =>
    ((loadYaml(source) as YamlMap)['additional_public_assets'] as YamlList)
        .toList();

void main() {
  group('planStateBuildInputs', () {
    test('creates build.yaml when absent', () {
      final plan = planStateBuildInputs(null);

      expect(plan.action, StateBuildInputsAction.create);
      expect(
        plan.source,
        'additional_public_assets:\n'
        '  - .restage/measurement-state.json\n'
        '  - .restage/wire-ids.events.jsonl\n'
        '  - .restage/receipts/**\n',
      );
    });

    test('adds the list to a build.yaml with other content', () {
      const source = '''
# App builders.
targets:
  \$default:
    builders:
      restage_codegen:outputs:
        options:
          bundled_runtime: true
''';

      final plan = planStateBuildInputs(source);

      expect(plan.action, StateBuildInputsAction.update);
      expect(_listed(plan.source), restageStateBuildInputs);
      expect(
        plan.source.replaceFirst(
          'additional_public_assets:\n'
              '  - .restage/measurement-state.json\n'
              '  - .restage/wire-ids.events.jsonl\n'
              '  - .restage/receipts/**\n',
          '',
        ),
        source,
      );
    });

    test('appends only missing entries to an existing list', () {
      const source = '''
additional_public_assets:
  - tool/fixture.json
  - .restage/measurement-state.json
''';

      final plan = planStateBuildInputs(source);

      expect(plan.action, StateBuildInputsAction.update);
      expect(_listed(plan.source), [
        'tool/fixture.json',
        '.restage/measurement-state.json',
        '.restage/wire-ids.events.jsonl',
        '.restage/receipts/**',
      ]);
    });

    test('keeps a file that already lists every entry', () {
      const source = '''
additional_public_assets:
  - .restage/wire-ids.events.jsonl
  - .restage/measurement-state.json
  - .restage/receipts/**
''';

      final plan = planStateBuildInputs(source);

      expect(plan.action, StateBuildInputsAction.keep);
      expect(plan.source, source);
    });

    for (final (label, source) in [
      ('does not parse', 'targets: [\n'),
      ('is not a map', '- one\n- two\n'),
      ('has a non-list entry', 'additional_public_assets: tool/a.json\n'),
    ]) {
      test('asks the user to edit a file that $label', () {
        final plan = planStateBuildInputs(source);

        expect(plan.action, StateBuildInputsAction.manual);
        expect(plan.source, source);
      });
    }
  });

  group('planEarlyRequestOptions', () {
    test('writes the service and key into a new build.yaml', () {
      final plan = planEarlyRequestOptions(
        null,
        baseUrl: 'https://api.example.com',
        apiKey: 'rs_pk_test',
      );
      expect(plan.action, StateBuildInputsAction.create);
      final options = loadYaml(
        plan.source,
      )['targets'][r'$default']['builders'][earlyRequestBuilderKey]['options'];
      expect(options['base_url'], 'https://api.example.com');
      expect(options['api_key'], 'rs_pk_test');
    });

    test('keeps values already set and leaves other builders alone', () {
      const source = '''
targets:
  \$default:
    builders:
      restage_codegen:user_factories:
        options:
          catalog: derived
      restage_codegen:restage_early_template:
        options:
          api_key: rs_pk_mine
''';
      final plan = planEarlyRequestOptions(
        source,
        baseUrl: 'https://api.example.com',
        apiKey: 'rs_pk_other',
      );
      final builders = loadYaml(
        plan.source,
      )['targets'][r'$default']['builders'];
      expect(
        builders['restage_codegen:user_factories']['options']['catalog'],
        'derived',
      );
      final options = builders[earlyRequestBuilderKey]['options'];
      expect(options['api_key'], 'rs_pk_mine');
      expect(options['base_url'], 'https://api.example.com');
    });

    test('records an explicit opt-out', () {
      final plan = planEarlyRequestOptions(null, enabled: false);
      final options = loadYaml(
        plan.source,
      )['targets'][r'$default']['builders'][earlyRequestBuilderKey]['options'];
      expect(options['early_request'], false);
    });
  });
}
