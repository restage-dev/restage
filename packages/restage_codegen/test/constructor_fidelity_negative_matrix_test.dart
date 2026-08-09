import 'package:restage_codegen/src/dart_import_planner.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widget_constructor_facts.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _annotation = '''
@RestageWidget(
  name: 'Probe',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.input,
)
''';

void main() {
  group('constructor-fidelity rejected matrix', () {
    test('required host plumbing fails and optional plumbing stays reported',
        () async {
      const sourcePath = 'lib/host_plumbing.dart';
      const sources = {
        sourcePath: '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Host-plumbing rejection probe.
$_annotation
class Probe {
  const Probe({required this.requiredNode, this.optionalNode});

  /// Required host-owned state.
  final FocusNode requiredNode;

  /// Optional host-owned state.
  final FocusNode? optionalNode;
}
''',
      };
      final facts = await runWidgetConstructorFactsOn(sources);
      expect(
        facts.inputs.map((input) => input.name),
        containsAll(<String>['requiredNode', 'optionalNode']),
        reason: 'the source inputs must exist before target rejection',
      );

      for (final target in WidgetVisitorTarget.values) {
        final result = await runWidgetVisitorOn(sources, target: target);
        expect(result.widgets.single.name, 'Probe', reason: target.name);
        final failure = result.issues.singleWhere(
          (issue) =>
              issue.location == '$sourcePath#Probe.requiredNode' &&
              issue.code == IssueCode.unsupportedPropertyType,
        );
        expect(failure.message, contains('Target: ${target.name}'));
        final exclusion = result.exclusions.singleWhere(
          (candidate) => candidate.property == 'optionalNode',
        );
        expect(exclusion.location, '$sourcePath#Probe.optionalNode');
        expect(exclusion.target, target.name);
        expect(exclusion.reason, contains('Target: ${target.name}'));
      }
    });

    test('private defaults fail at the input path for each wire target',
        () async {
      const sourcePath = 'lib/private_default.dart';
      const sources = {
        sourcePath: '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const _privateDefault = 7;

/// Private-default rejection probe.
$_annotation
class Probe {
  const Probe({this.count = _privateDefault});

  /// Visible count.
  final int count;
}
''',
      };
      final facts = await runWidgetConstructorFactsOn(sources);
      expect(facts.inputs.single.name, 'count');
      expect(
        facts.inputs.single.constructorDefault,
        isA<UnsupportedWidgetConstructorDefault>(),
      );

      for (final target in const [
        WidgetVisitorTarget.rfw,
        WidgetVisitorTarget.a2ui,
      ]) {
        final result = await runWidgetVisitorOn(sources, target: target);
        expect(result.widgets.single.name, 'Probe', reason: target.name);
        final issue = result.issues.singleWhere(
          (candidate) =>
              candidate.location == '$sourcePath#Probe.count' &&
              candidate.code == IssueCode.invalidWidgetConstructorInput,
        );
        expect(issue.message, contains('${target.name} target'));
      }
    });

    test('ambiguous and transformed ordinary bindings fail on every target',
        () async {
      const sourcePath = 'lib/ordinary_bindings.dart';
      const sources = {
        sourcePath: '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Ordinary-binding rejection probe.
$_annotation
class Probe {
  Probe(String ambiguous, String transformed)
      : first = ambiguous,
        second = ambiguous,
        transformedValue = transformed.trim();

  /// First ambiguous destination.
  final String first;

  /// Second ambiguous destination.
  final String second;

  /// Transformed destination.
  final String transformedValue;
}
''',
      };
      final facts = await runWidgetConstructorFactsOn(sources);
      expect(
        facts.issues.map((issue) => issue.location),
        containsAll(<String>[
          '$sourcePath#Probe.ambiguous',
          '$sourcePath#Probe.transformed',
        ]),
        reason: 'both constructor parameters must survive into fact errors',
      );

      for (final target in WidgetVisitorTarget.values) {
        final result = await runWidgetVisitorOn(sources, target: target);
        expect(result.widgets.single.name, 'Probe', reason: target.name);
        final failures = result.issues.where(
          (issue) => issue.code == IssueCode.invalidWidgetConstructorInput,
        );
        expect(failures, hasLength(2), reason: target.name);
        expect(
          failures.map((issue) => issue.message),
          everyElement(contains('For the ${target.name} target')),
        );
      }
    });

    test('named-only and factory-only widgets fail on every target', () async {
      for (final fixture in <(String, String)>[
        (
          'NamedOnlyProbe',
          '''
class NamedOnlyProbe {
  const NamedOnlyProbe.named(this.label);
  final String label;
}
''',
        ),
        (
          'FactoryOnlyProbe',
          '''
abstract class FactoryOnlyProbe {
  const factory FactoryOnlyProbe(String label) = FactoryOnlyProbeImpl;
  String get label;
}
class FactoryOnlyProbeImpl implements FactoryOnlyProbe {
  const FactoryOnlyProbeImpl(this.label);
  @override
  final String label;
}
''',
        ),
      ]) {
        final sourcePath = 'lib/${fixture.$1}.dart';
        final sources = {
          sourcePath: '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: '${fixture.$1}',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.input,
  description: 'Constructor selection rejection probe.',
)
${fixture.$2}
''',
        };
        final facts = await runWidgetConstructorFactsOn(
          sources,
          className: fixture.$1,
        );
        expect(
          facts.issues,
          isNotEmpty,
          reason: '${fixture.$1} must reach constructor fact selection',
        );

        for (final target in WidgetVisitorTarget.values) {
          final result = await runWidgetVisitorOn(sources, target: target);
          expect(result.widgets, isEmpty, reason: target.name);
          final issue = result.issues.singleWhere(
            (candidate) =>
                candidate.location == '$sourcePath#${fixture.$1}' &&
                candidate.code == IssueCode.invalidWidgetConstructorInput,
          );
          expect(issue.message, contains('For the ${target.name} target'));
          expect(issue.message, contains('no unnamed generative constructor'));
        }
      }
    });

    test('RFW rejects callback arity, payload, and return at source paths',
        () async {
      const sourcePath = 'lib/rfw_callbacks.dart';
      const sources = {
        sourcePath: '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// RFW callback rejection probe.
$_annotation
class Probe {
  const Probe({
    required this.badArity,
    required this.badPayload,
    required this.badReturn,
  });

  /// Unsupported two-argument callback.
  final void Function(int, int) badArity;

  /// Unsupported non-scalar payload callback.
  final void Function(Object) badPayload;

  /// Unsupported non-void return callback.
  final int Function() badReturn;
}
''',
      };
      final facts = await runWidgetConstructorFactsOn(sources);
      expect(
        facts.inputs.map((input) => input.name),
        containsAll(<String>['badArity', 'badPayload', 'badReturn']),
      );
      final result = await runWidgetVisitorOn(sources);
      expect(
        result.widgets.single.properties.map((property) => property.name),
        containsAll(<String>['badArity', 'badPayload', 'badReturn']),
        reason: 'callbacks must remain in the intermediate RFW catalog',
      );
      final failures = result.issues.where(
        (issue) => issue.code == IssueCode.invalidEventConfiguration,
      );
      expect(failures, hasLength(3));
      expect(
        failures.map((issue) => issue.location),
        containsAll(<String>[
          '$sourcePath#Probe.badArity',
          '$sourcePath#Probe.badPayload',
          '$sourcePath#Probe.badReturn',
        ]),
      );
      expect(
        failures.map((issue) => issue.message),
        everyElement(contains('RFW customer events')),
      );
    });

    test('A2UI rejects dangling, duplicate, and conflicting pairings',
        () async {
      const sourcePath = 'lib/a2ui_pairings.dart';
      const sources = {
        sourcePath: '''
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;

@a2ui.Config.writeBackValues({
  'missingCallback': 'missingValue',
  'onChanged': 'value',
  'onCountChanged': 'count',
})
class Probe {
  const Probe({
    required this.value,
    required this.count,
    required this.onChanged,
    required this.onCountChanged,
  });

  final String value;
  final int count;

  @a2ui.Config.writeBackValue('value')
  final void Function(String) onChanged;

  @a2ui.Config.writeBackValue('value')
  final void Function(int) onCountChanged;
}
''',
      };
      final facts = await runWidgetConstructorFactsOn(sources);
      expect(
        facts.inputs.map((input) => input.name),
        containsAll(<String>['value', 'count', 'onChanged', 'onCountChanged']),
        reason: 'all pairing endpoints must exist before A2UI validation',
      );
      final config = await runTargetConfigReadersOn(sources);
      expect(
        config.issues.map((issue) => issue.code),
        containsAll(<IssueCode>[
          IssueCode.invalidTargetConfigReference,
          IssueCode.duplicateTargetConfig,
          IssueCode.conflictingTargetConfig,
        ]),
      );
      expect(
        config.issues.map((issue) => issue.location),
        everyElement(startsWith('$sourcePath#Probe')),
      );
      expect(
        config.issues.map((issue) => issue.message).join('\n'),
        contains('A2UI'),
      );
    });

    test('a genuine unresolved A2UI annotation fails at its source path',
        () async {
      const sourcePath = 'lib/unresolved_a2ui_annotation.dart';
      const sources = {
        sourcePath: '''
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;

String runtimeUsage() => 'runtime';

@a2ui.Config(usage: runtimeUsage())
class Probe {}
''',
      };
      final config = await runTargetConfigReadersOn(sources);
      final issue = config.issues.singleWhere(
        (candidate) => candidate.code == IssueCode.missingAnnotationField,
      );
      expect(issue.location, startsWith('$sourcePath#Probe@a2ui.Config'));
      expect(issue.message, contains('a2ui.Config'));
      expect(config.writeBackValues, isEmpty);
    });

    test('target capability walls retain the widget before rejection',
        () async {
      const sourcePath = 'lib/capability_walls.dart';
      const sources = {
        sourcePath: '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Capability-wall rejection probe.
$_annotation
class Probe {
  const Probe({required this.items, required this.timestamp});

  /// A direct scalar list admitted only by A2UI.
  final List<int> items;

  /// A host type admitted by no generated target.
  final DateTime timestamp;
}
''',
      };
      final facts = await runWidgetConstructorFactsOn(sources);
      expect(
        facts.inputs.map((input) => input.name),
        containsAll(<String>['items', 'timestamp']),
      );

      for (final target in WidgetVisitorTarget.values) {
        final result = await runWidgetVisitorOn(sources, target: target);
        expect(result.widgets.single.name, 'Probe', reason: target.name);
        final failures = result.issues.where(
          (issue) => issue.code == IssueCode.unsupportedPropertyType,
        );
        expect(
          failures.map((issue) => issue.location),
          contains('$sourcePath#Probe.timestamp'),
          reason: target.name,
        );
        expect(
          failures.map((issue) => issue.message),
          everyElement(contains('Target: ${target.name}')),
          reason: target.name,
        );
        if (target == WidgetVisitorTarget.a2ui) {
          expect(
            result.widgets.single.properties.map((property) => property.name),
            contains('items'),
          );
        } else {
          expect(
            failures.map((issue) => issue.location),
            contains('$sourcePath#Probe.items'),
            reason: target.name,
          );
        }
      }
    });

    test('Widgetbook import collisions name both target and source path', () {
      const sourcePath = 'lib/collision.dart#CollisionProbe.data';
      const customerLibrary = 'package:fixture/models.dart';
      expect(
        () => DartImportPlanner(
          libraryUris: const {customerLibrary},
          bareSymbolImports: const [
            DartBareSymbolImport(
              libraryUri: customerLibrary,
              symbol: 'Meta',
              sourcePath: sourcePath,
            ),
          ],
          bareSymbolReservations: const [
            DartBareSymbolReservation(
              libraryUri: 'package:widgetbook/src/core/framework/meta.dart',
              symbol: 'Meta',
              source: 'package:widgetbook/widgetbook.dart export',
            ),
          ],
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains(sourcePath),
              contains(customerLibrary),
              contains('package:widgetbook/widgetbook.dart'),
            ),
          ),
        ),
      );
    });
  });
}
