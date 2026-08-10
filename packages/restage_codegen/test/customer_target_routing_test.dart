import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('per-widget target routing', () {
    test('one package supports default, solo, and pairwise target sets',
        () async {
      const sources = {'lib/routing.dart': _widgetTargetMatrixSource};
      final expected = <WidgetVisitorTarget, Set<String>>{
        WidgetVisitorTarget.rfw: {
          'DefaultCard',
          'RfwOnlyCard',
          'RfwA2uiCard',
          'RfwWidgetbookCard',
        },
        WidgetVisitorTarget.a2ui: {
          'DefaultCard',
          'A2uiOnlyCard',
          'RfwA2uiCard',
          'A2uiWidgetbookCard',
        },
        WidgetVisitorTarget.widgetbook: {
          'DefaultCard',
          'WidgetbookOnlyCard',
          'RfwWidgetbookCard',
          'A2uiWidgetbookCard',
        },
      };

      for (final target in WidgetVisitorTarget.values) {
        final result = await runWidgetVisitorOn(sources, target: target);
        expect(result.issues, isEmpty, reason: target.name);
        expect(
          result.widgets.map((widget) => widget.name).toSet(),
          expected[target],
          reason: target.name,
        );
      }
    });

    test('disabled widget exits before constructor and capability validation',
        () async {
      const sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

final runtimeUsage = DateTime.now().toIso8601String();

@a2ui.Config.enabled(false)
@a2ui.Config(usage: runtimeUsage)
@a2ui.Config.usage(runtimeUsage)
@a2ui.Config.writeBackValues({'missing': 'alsoMissing'})
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
  description: 'A target routing probe.',
)
class Probe {
  const Probe.named(this.hostObject);
  final Object hostObject;
}
''',
      };

      final a2ui = await runWidgetVisitorOn(
        sources,
        target: WidgetVisitorTarget.a2ui,
      );
      final rfw = await runWidgetVisitorOn(sources);

      expect(a2ui.widgets, isEmpty);
      expect(a2ui.issues, isEmpty);
      expect(
        rfw.issues.map((issue) => issue.code),
        contains(IssueCode.invalidWidgetConstructorInput),
      );
    });

    test('disabled widget exits before library ownership resolution', () async {
      const sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@a2ui.Config.enabled(false)
@RestageWidget()
class Probe {
  const Probe();
}
''',
      };

      final a2ui = await runWidgetVisitorOn(
        sources,
        target: WidgetVisitorTarget.a2ui,
      );
      final rfw = await runWidgetVisitorOn(sources);

      expect(a2ui.widgets, isEmpty);
      expect(a2ui.issues, isEmpty);
      expect(
        rfw.issues.map((issue) => issue.message),
        contains(contains('omits `library`')),
      );
    });

    test('disabled widget exits before target duplicate checks', () async {
      const sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// First duplicate-routing probe.
@RestageWidget(
  name: 'SharedName',
  library: WidgetLibrary.custom('acme.widgets'),
)
class FirstProbe {
  const FirstProbe();
}

/// Second duplicate-routing probe.
@a2ui.Config.enabled(false)
@RestageWidget(
  name: 'SharedName',
  library: WidgetLibrary.custom('acme.widgets'),
)
class SecondProbe {
  const SecondProbe();
}
''',
      };

      final a2ui = await runWidgetVisitorOn(
        sources,
        target: WidgetVisitorTarget.a2ui,
      );
      final rfw = await runWidgetVisitorOn(sources);

      expect(a2ui.issues, isEmpty);
      expect(a2ui.widgets.map((widget) => widget.name), ['SharedName']);
      expect(
        rfw.issues.map((issue) => issue.code),
        contains(IssueCode.duplicateWidgetName),
      );
    });

    test('rejects inherited property placement of class-only enabled',
        () async {
      const sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class BaseProbe {
  const BaseProbe({this.label = ''});

  @a2ui.Config.enabled(false)
  @RestageProperty(description: 'Visible label.')
  final String label;
}

/// Inherited placement probe.
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
)
class Probe extends BaseProbe {
  const Probe({super.label});
}
''',
      };

      final result = await runWidgetVisitorOn(
        sources,
        target: WidgetVisitorTarget.a2ui,
      );

      expect(result.widgets, isEmpty);
      expect(
        result.issues.map((issue) => issue.code),
        contains(IssueCode.invalidTargetConfigPlacement),
      );
      expect(
        result.issues.map((issue) => issue.location),
        contains('lib/probe.dart#Probe.label@a2ui.Config[0]'),
      );
    });
  });

  group('selective Ignore routing', () {
    test('neutral facts retain targets in public enum order', () async {
      final facts = await runWidgetConstructorFactsOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Probe {
  const Probe({
    @Ignore([
      EmitTarget.widgetbook,
      EmitTarget.a2ui,
      EmitTarget.widgetbook,
    ])
    this.label = '',
  });

  final String label;
}
''',
      });

      expect(facts.issues, isEmpty);
      expect(
        facts.inputs.single.ignoreTargets!.toList(),
        [EmitTarget.a2ui, EmitTarget.widgetbook],
      );
    });

    test('list, set, aliases, duplicates, and order normalize by target',
        () async {
      const sources = {'lib/ignore_matrix.dart': _ignoreMatrixSource};
      final expected = <WidgetVisitorTarget, List<String>>{
        WidgetVisitorTarget.rfw: ['nativeHidden'],
        WidgetVisitorTarget.a2ui: ['rfwHidden', 'edgeHidden'],
        WidgetVisitorTarget.widgetbook: ['rfwHidden'],
      };

      for (final target in WidgetVisitorTarget.values) {
        final result = await runWidgetVisitorOn(sources, target: target);
        expect(result.issues, isEmpty, reason: target.name);
        expect(
          result.widgets.single.properties.map((property) => property.name),
          expected[target],
          reason: target.name,
        );
        expect(
          result.exclusions,
          isEmpty,
          reason: 'authored routing must stay distinct from automatic '
              'decoder exclusions (${target.name})',
        );
      }
    });

    test('explicit empty selection fails loudly instead of becoming a no-op',
        () async {
      const sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Empty target-selection probe.
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
)
class Probe {
  const Probe({@Ignore(<EmitTarget>[]) this.label = ''});
  /// Visible label.
  @RestageProperty(description: 'Visible label.')
  final String label;
}
''',
      };

      for (final target in WidgetVisitorTarget.values) {
        final result = await runWidgetVisitorOn(sources, target: target);
        final issue = result.issues.singleWhere(
          (candidate) =>
              candidate.code == IssueCode.invalidWidgetConstructorInput,
        );
        expect(issue.message, contains('must not be empty'));
      }
    });

    test('custom const Iterable fails with a const list or set diagnostic',
        () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class CustomTargets extends Iterable<EmitTarget> {
  const CustomTargets();

  @override
  Iterator<EmitTarget> get iterator => const <EmitTarget>[].iterator;
}

/// Custom iterable probe.
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
)
class Probe {
  const Probe({@Ignore(CustomTargets()) this.label = ''});
  /// Visible label.
  @RestageProperty(description: 'Visible label.')
  final String label;
}
''',
      });

      final issue = result.issues.singleWhere(
        (candidate) =>
            candidate.code == IssueCode.invalidWidgetConstructorInput,
      );
      expect(issue.message, contains('const list or set'));
    });

    test('foreign EmitTarget members fail resolved enum identity', () async {
      final result = await runWidgetVisitorOn({
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart' hide EmitTarget;

enum EmitTarget { rfw, a2ui, widgetbook }

/// Foreign enum probe.
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
)
class Probe {
  const Probe({@Ignore(<dynamic>[EmitTarget.a2ui]) this.label = ''});
  /// Visible label.
  final String label;
}
''',
      });

      final issue = result.issues.singleWhere(
        (candidate) =>
            candidate.code == IssueCode.invalidWidgetConstructorInput,
      );
      expect(issue.message, contains('rfw_catalog_schema'));
      expect(issue.message, contains('EmitTarget'));
    });

    test('required and assert-required errors affect only selected target',
        () async {
      const sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Required selective exclusion probe.
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
)
class Probe {
  const Probe({
    @Ignore({EmitTarget.a2ui}) required this.requiredValue,
    @Ignore({EmitTarget.a2ui}) this.assertedValue,
  }) : assert(assertedValue != null);

  /// Required value.
  final String requiredValue;

  /// Assert-required value.
  final String? assertedValue;
}
''',
      };

      final a2ui = await runWidgetVisitorOn(
        sources,
        target: WidgetVisitorTarget.a2ui,
      );
      expect(
        a2ui.issues
            .where(
              (issue) => issue.code == IssueCode.invalidWidgetConstructorInput,
            )
            .map((issue) => issue.location)
            .toSet(),
        {
          'lib/probe.dart#Probe.requiredValue',
          'lib/probe.dart#Probe.assertedValue',
        },
      );

      for (final target in const [
        WidgetVisitorTarget.rfw,
        WidgetVisitorTarget.widgetbook,
      ]) {
        final sibling = await runWidgetVisitorOn(sources, target: target);
        expect(
          sibling.issues.where(
            (issue) => issue.code == IssueCode.invalidWidgetConstructorInput,
          ),
          isEmpty,
          reason: target.name,
        );
        expect(
          sibling.widgets.single.properties.map((property) => property.name),
          ['requiredValue', 'assertedValue'],
          reason: target.name,
        );
      }
    });

    test('positional hole fails only the selected target', () async {
      const sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Positional selective exclusion probe.
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
)
class Probe {
  const Probe([
    @Ignore({EmitTarget.a2ui}) this.internal = 0,
    this.label = 'visible',
  ]);

  /// Internal value.
  @RestageProperty(description: 'Internal value.')
  final int internal;

  /// Visible label.
  @RestageProperty(description: 'Visible label.')
  final String label;
}
''',
      };

      final a2ui = await runWidgetVisitorOn(
        sources,
        target: WidgetVisitorTarget.a2ui,
      );
      final issue = a2ui.issues.singleWhere(
        (candidate) =>
            candidate.code == IssueCode.invalidWidgetConstructorInput,
      );
      expect(issue.message, contains('@Ignore'));
      expect(issue.message, contains('shift'));

      for (final target in const [
        WidgetVisitorTarget.rfw,
        WidgetVisitorTarget.widgetbook,
      ]) {
        final sibling = await runWidgetVisitorOn(sources, target: target);
        expect(sibling.issues, isEmpty, reason: target.name);
        expect(
          sibling.widgets.single.properties.map((property) => property.name),
          ['internal', 'label'],
          reason: target.name,
        );
      }
    });

    test('positional omission is valid when every later input is auto-excluded',
        () async {
      const sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Positional final-set probe.
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
)
class Probe {
  const Probe([
    @Ignore({EmitTarget.a2ui}) this.label = '',
    this.hostObject,
  ]);

  /// Visible label.
  @RestageProperty(description: 'Visible label.')
  final String label;

  /// Host-only object.
  @RestageProperty(description: 'Host-only object.')
  final Object? hostObject;
}
''',
      };

      final result = await runWidgetVisitorOn(
        sources,
        target: WidgetVisitorTarget.a2ui,
      );

      expect(result.issues, isEmpty);
      expect(result.widgets, hasLength(1));
      expect(result.widgets.single.properties, isEmpty);
      expect(
        result.exclusions.map((exclusion) => exclusion.property),
        ['hostObject'],
      );
    });

    test('selective Ignore retains migration notices on included siblings',
        () async {
      const sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Migration routing probe.
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
)
class Probe {
  const Probe({@Ignore({EmitTarget.a2ui}) this.label = ''});

  /// Visible label.
  final String label;
}
''',
      };

      final a2ui = await runWidgetVisitorOn(
        sources,
        target: WidgetVisitorTarget.a2ui,
      );
      expect(
        a2ui.issues.where(
          (issue) => issue.code == IssueCode.constructorCatalogMigration,
        ),
        isEmpty,
      );

      for (final target in const [
        WidgetVisitorTarget.rfw,
        WidgetVisitorTarget.widgetbook,
      ]) {
        final sibling = await runWidgetVisitorOn(sources, target: target);
        final notices = sibling.issues
            .where(
              (issue) => issue.code == IssueCode.constructorCatalogMigration,
            )
            .toList();
        expect(notices, hasLength(1), reason: target.name);
        expect(
          notices.single.location,
          'lib/probe.dart#Probe.label',
          reason: target.name,
        );
        expect(
          sibling.widgets.single.properties.map((property) => property.name),
          ['label'],
          reason: target.name,
        );
      }
    });

    test('selective Ignore compares migration order among surviving fields',
        () async {
      final sources = {
        'lib/probe.dart': _orderMigrationSource(
          '@Ignore({EmitTarget.a2ui})',
        ),
      };

      for (final target in WidgetVisitorTarget.values) {
        final result = await runWidgetVisitorOn(sources, target: target);
        final notices = result.issues
            .where(
              (issue) =>
                  issue.code == IssueCode.constructorCatalogMigration &&
                  issue.location == 'lib/probe.dart#Probe',
            )
            .toList();
        expect(notices, hasLength(1), reason: target.name);
        expect(
          notices.single.message,
          allOf(
            contains('For the ${target.name} target'),
            target == WidgetVisitorTarget.a2ui
                ? allOf(contains('second, first'), contains('first, second'))
                : allOf(
                    contains('hidden, second, first'),
                    contains('hidden, first, second'),
                  ),
          ),
          reason: target.name,
        );
      }
    });

    test('selective Ignore removes unreachable structured closure by target',
        () async {
      const sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class ProbeData {
  const ProbeData({required this.label});

  @RestageProperty(description: 'Structured label.')
  final String label;
}

/// Structured routing probe.
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
)
class Probe {
  const Probe({
    @Ignore({EmitTarget.a2ui, EmitTarget.widgetbook}) this.data,
    this.title = '',
  });

  /// Optional structured data.
  final ProbeData? data;

  /// Visible title.
  final String title;
}
''',
      };

      final rfw = await runWidgetVisitorOn(sources);
      expect(
        rfw.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      expect(
        rfw.widgets.single.properties.map((property) => property.name),
        ['data', 'title'],
      );
      expect(rfw.structuredTypes.map((entry) => entry.name), ['ProbeData']);

      for (final target in const [
        WidgetVisitorTarget.a2ui,
        WidgetVisitorTarget.widgetbook,
      ]) {
        final result = await runWidgetVisitorOn(sources, target: target);
        expect(
          result.issues.where((issue) => !issue.code.isInformational),
          isEmpty,
          reason: target.name,
        );
        expect(
          result.widgets.single.properties.map((property) => property.name),
          ['title'],
          reason: target.name,
        );
        expect(result.structuredTypes, isEmpty, reason: target.name);
        expect(result.slotTargets, isEmpty, reason: target.name);
      }
    });

    test('selective callback routing preserves target-local write-back closure',
        () async {
      const widgetbookOmission = {
        'lib/probe.dart': _callbackRoutingSource,
      };

      for (final target in const [
        WidgetVisitorTarget.rfw,
        WidgetVisitorTarget.a2ui,
      ]) {
        final result = await runWidgetVisitorOn(
          widgetbookOmission,
          target: target,
        );
        expect(
          result.issues.where((issue) => !issue.code.isInformational),
          isEmpty,
          reason: target.name,
        );
        expect(
          result.widgets.single.properties.map((property) => property.name),
          ['value', 'onChanged'],
          reason: target.name,
        );
      }

      final widgetbook = await runWidgetVisitorOn(
        widgetbookOmission,
        target: WidgetVisitorTarget.widgetbook,
      );
      expect(
        widgetbook.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      expect(
        widgetbook.widgets.single.properties.map((property) => property.name),
        ['value'],
      );
    });

    test('same-target double projection keeps one order migration notice',
        () async {
      final facts = await runProjectedWidgetConstructorFactsOn(
        {
          'lib/probe.dart': _orderMigrationSource(
            '@Ignore({EmitTarget.a2ui})',
          ),
        },
        target: EmitTarget.a2ui,
        projections: 2,
        emittedPropertyNames: const {'first', 'second'},
      );

      expect(
        facts.issues.where(
          (issue) =>
              issue.code == IssueCode.constructorCatalogMigration &&
              issue.location == 'lib/probe.dart#Probe',
        ),
        hasLength(1),
      );
    });

    test(
        'invalid selective positional omission does not change order '
        'diagnostics', () async {
      const sources = {
        'lib/probe.dart': _positionalOrderMigrationSource,
      };

      final a2ui = await runWidgetVisitorOn(
        sources,
        target: WidgetVisitorTarget.a2ui,
      );
      expect(
        a2ui.issues.where(
          (issue) =>
              issue.code == IssueCode.invalidWidgetConstructorInput &&
              issue.message.contains('shift'),
        ),
        hasLength(1),
      );
      expect(
        a2ui.issues.where(
          (issue) =>
              issue.code == IssueCode.constructorCatalogMigration &&
              issue.location == 'lib/probe.dart#Probe',
        ),
        isEmpty,
      );

      for (final target in const [
        WidgetVisitorTarget.rfw,
        WidgetVisitorTarget.widgetbook,
      ]) {
        final sibling = await runWidgetVisitorOn(sources, target: target);
        expect(
          sibling.issues.where(
            (issue) =>
                issue.code == IssueCode.constructorCatalogMigration &&
                issue.location == 'lib/probe.dart#Probe',
          ),
          hasLength(1),
          reason: target.name,
        );
      }
    });

    test('legacy all-target Ignore keeps historical order diagnostics',
        () async {
      final sources = {
        'lib/probe.dart': _orderMigrationSource('@Ignore()'),
      };

      final neutral = await runWidgetConstructorFactsOn(sources);
      expect(
        neutral.issues.where(
          (issue) => issue.code == IssueCode.constructorCatalogMigration,
        ),
        isEmpty,
      );
      for (final target in WidgetVisitorTarget.values) {
        final result = await runWidgetVisitorOn(sources, target: target);
        expect(
          result.issues.where(
            (issue) => issue.code == IssueCode.constructorCatalogMigration,
          ),
          isEmpty,
          reason: target.name,
        );
      }
    });
  });
}

String _orderMigrationSource(String ignore) => '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Order migration routing probe.
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
)
class Probe {
  const Probe({
    $ignore this.hidden = '',
    this.first = '',
    this.second = '',
  });

  @RestageProperty(description: 'Target-hidden value.')
  final String hidden;

  @RestageProperty(description: 'Second field.')
  final String second;

  @RestageProperty(description: 'First field.')
  final String first;
}
''';

const _positionalOrderMigrationSource = '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Invalid positional order migration probe.
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
)
class Probe {
  const Probe([
    @Ignore({EmitTarget.a2ui}) this.hidden = '',
    this.first = '',
    this.second = '',
  ]);

