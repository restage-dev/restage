import 'package:restage_codegen/src/issue.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('widget target routing reader', () {
    test('aggregate and named enabled forms coalesce by resolved target',
        () async {
      const sources = {
        'lib/probe.dart': '''
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw.dart' as rfw;
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

@rfw.Config(enabled: true)
@rfw.Config.enabled(true)
@a2ui.Config(enabled: false, usage: 'Not emitted to A2UI.')
@a2ui.Config.enabled(false)
@wb.Config(enabled: true, maxStories: 4)
@wb.Config.enabled(true)
class Probe {}
''',
      };

      final rfw = await runWidgetTargetRoutingReaderOn(
        sources,
        target: EmitTarget.rfw,
      );
      final a2ui = await runWidgetTargetRoutingReaderOn(
        sources,
        target: EmitTarget.a2ui,
      );
      final widgetbook = await runWidgetTargetRoutingReaderOn(
        sources,
        target: EmitTarget.widgetbook,
      );

      expect(rfw.enabled, isTrue);
      expect(rfw.issues, isEmpty);
      expect(a2ui.enabled, isFalse);
      expect(a2ui.issues, isEmpty);
      expect(widgetbook.enabled, isTrue);
      expect(widgetbook.issues, isEmpty);
    });

    test('conflicting enabled values fail at both source locations', () async {
      final result = await runWidgetTargetRoutingReaderOn(
        {
          'lib/probe.dart': '''
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;

@a2ui.Config.enabled(true)
@a2ui.Config(enabled: false)
class Probe {}
''',
        },
        target: EmitTarget.a2ui,
      );

      expect(result.valid, isFalse);
      final conflicts = result.issues
          .where((issue) => issue.code == IssueCode.conflictingTargetConfig)
          .toList();
      expect(conflicts, hasLength(2));
      expect(conflicts.map((issue) => issue.location).toSet(), hasLength(2));
      expect(
        conflicts.map((issue) => issue.message),
        everyElement(allOf(contains('true'), contains('false'))),
      );
    });

    test('foreign and unresolved Config spellings never change routing',
        () async {
      final foreign = await runWidgetTargetRoutingReaderOn(
        {
          'lib/probe.dart': '''
class Config {
  const Config({this.enabled});
  final bool? enabled;
}

@Config(enabled: false)
class Probe {}
''',
        },
        target: EmitTarget.a2ui,
      );
      final unresolved = await runWidgetTargetRoutingReaderOn(
        {
          'lib/probe.dart': '''
@Config(enabled: false)
class Probe {}
''',
        },
        target: EmitTarget.a2ui,
      );

      expect(foreign.enabled, isTrue);
      expect(foreign.issues, isEmpty);
      expect(unresolved.enabled, isTrue);
      expect(unresolved.issues, isEmpty);
    });

    test('enabled on a field or constructor formal fails placement', () async {
      final result = await runWidgetTargetRoutingReaderOn(
        {
          'lib/probe.dart': '''
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

class Probe {
  const Probe({
    @wb.Config.enabled(false) this.formalValue = '',
  });

  @wb.Config(enabled: false)
  final String fieldValue = '';

  @wb.Config(enabled: null)
  final String explicitNullValue = '';

  final String formalValue;
}
''',
        },
        target: EmitTarget.widgetbook,
      );

      expect(result.valid, isFalse);
      final placements = result.issues
          .where(
            (issue) => issue.code == IssueCode.invalidTargetConfigPlacement,
          )
          .toList();
      expect(placements, hasLength(3));
      expect(
        placements.map((issue) => issue.location),
        containsAll([
          contains('fieldValue'),
          contains('explicitNullValue'),
          contains('formalValue'),
        ]),
      );
    });

    test('a malformed genuine enabled annotation fails loudly', () async {
      final result = await runWidgetTargetRoutingReaderOn(
        {
          'lib/probe.dart': '''
import 'package:rfw_catalog_schema/rfw.dart' as rfw;

final runtimeEnabled = false;

@rfw.Config.enabled(runtimeEnabled)
class Probe {}
''',
        },
        target: EmitTarget.rfw,
      );

      expect(result.valid, isFalse);
      expect(result.issues, hasLength(1));
      expect(result.issues.single.code, IssueCode.missingAnnotationField);
      expect(result.issues.single.message, contains('const-evaluated'));
    });
  });
}
