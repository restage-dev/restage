import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/target_config_reader.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' show StoryExpansion;
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

    test('Widgetbook skips unevaluable A2UI-only config before evaluation',
        () async {
      const sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;

final runtimeEnabled = DateTime.now().isUtc;
final runtimePairings = <String, String>{'onChanged': 'value'};

@a2ui.Config(enabled: runtimeEnabled)
@a2ui.Config.enabled(runtimeEnabled)
@a2ui.Config.writeBackValues(runtimePairings)
class Probe {
  const Probe({required this.value, required this.onChanged});
  final String value;
  final void Function(String) onChanged;
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
          (issue) => issue.code == IssueCode.missingAnnotationField,
        ),
        hasLength(3),
      );
      expect(widgetbook.usage, isNull);
      expect(widgetbook.writeBackValues, isEmpty);
      expect(widgetbook.issues, isEmpty);
    });
  });

  group('Widgetbook target config reader', () {
    test('aggregate and shorthands merge by exact key and typed value',
        () async {
      final result = await runWidgetbookTargetConfigReaderOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

enum Mode { idle, ready }

@wb.Config(
  expansion: wb.StoryExpansion.cartesian,
  maxStories: 12,
)
@wb.Config.expansion(wb.StoryExpansion.cartesian)
@wb.Config.maxStories(12)
class Probe {
  const Probe({required this.enabled, required this.mode});

  @wb.Config.values([false, true])
  @wb.Config.values([false, true])
  final bool enabled;

  @wb.Config.allValues()
  final Mode? mode;
}
''',
      });

      expect(result.issues, isEmpty);
      expect(result.expansion, StoryExpansion.cartesian);
      expect(result.maxStories, 12);
      expect(
        result.properties['enabled']!.storyValues!
            .map((value) => value.toBoolValue()),
        [false, true],
      );
      expect(result.properties['enabled']!.allValues, isFalse);
      expect(result.properties['mode']!.allValues, isTrue);
      expect(result.properties['mode']!.storyValues, isNull);
    });

    test('expansion aliases canonicalize and merge with a direct member',
        () async {
      final result = await runWidgetbookTargetConfigReaderOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

const cartesianAlias = wb.StoryExpansion.cartesian;
const chainedCartesianAlias = cartesianAlias;

@wb.Config(expansion: chainedCartesianAlias)
@wb.Config.expansion(wb.StoryExpansion.cartesian)
class Probe {
  const Probe();
}
''',
      });

      expect(result.issues, isEmpty);
      expect(result.expansion, StoryExpansion.cartesian);
    });

    test('property enum aliases canonicalize and merge with a direct member',
        () async {
      final result = await runWidgetbookTargetConfigReaderOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

enum Mode { idle, ready }

const readyAlias = Mode.ready;
const chainedReadyAlias = readyAlias;

class Probe {
  const Probe({this.mode = Mode.idle});

  @wb.Config(storyValues: [chainedReadyAlias])
  @wb.Config.values([Mode.ready])
  final Mode mode;
}
''',
      });

      expect(result.issues, isEmpty);
      final value = result.properties['mode']!.storyValues!.single;
      final variable = value.variable;
      expect(variable, isA<FieldElement>());
      expect((variable! as FieldElement).isEnumConstant, isTrue);
      expect(variable.name, 'ready');
      expect(variable.enclosingElement?.name, 'Mode');
      expect(variable.library?.identifier, 'package:apps_examples/probe.dart');
    });

    test('lookalike and const-variable annotations are ignored', () async {
      final result = await runWidgetbookTargetConfigReaderOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

class Config {
  const Config({this.maxStories});
  final int? maxStories;
}

const indirect = wb.Config.maxStories(99);

@Config(maxStories: 41)
@indirect
class Probe {}
''',
      });

      expect(result.issues, isEmpty);
      expect(result.expansion, isNull);
      expect(result.maxStories, isNull);
      expect(result.properties, isEmpty);
    });

    test('malformed genuine annotation fails loudly', () async {
      final result = await runWidgetbookTargetConfigReaderOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

final runtimeValues = <Object?>[false, true];

class Probe {
  const Probe({this.enabled = false});

  @wb.Config.values(runtimeValues)
  final bool enabled;
}
''',
      });

      expect(result.issues, hasLength(1));
      expect(result.issues.single.code, IssueCode.missingAnnotationField);
      expect(
        result.issues.single.message,
        contains('could not be const-evaluated'),
      );
      expect(
        result.issues.single.location,
        contains('#Probe.enabled@wb.Config'),
      );
    });

    test('class-only and field-only keys reject the wrong placement', () async {
      final result = await runWidgetbookTargetConfigReaderOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

@wb.Config.values([false, true])
class Probe {
  @wb.Config.maxStories(4)
  final bool enabled = false;
}
''',
      });

      final placements = result.issues
          .where(
            (issue) => issue.code == IssueCode.invalidTargetConfigPlacement,
          )
          .toList();
      expect(placements, hasLength(2));
      expect(
        placements.map((issue) => issue.location),
        containsAll([contains('#Probe@'), contains('#Probe.enabled@')]),
      );
    });

    test('constructor-formal placement fails loudly', () async {
      final result = await runWidgetbookTargetConfigReaderOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

class Probe {
  const Probe({
    @wb.Config.allValues() this.enabled = false,
  });

  final bool enabled;
}
''',
      });

      expect(result.properties, isEmpty);
      expect(
        result.issues,
        contains(
          isA<Issue>()
              .having(
                (issue) => issue.code,
                'code',
                IssueCode.invalidTargetConfigPlacement,
              )
              .having(
                (issue) => issue.message,
                'message',
                contains('constructor formal'),
              )
              .having(
                (issue) => issue.location,
                'location',
                contains('#Probe.new.enabled@wb.Config'),
              ),
        ),
      );
    });

    test('field config is keyed by its admitted ordinary formal name',
        () async {
      final result = await runWidgetbookTargetConfigReaderOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

class Probe {
  const Probe({bool isEnabled = false}) : enabled = isEnabled;

  @wb.Config.allValues()
  final bool enabled;
}
''',
      });

      expect(result.issues, isEmpty);
      expect(result.properties.keys, ['isEnabled']);
      expect(result.properties.values.single.allValues, isTrue);
    });

    test('same-name non-backing field config is rejected by exact identity',
        () async {
      final result = await runWidgetbookTargetConfigReaderOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

class Probe {
  const Probe({bool enabled = false}) : storedEnabled = enabled;

  @wb.Config.allValues()
  final bool enabled = false;

  final bool storedEnabled;
}
''',
      });

      expect(result.properties, isEmpty);
      expect(
        result.issues,
        contains(
          isA<Issue>()
              .having(
                (issue) => issue.code,
                'code',
                IssueCode.invalidTargetConfigPlacement,
              )
              .having(
                (issue) => issue.location,
                'location',
                contains('lib/probe.dart#Probe.enabled@wb.Config'),
              ),
        ),
      );
    });

    test('inherited formal chain is rejected at each defining source',
        () async {
      final result = await runWidgetbookTargetConfigReaderOn({
        'lib/base.dart': '''
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

class BaseProbe {
  const BaseProbe({
    @wb.Config.allValues() this.enabled = false,
  });

  final bool enabled;
}
''',
        'lib/middle.dart': '''
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;
import 'base.dart';

class MiddleProbe extends BaseProbe {
  const MiddleProbe({
    @wb.Config.allValues() super.enabled,
  });
}
''',
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;
import 'middle.dart';

class Probe extends MiddleProbe {
  const Probe({
    @wb.Config.allValues() super.enabled,
  });
}
''',
      });

      final placements = result.issues
          .where(
            (issue) => issue.code == IssueCode.invalidTargetConfigPlacement,
          )
          .toList();
      expect(result.properties, isEmpty);
      expect(placements, hasLength(3));
      expect(
        placements.map((issue) => issue.location).toSet(),
        {
          'lib/probe.dart#Probe.new.enabled@wb.Config[0]',
          'lib/middle.dart#MiddleProbe.new.enabled@wb.Config[0]',
          'lib/base.dart#BaseProbe.new.enabled@wb.Config[0]',
        },
      );
    });

    test('exact inherited backing field config remains legal and source-bound',
        () async {
      final result = await runWidgetbookTargetConfigReaderOn({
        'lib/base.dart': '''
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

class BaseProbe {
  const BaseProbe({this.enabled = false});

  @wb.Config.allValues()
  final bool enabled;
}
''',
        'lib/probe.dart': '''
import 'base.dart';

class Probe extends BaseProbe {
  const Probe({super.enabled});
}
''',
      });

      expect(result.issues, isEmpty);
      expect(result.properties.keys, ['enabled']);
      expect(result.properties['enabled']!.allValues, isTrue);
      expect(
        result.properties['enabled']!.allValuesLocation,
        'lib/base.dart#BaseProbe.enabled@wb.Config[0]',
      );
    });

    test('inherited non-backing field is rejected at its defining source',
        () async {
      final result = await runWidgetbookTargetConfigReaderOn({
        'lib/base.dart': '''
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

class BaseProbe {
  const BaseProbe({this.enabled = false});

  final bool enabled;

  @wb.Config.allValues()
  final bool unrelated = false;
}
''',
        'lib/probe.dart': '''
import 'base.dart';

class Probe extends BaseProbe {
  const Probe({super.enabled});
}
''',
      });

      expect(result.properties, isEmpty);
      expect(
        result.issues.single,
        isA<Issue>()
            .having(
              (issue) => issue.code,
              'code',
              IssueCode.invalidTargetConfigPlacement,
            )
            .having(
              (issue) => issue.location,
              'location',
              'lib/base.dart#BaseProbe.unrelated@wb.Config[0]',
            ),
      );
    });

    test('field config fails loudly when constructor facts are unavailable',
        () async {
      final result = await runWidgetbookTargetConfigReaderOn(
        {
          'lib/probe.dart': '''
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

class Probe {
  const Probe({this.enabled = false});

  @wb.Config.allValues()
  final bool enabled;
}
''',
        },
        includeConstructorFacts: false,
      );

      expect(result.properties, isEmpty);
      expect(
        result.issues.single,
        isA<Issue>()
            .having(
              (issue) => issue.code,
              'code',
              IssueCode.invalidTargetConfigPlacement,
            )
            .having(
              (issue) => issue.message,
              'message',
              contains('constructor facts are unavailable'),
            ),
      );
    });

    test('conflicting keys and mutually exclusive selectors anchor both uses',
        () async {
      final result = await runWidgetbookTargetConfigReaderOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

@wb.Config.expansion(wb.StoryExpansion.independent)
@wb.Config.expansion(wb.StoryExpansion.cartesian)
class Probe {
  const Probe({this.enabled = false});

  @wb.Config.values([false, true])
  @wb.Config.allValues()
  final bool enabled;
}
''',
      });

      final conflicts = result.issues
          .where((issue) => issue.code == IssueCode.conflictingTargetConfig)
          .toList();
      expect(conflicts, hasLength(4));
      expect(
        conflicts.map((issue) => issue.message),
        containsAll([
          contains('expansion'),
          contains('storyValues and allValues are mutually exclusive'),
        ]),
      );
      expect(conflicts.map((issue) => issue.location).toSet(), hasLength(4));
    });
  });
}