  @RestageProperty(description: 'Target-hidden value.')
  final String hidden;

  @RestageProperty(description: 'Second field.')
  final String second;

  @RestageProperty(description: 'First field.')
  final String first;
}
''';

const _callbackRoutingSource = '''
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Callback routing probe.
@a2ui.Config.writeBackValues({'onChanged': 'value'})
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
)
class Probe {
  const Probe({
    this.value = '',
    @Ignore({EmitTarget.widgetbook}) this.onChanged,
  });

  /// Current value.
  final String value;

  /// Reports a changed value.
  final void Function(String)? onChanged;
}
''';

const _widgetTargetMatrixSource = '''
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw.dart' as rfw;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

@RestageWidget(name: 'DefaultCard', library: WidgetLibrary.custom('acme.widgets'))
/// Default target card.
class DefaultCard { const DefaultCard(); }

@a2ui.Config.enabled(false)
@wb.Config.enabled(false)
@RestageWidget(name: 'RfwOnlyCard', library: WidgetLibrary.custom('acme.widgets'))
/// RFW-only card.
class RfwOnlyCard { const RfwOnlyCard(); }

@rfw.Config.enabled(false)
@wb.Config.enabled(false)
@RestageWidget(name: 'A2uiOnlyCard', library: WidgetLibrary.custom('acme.widgets'))
/// A2UI-only card.
class A2uiOnlyCard { const A2uiOnlyCard(); }

