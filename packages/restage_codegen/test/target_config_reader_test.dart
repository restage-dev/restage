import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/target_config_reader.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('target config reader', () {
    test('aggregate and shorthand A2UI facts merge by key', () async {
      final result = await runTargetConfigReadersOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@a2ui.Config(
  usage: 'Use the probe.',
  writeBackValues: {'onChanged': 'value'},
)
@a2ui.Config.usage('Use the probe.')
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.input,
)
class Probe {
  const Probe({
    required this.value,
    required this.count,
    required this.onChanged,
    required this.onCountChanged,
  });

  /// Current value.
  final String value;

  /// Current count.
  final int count;

  /// Reports a value change.
  final void Function(String) onChanged;

  /// Reports a count change.
  @a2ui.Config.writeBackValue('count')
  final void Function(int) onCountChanged;
}
''',
      });

      expect(result.issues, isEmpty);
      expect(result.usage, 'Use the probe.');
      expect(result.writeBackValues, {
        'onChanged': 'value',
        'onCountChanged': 'count',
      });
    });

    test('duplicate A2UI write-back pairings fail at both source paths',
        () async {
      final result = await runTargetConfigReadersOn({
        'lib/duplicate_pairing.dart': '''
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;

@a2ui.Config.writeBackValues({'onChanged': 'value'})
class Probe {
  const Probe({required this.value, required this.onChanged});

  final String value;

  @a2ui.Config.writeBackValue('value')
  final void Function(String) onChanged;
}
''',
      });

      final duplicates = result.issues
          .where((issue) => issue.code == IssueCode.duplicateTargetConfig)
          .toList();
      expect(duplicates, hasLength(2));
      expect(
        duplicates.map((issue) => issue.location),
        everyElement(startsWith('lib/duplicate_pairing.dart#Probe')),
      );
      expect(
        duplicates.map((issue) => issue.message),
        everyElement(contains('Duplicate A2UI write-back pairing')),
      );
    });

    test('identical duplicates coalesce and conflicts anchor both uses',
        () async {
      final identical = await runTargetConfigReadersOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;

@a2ui.Config.usage('Same')
@a2ui.Config.usage('Same')
class Probe {}
''',
      });
      expect(identical.issues, isEmpty);

      final conflicting = await runTargetConfigReadersOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;

@a2ui.Config.usage('First')
@a2ui.Config.usage('Second')
class Probe {}
''',
      });
      final conflicts = conflicting.issues
          .where((issue) => issue.code == IssueCode.conflictingTargetConfig)
          .toList();
      expect(conflicts, hasLength(2));
      expect(conflicts.map((issue) => issue.location).toSet(), hasLength(2));
      expect(conflicts.first.message, contains(conflicts[0].location));
      expect(conflicts.first.message, contains(conflicts[1].location));
    });

    test('lookalike Config is ignored by resolved defining-library identity',
        () async {
      final result = await runTargetConfigReadersOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Config {
  const Config({this.usage});
  final String? usage;
}

@Config(usage: 'Lookalike')
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.input,
)
class Probe {}
''',
      });

      expect(result.issues, isEmpty);
      expect(result.usage, isNull);
    });

    test('placement validation rejects class-only keys on a field', () async {
      final result = await runTargetConfigReadersOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;

class Probe {
  @a2ui.Config(usage: 'Wrong level')
  final String value = '';
}
''',
      });

      expect(
        result.issues.single.code,
        IssueCode.invalidTargetConfigPlacement,
      );
    });

    test('A2UI pairings resolve both constructor properties', () async {
      final result = await runTargetConfigReadersOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;

@a2ui.Config.writeBackValues({
  'missingCallback': 'value',
  'onChanged': 'missingValue',
  'value': 'onChanged',
})
class Probe {
  const Probe({required this.value, required this.onChanged});
  final String value;
  final void Function(String) onChanged;
}
''',
      });

      final issues = result.issues
          .where(
            (issue) => issue.code == IssueCode.invalidTargetConfigReference,
          )
          .toList();
      expect(issues, hasLength(4));
      expect(
        issues.map((issue) => issue.message),
        containsAll([
          contains('"missingCallback" is not an input'),
          contains('"missingValue" is not an input'),
          contains('"value" on Probe must resolve to a callback'),
          contains('"onChanged" on Probe must resolve to a non-callback'),
        ]),
      );
    });

    test('Widgetbook consumes only the intentional A2UI usage mirror',
        () async {
      const sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;

@a2ui.Config(
  usage: 'Use the probe.',
  writeBackValues: {'missingCallback': 'missingValue'},
)
class Probe {
  const Probe({required this.value});
  final String value;
}
''',
      };

      final a2ui = await runTargetConfigReadersOn(sources);
      final widgetbook = await runTargetConfigReadersOn(
        sources,
        a2uiConsumer: A2uiTargetConfigConsumer.widgetbookMetadata,
      );

      expect(
        a2ui.issues.where(
          (issue) => issue.code == IssueCode.invalidTargetConfigReference,
        ),
        hasLength(2),
      );
      expect(widgetbook.usage, 'Use the probe.');
      expect(widgetbook.writeBackValues, isEmpty);
      expect(widgetbook.issues, isEmpty);
    });
  });
}
