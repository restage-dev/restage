// packages/rfw_catalog_compiler/test/policy/default_content_test.dart
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_compiler/src/policy/default_content/default_structured_walk.dart';
import 'package:test/test.dart';

import 'fakes/fake_dart_types.dart' as fakes;

void main() {
  group('default policy content', () {
    const ledger = PolicyLedger.builtIn();

    test(
        'type denylist includes the canonical controller/node/key '
        'cases', () {
      expect(
        ledger.denylist.types,
        containsAll(<String>{
          'BuildContext',
          'Element',
          'RenderObject',
          'State',
          'Key',
          'GlobalKey',
          'TextEditingController',
          'ScrollController',
          'FocusNode',
          'CustomPainter',
          'CustomClipper',
          'PreferredSizeWidget',
          'Shader',
          'ImageProvider',
          'AssetBundle',
          'Listenable',
          'ValueListenable',
          'ChangeNotifier',
          'Future',
          'Stream',
          'Animation',
          'TickerProvider',
          'Locale',
          'Matrix4',
          'RouteSettings',
          'Route',
          'PageRoute',
          'MouseCursor',
          'HitTestBehavior',
          'DragStartBehavior',
          'TextBaseline',
          'ScrollPhysics',
        }),
      );
      expect(ledger.denylist.types, isNot(contains('Curve')));
    });

    test(
        'type-suffix denylist covers Controller / Node / Builder / '
        'Configuration', () {
      expect(
        ledger.denylist.typeSuffixes,
        containsAll(<String>{
          'Controller',
          'Node',
          'Builder',
          'Configuration',
        }),
      );
      expect(ledger.denylist.typeSuffixes, isNot(contains('Behavior')));
    });

    test('valid Behavior enums are not suffix-denylisted', () {
      expect(
        DenylistFilter.match(
          fakes.fakeInterfaceType('ChangeReportingBehavior'),
          ledger,
        ),
        isNull,
      );
      expect(
        DenylistFilter.match(fakes.fakeInterfaceType('ClipBehavior'), ledger),
        isNull,
      );
    });

    test('exact-denylisted Behavior types still match', () {
      for (final typeName in <String>[
        'HitTestBehavior',
        'DragStartBehavior',
      ]) {
        final match = DenylistFilter.match(
          fakes.fakeInterfaceType(typeName),
          ledger,
        );
        expect(match, isNotNull, reason: typeName);
        expect(match!.policy, equals('denylist.types'), reason: typeName);
      }
    });

    test(
        'ScrollViewKeyboardDismissBehavior is a surfaceable enum, not '
        'denylisted', () {
      // A clean 2-member enum (manual / onDrag) — it round-trips through
      // the catalog wire format as any enum does, unlike the genuinely
      // unmappable scroll/text types it was historically grouped with.
      expect(
        ledger.denylist.types,
        isNot(contains('ScrollViewKeyboardDismissBehavior')),
      );
      expect(
        DenylistFilter.match(
          fakes.fakeInterfaceType('ScrollViewKeyboardDismissBehavior'),
          ledger,
        ),
        isNull,
      );
    });

    test(
        'widget denylist excludes Navigator, Hero, Drawer, dialogs, '
        'drag targets, layout builders, etc.', () {
      expect(
        ledger.denylist.widgets,
        containsAll(<String>{
          'package:flutter/src/widgets/navigator.dart#Navigator',
          'package:flutter/src/widgets/heroes.dart#Hero',
          'package:flutter/src/material/drawer.dart#Drawer',
          'package:flutter/src/material/dialog.dart#AlertDialog',
          'package:flutter/src/widgets/form.dart#Form',
          'package:flutter/src/widgets/layout_builder.dart#LayoutBuilder',
          'package:flutter/src/widgets/drag_target.dart#DragTarget',
          'package:flutter/src/widgets/basic.dart#CustomPaint',
        }),
      );
    });

    test('widget denylist explicitly allows intrinsic layout wrappers', () {
      expect(
        ledger.denylist.widgets,
        isNot(
          contains('package:flutter/src/widgets/basic.dart#IntrinsicHeight'),
        ),
      );
      expect(
        ledger.denylist.widgets,
        isNot(
          contains('package:flutter/src/widgets/basic.dart#IntrinsicWidth'),
        ),
      );
      expect(
        ledger.denylist.widgets,
        containsAll(<String>{
          'package:flutter/src/widgets/basic.dart#CustomPaint',
          'package:flutter/src/widgets/basic.dart#RepaintBoundary',
        }),
      );
    });

    test('mutex rules include Container.color ↔ Container.decoration', () {
      final containerRules = ledger.mutexRules
          .rules['package:flutter/src/widgets/container.dart#Container'];
      expect(containerRules, isNotNull);
      final rules = containerRules ?? [];
      expect(
        rules,
        contains(equals(<String>['color', 'decoration'])),
      );
    });

    test(
        'union registry seeds Gradient → [LinearGradient, '
        'RadialGradient, SweepGradient] as FQNs', () {
      final gradient = ledger.unionRegistry
          .entries['package:flutter/src/painting/gradient.dart#Gradient'];
      expect(gradient, isNotNull);
      expect(
        gradient!.members,
        containsAll(<String>{
          'package:flutter/src/painting/gradient.dart#LinearGradient',
          'package:flutter/src/painting/gradient.dart#RadialGradient',
          'package:flutter/src/painting/gradient.dart#SweepGradient',
        }),
      );
      expect(gradient.discriminatorField, equals('_s'));
    });

    test('union registry seeds ShapeBorder and OutlinedBorder variants', () {
      const expected = <String>{
        'package:flutter/src/painting/rounded_rectangle_border.dart#RoundedRectangleBorder',
        'package:flutter/src/painting/rounded_rectangle_border.dart#RoundedSuperellipseBorder',
        'package:flutter/src/painting/circle_border.dart#CircleBorder',
        'package:flutter/src/painting/stadium_border.dart#StadiumBorder',
        'package:flutter/src/painting/continuous_rectangle_border.dart#ContinuousRectangleBorder',
        'package:flutter/src/painting/beveled_rectangle_border.dart#BeveledRectangleBorder',
        'package:flutter/src/painting/linear_border.dart#LinearBorder',
        'package:flutter/src/painting/star_border.dart#StarBorder',
      };

      final shapeBorder = ledger.unionRegistry
          .entries['package:flutter/src/painting/borders.dart#ShapeBorder'];
      final outlinedBorder = ledger.unionRegistry
          .entries['package:flutter/src/painting/borders.dart#OutlinedBorder'];

      expect(shapeBorder, isNotNull);
      expect(shapeBorder!.members, containsAll(expected));
      expect(outlinedBorder, isNotNull);
      expect(outlinedBorder!.members, containsAll(expected));
    });

    test(
        'priority heuristics default to required-as-primary + first-4 '
        'common', () {
      expect(ledger.priorityHeuristics.requiredAsPrimary, isTrue);
      expect(ledger.priorityHeuristics.firstNCommon, equals(4));
    });
  });

  group('default_structured_walk', () {
    test('concrete whitelist has 24 entries', () {
      expect(kBuiltInStructuredConcrete, hasLength(24));
    });

    test('abstract list has 6 entries', () {
      expect(kBuiltInStructuredAbstract, hasLength(6));
    });

    test('max depth is 8', () {
      expect(kBuiltInStructuredMaxDepth, equals(8));
    });

    test('concrete whitelist includes BoxDecoration canonical FQN', () {
      expect(
        kBuiltInStructuredConcrete,
        contains(
          'package:flutter/src/painting/box_decoration.dart#BoxDecoration',
        ),
      );
    });

    test('concrete whitelist includes BoxConstraints canonical FQN', () {
      expect(
        kBuiltInStructuredConcrete,
        contains('package:flutter/src/rendering/box.dart#BoxConstraints'),
      );
    });

    test('abstract list includes Gradient canonical FQN', () {
      expect(
        kBuiltInStructuredAbstract,
        contains('package:flutter/src/painting/gradient.dart#Gradient'),
      );
    });

    test('Border FQN points to box_border.dart (not border.dart)', () {
      expect(
        kBuiltInStructuredConcrete,
        contains('package:flutter/src/painting/box_border.dart#Border'),
      );
    });

    test('Radius FQN points to dart:ui (not border_radius.dart)', () {
      expect(kBuiltInStructuredConcrete, contains('dart:ui#Radius'));
    });

    test('shape concrete whitelist includes current OutlinedBorder variants',
        () {
      expect(
        kBuiltInStructuredConcrete,
        containsAll(<String>{
          'package:flutter/src/painting/rounded_rectangle_border.dart#RoundedRectangleBorder',
          'package:flutter/src/painting/rounded_rectangle_border.dart#RoundedSuperellipseBorder',
          'package:flutter/src/painting/circle_border.dart#CircleBorder',
          'package:flutter/src/painting/stadium_border.dart#StadiumBorder',
          'package:flutter/src/painting/continuous_rectangle_border.dart#ContinuousRectangleBorder',
          'package:flutter/src/painting/beveled_rectangle_border.dart#BeveledRectangleBorder',
          'package:flutter/src/painting/linear_border.dart#LinearBorder',
          'package:flutter/src/painting/linear_border.dart#LinearBorderEdge',
          'package:flutter/src/painting/star_border.dart#StarBorder',
        }),
      );
      expect(
        kBuiltInStructuredAbstract,
        contains('package:flutter/src/painting/borders.dart#OutlinedBorder'),
      );
    });

    test('concrete and abstract sets are disjoint', () {
      final overlap =
          kBuiltInStructuredConcrete.intersection(kBuiltInStructuredAbstract);
      expect(overlap, isEmpty);
    });
  });
}