@rfw.Config.enabled(false)
@a2ui.Config.enabled(false)
@RestageWidget(name: 'WidgetbookOnlyCard', library: WidgetLibrary.custom('acme.widgets'))
/// Widgetbook-only card.
class WidgetbookOnlyCard { const WidgetbookOnlyCard(); }

@wb.Config.enabled(false)
@RestageWidget(name: 'RfwA2uiCard', library: WidgetLibrary.custom('acme.widgets'))
/// RFW and A2UI card.
class RfwA2uiCard { const RfwA2uiCard(); }

@a2ui.Config.enabled(false)
@RestageWidget(name: 'RfwWidgetbookCard', library: WidgetLibrary.custom('acme.widgets'))
/// RFW and Widgetbook card.
class RfwWidgetbookCard { const RfwWidgetbookCard(); }

@rfw.Config.enabled(false)
@RestageWidget(name: 'A2uiWidgetbookCard', library: WidgetLibrary.custom('acme.widgets'))
/// A2UI and Widgetbook card.
class A2uiWidgetbookCard { const A2uiWidgetbookCard(); }
''';

const _ignoreMatrixSource = '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const nativeTargets = <EmitTarget>[
  EmitTarget.widgetbook,
  EmitTarget.a2ui,
  EmitTarget.a2ui,
];
const edgeTargets = <EmitTarget>{
  EmitTarget.widgetbook,
  EmitTarget.rfw,
};
const firstTargets = <EmitTarget>[EmitTarget.rfw, EmitTarget.a2ui];

/// Selective exclusion matrix.
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
)
class Probe {
  const Probe({
    @ignore this.global = '',
    @Ignore([EmitTarget.rfw]) this.rfwHidden = '',
    @Ignore(nativeTargets) this.nativeHidden = '',
    @Ignore(edgeTargets) this.edgeHidden = '',
    @Ignore([...firstTargets, EmitTarget.widgetbook]) this.spreadHidden = '',
    @Ignore(EmitTarget.values) this.valuesHidden = '',
  });

  @RestageProperty(description: 'Hidden from every target.')
  final String global;

  /// Hidden only from RFW.
  @RestageProperty(description: 'Hidden only from RFW.')
  final String rfwHidden;

  /// Hidden from native siblings.
  @RestageProperty(description: 'Hidden from native siblings.')
  final String nativeHidden;

  /// Hidden from the edge target pair.
  @RestageProperty(description: 'Hidden from the edge target pair.')
  final String edgeHidden;

  @RestageProperty(description: 'Hidden from the first target set.')
  final String spreadHidden;

  @RestageProperty(description: 'Hidden from every enumerated target.')
  final String valuesHidden;
}
''';
