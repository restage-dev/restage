import 'package:glob/glob.dart';
import 'package:restage_cli/src/init/build_yaml_editor.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

List<Object?> _listed(String source) =>
    ((loadYaml(source) as YamlMap)['additional_public_assets'] as YamlList)
        .toList();

YamlMap? _builder(String source, String key) =>
    ((loadYaml(source) as YamlMap)['targets']?[r'$default']?['builders']
            as YamlMap?)?[key]
        as YamlMap?;

void main() {
  group('state file tracking', () {
    test('creates build.yaml when absent', () {
      final plan = planBuildYaml(null);

      expect(plan.action, StateBuildInputsAction.create);
      expect(
        plan.source,
        'additional_public_assets:\n'
        '  - .restage/measurement-state.json\n'
        '  - .restage/wire-ids.events.jsonl\n'
        '  - .restage/receipts/**\n'
        '  - .restage/library-contracts/**\n',
      );
      expect(plan.written, ['state file tracking']);
      expect(plan.hasApiKey, isFalse);
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

      final plan = planBuildYaml(source);

      expect(plan.action, StateBuildInputsAction.update);
      expect(_listed(plan.source), restageStateBuildInputs);
      expect(
        _builder(
          plan.source,
          'restage_codegen:outputs',
        )!['options']['bundled_runtime'],
        isTrue,
      );
      expect(plan.source, contains('# App builders.'));
    });

    test('replaces .restage/**, which admits push output, and keeps the '
        'rest', () {
      const source = '''
additional_public_assets:
  - tool/fixture.json
  - .restage/**
  - .restage/receipts/**
''';

      final plan = planBuildYaml(source);

      expect(plan.action, StateBuildInputsAction.update);
      expect(_listed(plan.source), [
        'tool/fixture.json',
        '.restage/receipts/**',
        '.restage/measurement-state.json',
        '.restage/wire-ids.events.jsonl',
        '.restage/library-contracts/**',
      ]);
    });

    test('no entry admits what builds and pushes write', () {
      for (final path in const [
        '.restage/build/surface_capture/lib/main.dart',
        '.restage/build/surface_capture/pubspec.yaml',
        '.restage/build/metadata/restage.publication.json',
        '.restage/build/library-contracts/app/v1.json',
      ]) {
        for (final entry in restageStateBuildInputs) {
          expect(Glob(entry).matches(path), isFalse, reason: '$entry, $path');
        }
      }
      for (final path in const [
        '.restage/measurement-state.json',
        '.restage/wire-ids.events.jsonl',
        '.restage/receipts/surface/paywall/pro/push-r1.json',
        '.restage/library-contracts/app/v1.json',
      ]) {
        expect(
          restageStateBuildInputs.any((entry) => Glob(entry).matches(path)),
          isTrue,
          reason: path,
        );
      }
    });

    test('keeps a file that already lists every entry', () {
      const source = '''
additional_public_assets:
  - tool/fixture.json
  - .restage/measurement-state.json
  - .restage/wire-ids.events.jsonl
  - .restage/receipts/**
  - .restage/library-contracts/**
''';

      final plan = planBuildYaml(source);

      expect(plan.action, StateBuildInputsAction.keep);
      expect(plan.source, source);
      expect(plan.written, isEmpty);
    });

    for (final (label, source) in [
      ('does not parse', 'targets: [\n'),
      ('is not a map', '- one\n- two\n'),
      ('has a non-list entry', 'additional_public_assets: tool/a.json\n'),
    ]) {
      test('asks the user to edit a file that $label', () {
        final plan = planBuildYaml(source);

        expect(plan.action, StateBuildInputsAction.manual);
        expect(plan.source, source);
      });
    }
  });

  group('delivery options', () {
    test('adds missing delivery keys and keeps the listed ones', () {
      final first = planBuildYaml(null, deliveryKeys: const ['7:a', '7:b']);
      expect(
        _builder(
          first.source,
          deliveryOptionsBuilderKey,
        )!['options']['delivery_keys'],
        ['7:a', '7:b'],
      );
      expect(first.written, contains('the delivery keys'));

      final again = planBuildYaml(
        first.source,
        deliveryKeys: const ['7:c', '7:a'],
      );
      expect(
        _builder(
          again.source,
          deliveryOptionsBuilderKey,
        )!['options']['delivery_keys'],
        ['7:a', '7:b', '7:c'],
      );
      expect(
        planBuildYaml(again.source, deliveryKeys: const ['7:a']).written,
        isEmpty,
      );

      final scalar = planBuildYaml(
        '''
targets:
  \$default:
    builders:
      restage_codegen:user_factories:
        options:
          delivery_keys: 7:a
''',
        deliveryKeys: const ['7:b'],
      );
      expect(scalar.kept, ['delivery_keys']);
    });

    test('writes the canonical service URL and the key', () {
      final plan = planBuildYaml(
        null,
        baseUrl: 'https://api.example.com/',
        apiKey: 'rs_pk_test',
      );
      final options = _builder(plan.source, deliveryOptionsBuilderKey)!;
      expect(options['options']['base_url'], 'https://api.example.com');
      expect(options['options']['api_key'], 'rs_pk_test');
      expect(plan.written, [
        'state file tracking',
        'the service URL',
        'the publishable key',
      ]);
      expect(plan.hasApiKey, isTrue);
    });

    test('keeps values already set and reports a different one', () {
      const source = '''
additional_public_assets:
  - .restage/measurement-state.json
  - .restage/wire-ids.events.jsonl
  - .restage/receipts/**
  - .restage/library-contracts/**
targets:
  \$default:
    builders:
      restage_codegen:user_factories:
        options:
          catalog: derived
          api_key: rs_pk_mine
''';
      final plan = planBuildYaml(
        source,
        baseUrl: 'https://api.example.com',
        apiKey: 'rs_pk_other',
      );
      final options =
          _builder(plan.source, deliveryOptionsBuilderKey)!['options']
              as YamlMap;
      expect(options['catalog'], 'derived');
      expect(options['api_key'], 'rs_pk_mine');
      expect(options['base_url'], 'https://api.example.com');
      expect(plan.kept, ['api_key']);
      expect(plan.hasApiKey, isTrue);
    });

    test('a file with a key reports it with no key given', () {
      const source = '''
additional_public_assets:
  - .restage/measurement-state.json
  - .restage/wire-ids.events.jsonl
  - .restage/receipts/**
  - .restage/library-contracts/**
targets:
  \$default:
    builders:
      restage_codegen:user_factories:
        options:
          api_key: rs_pk_mine
''';
      final plan = planBuildYaml(source);
      expect(plan.action, StateBuildInputsAction.keep);
      expect(plan.hasApiKey, isTrue);
    });

    test('moves options from the old builder and drops early_request', () {
      const source = '''
additional_public_assets:
  - .restage/measurement-state.json
  - .restage/wire-ids.events.jsonl
  - .restage/receipts/**
  - .restage/library-contracts/**
targets:
  \$default:
    builders:
      restage_codegen:restage_early_template:
        options:
          api_key: rs_pk_old
          base_url: https://old.example.com
          channel: beta
          early_request: false
      restage_codegen:outputs:
        options:
          bundled_runtime: true
''';
      final plan = planBuildYaml(source);
      expect(_builder(plan.source, legacyDeliveryOptionsBuilderKey), isNull);
      final options =
          _builder(plan.source, deliveryOptionsBuilderKey)!['options']
              as YamlMap;
      expect(options['api_key'], 'rs_pk_old');
      expect(options['base_url'], 'https://old.example.com');
      expect(options['channel'], 'beta');
      expect(
        _builder(
          plan.source,
          'restage_codegen:outputs',
        )!['options']['bundled_runtime'],
        isTrue,
      );
      expect(plan.written, [
        'moved api_key, base_url, channel from '
            'restage_codegen:restage_early_template',
      ]);
      expect(plan.hasApiKey, isTrue);
    });

    test('a value already in the new place wins over the old one', () {
      const source = '''
additional_public_assets:
  - .restage/measurement-state.json
  - .restage/wire-ids.events.jsonl
  - .restage/receipts/**
  - .restage/library-contracts/**
targets:
  \$default:
    builders:
      restage_codegen:restage_early_template:
        options:
          api_key: rs_pk_old
      restage_codegen:user_factories:
        options:
          api_key: rs_pk_new
''';
      final plan = planBuildYaml(source);
      expect(_builder(plan.source, legacyDeliveryOptionsBuilderKey), isNull);
      expect(
        _builder(plan.source, deliveryOptionsBuilderKey)!['options']['api_key'],
        'rs_pk_new',
      );
    });

    test('a blank old value is dropped and a URL moves canonically', () {
      const source = '''
additional_public_assets:
  - .restage/measurement-state.json
  - .restage/wire-ids.events.jsonl
  - .restage/receipts/**
  - .restage/library-contracts/**
targets:
  \$default:
    builders:
      restage_codegen:restage_early_template:
        options:
          api_key:
          base_url: https://api.example.com/
          channel: beta
''';
      final plan = planBuildYaml(
        source,
        apiKey: 'rs_pk_given',
        baseUrl: 'https://api.example.com',
      );
      final options =
          _builder(plan.source, deliveryOptionsBuilderKey)!['options']
              as YamlMap;
      expect(options['base_url'], 'https://api.example.com');
      expect(options['api_key'], 'rs_pk_given');
      expect(options['channel'], 'beta');
      // The moved URL matches the given one, so nothing is reported kept.
      expect(plan.kept, isEmpty);
    });

    test('a file the editor cannot change still reports a given key', () {
      final plan = planBuildYaml(
        'additional_public_assets: tool/a.json\n',
        apiKey: 'rs_pk_given',
      );
      expect(plan.action, StateBuildInputsAction.manual);
      expect(plan.hasApiKey, isTrue);
    });

    test('an opt-out alone is removed with its empty levels', () {
      const source = '''
additional_public_assets:
  - .restage/measurement-state.json
  - .restage/wire-ids.events.jsonl
  - .restage/receipts/**
  - .restage/library-contracts/**
targets:
  \$default:
    builders:
      restage_codegen:restage_early_template:
        options:
          early_request: false
''';
      final plan = planBuildYaml(source);
      expect(
        (loadYaml(plan.source) as YamlMap).containsKey('targets'),
        isFalse,
      );
      expect(plan.written, [
        'removed old restage_codegen:restage_early_template options',
      ]);
    });
  });
}
