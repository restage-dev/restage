import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/source_state.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('extractSourceBuildBlueprint', () {
    test('captures supported StatefulWidget root state', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class GestureDetector extends Widget {
          const GestureDetector({this.onTap, this.child});
          final void Function()? onTap;
          final Widget? child;
        }

        class ProPaywall extends StatefulWidget {
          const ProPaywall();
          _ProPaywallState createState() => _ProPaywallState();
        }

        class _ProPaywallState extends State<ProPaywall> {
          bool annual = false;
          void toggle() => setState(() => annual = !annual);
          Widget build(BuildContext context) => GestureDetector(onTap: toggle);
        }
      ''');

      expect(result.issues, isEmpty);
      final blueprint = result.blueprint;
      expect(blueprint, isNotNull);
      expect(blueprint!.state!.map((field) => field.name), ['annual']);
      expect(blueprint.state!.single.initialValue, false);
      expect(blueprint.eventHandlers.keys, contains('toggle'));
      expect(blueprint.rootExpression, isNotNull);
    });

    test('derives stateless root host data params in declaration order',
        () async {
      final result = await _extractBlueprint(
        '''
        import 'package:flutter/widgets.dart';

        class Foo extends StatelessWidget {
          const Foo({
            super.key,
            required this.title,
            this.count,
            this.nickname = null,
            this.heading = 'Welcome',
          });
          final String title;
          final int? count;
          final String? nickname;
          final String heading;
          Widget build(BuildContext context) => const SizedBox.shrink();
        }
      ''',
        className: 'Foo',
      );

      expect(result.issues, isEmpty);
      final params = result.blueprint!.rootParams;
      expect(
        params.map((param) => param.name),
        ['title', 'count', 'nickname', 'heading'],
      );
      expect(params[0].isNullable, isFalse);
      expect(params[1].isNullable, isTrue);
      expect(params.map((param) => param.field), everyElement(isNotNull));
      expect(
        params.map((param) => param.isRequired),
        [true, false, false, false],
      );
      expect(
        params.map((param) => param.kind),
        everyElement(RootContextParamKind.named),
      );
      expect(
        params.map((param) => param.typeCode),
        ['String', 'int?', 'String?', 'String'],
      );
      expect(params[0].defaultValueCode, isNull);
      expect(params[1].defaultValueCode, isNull);
      expect(params[2].defaultValueCode, 'null');
      expect(params[2].hasNullDefault, isTrue);
      expect(params[3].defaultValueCode, "'Welcome'");
      expect(params[3].hasNonNullDefault, isTrue);
    });

    test('retains positional constructor forms and field type spelling',
        () async {
      final result = await _extractBlueprint(
        '''
        $kSourceStateStubs

        class Foo extends StatelessWidget {
          const Foo(this.title, [this.count = 2]);
          final String title;
          final int count;
          Widget build(BuildContext context) => const Widget();
        }
      ''',
        className: 'Foo',
      );

      expect(result.issues, isEmpty);
      final params = result.blueprint!.rootParams;
      expect(params.map((param) => param.name), ['title', 'count']);
      expect(
        params.map((param) => param.kind),
        [
          RootContextParamKind.requiredPositional,
          RootContextParamKind.optionalPositional,
        ],
      );
      expect(params.map((param) => param.typeCode), ['String', 'int']);
      expect(params[1].defaultValueCode, '2');
    });

    test('refuses Object list elements with one remedy', () async {
      for (final element in ['Object?', 'Object']) {
        final result = await _extractBlueprint(
          '''
            $kSourceStateStubs
            class Foo extends StatelessWidget {
              const Foo({required this.value});
              final List<$element> value;
              Widget build(BuildContext context) => const Widget();
            }
          ''',
          className: 'Foo',
        );
        final refused = result.blueprint!.rootParams.single;
        expect(refused.hostDataProblem?.path, 'value[]', reason: element);
        expect(
          refused.hostDataProblem?.detail,
          contains('cannot be Object'),
          reason: element,
        );
      }
    });

    test('admits List and Map root host data params', () async {
      final result = await _extractBlueprint(
        '''
        $kSourceStateStubs

        class Foo extends StatelessWidget {
          const Foo({required this.tags, required this.counts});
          final List<String> tags;
          final Map<String, int> counts;
          Widget build(BuildContext context) => const Widget();
        }
      ''',
        className: 'Foo',
      );

      expect(result.issues, isEmpty);
      expect(
        result.blueprint!.rootParams.map((param) => param.name),
        ['tags', 'counts'],
      );
      expect(
        result.blueprint!.rootParams.map((param) => param.isHostData),
        everyElement(isTrue),
      );
    });

    test('derives the closed recursive host-data shape', () async {
      const acceptedSource = '''
        $kSourceStateStubs

        final class Habit {
          const Habit({required this.id, required this.name});
          final String id;
          final String name;
        }

        typedef HabitAlias = Habit;

        final class Group {
          const Group(this.label, this.habits, this.selected);
          final String label;
          final List<HabitAlias> habits;
          final Map<String, Habit?> selected;
        }

        class Foo extends StatelessWidget {
          const Foo({required this.group});
          final Group? group;
          Widget build(BuildContext context) => const Widget();
        }
      ''';
      final accepted = await _extractBlueprint(
        acceptedSource,
        className: 'Foo',
      );

      expect(accepted.issues, isEmpty);
      final param = accepted.blueprint!.rootParams.single;
      expect(param.isHostData, isTrue);
      expect(param.typeCode, 'Group?');
      final group = param.hostDataShape;
      if (group is! HostDataObjectShape) {
        fail('expected a plain object shape, got $group');
      }
      expect(group.fields.map((field) => field.wireKey), [
        'label',
        'habits',
        'selected',
      ]);
      final habits = group.fields[1].shape as HostDataListShape;
      final habit = habits.elementShape as HostDataObjectShape;
      expect(habit.element.name, 'Habit');
      expect(habit.fields.map((field) => field.wireKey), ['id', 'name']);
      expect(
        habit.fields.map((field) => field.element.name),
        ['id', 'name'],
      );
      expect(
        (group.fields[2].shape as HostDataMapShape).valueShape,
        isA<HostDataObjectShape>(),
      );

      final cases =
          <({String name, String declarations, String type, String path})>[
        (
          name: 'dynamic',
          declarations: '',
          type: 'dynamic',
          path: 'value',
        ),
        (
          name: 'object',
          declarations: '',
          type: 'Object',
          path: 'value',
        ),
        (
          name: 'enum',
          declarations: 'enum Choice { one }',
          type: 'Choice',
          path: 'value',
        ),
        (
          name: 'record',
          declarations: '',
          type: '(String, int)',
          path: 'value',
        ),
        (
          name: 'function',
          declarations: '',
          type: 'String Function()',
          path: 'value',
        ),
        (
          name: 'set',
          declarations: '',
          type: 'Set<String>',
          path: 'value',
        ),
        (
          name: 'iterable',
          declarations: '',
          type: 'Iterable<String>',
          path: 'value',
        ),
        (
          name: 'map key',
          declarations: '',
          type: 'Map<int, String>',
          path: 'value{key}',
        ),
        (
          name: 'mutable field',
          declarations: 'class Value { Value(this.name); String name; }',
          type: 'Value',
          path: 'value',
        ),
        (
          name: 'private field',
          declarations: '''
            class Value { const Value(this._name); final String _name; }
          ''',
          type: 'Value',
          path: 'value._name',
        ),
        (
          name: 'computed field',
          declarations: '''
            class Value {
              const Value(this.name);
              final String name;
              String get label => name;
            }
          ''',
          type: 'Value',
          path: 'value.label',
        ),
        (
          name: 'non-const construction',
          declarations: 'class Value { Value(); }',
          type: 'Value',
          path: 'value',
        ),
        (
          name: 'missing unnamed construction',
          declarations: 'class Value { const Value.named(); }',
          type: 'Value',
          path: 'value',
        ),
        (
          name: 'empty object',
          declarations: 'final class Value { const Value(); }',
          type: 'Value',
          path: 'value',
        ),
        (
          name: 'method',
          declarations: '''
            class Value { const Value(); String read() => 'value'; }
          ''',
          type: 'Value',
          path: 'value',
        ),
        (
          name: 'generic',
          declarations: '''
            class Value<T> { const Value(this.value); final T value; }
          ''',
          type: 'Value<String>',
          path: 'value',
        ),
        (
          name: 'inherited',
          declarations: '''
            class Base { const Base(this.id); final String id; }
            class Value extends Base { const Value(super.id); }
          ''',
          type: 'Value',
          path: 'value',
        ),
        (
          name: 'mixed in',
          declarations: '''
            mixin Extra { final String extra = ''; }
            class Value with Extra { const Value(); }
          ''',
          type: 'Value',
          path: 'value',
        ),
        (
          name: 'nested bad field',
          declarations: '''
            class Value { const Value(this.child); final Child child; }
            class Child { const Child(this.names); final Set<String> names; }
          ''',
          type: 'Value',
          path: 'value.child.names',
        ),
        (
          name: 'cycle',
          declarations: '''
            class Value { const Value(this.child); final Child child; }
            class Child { const Child(this.value); final Value value; }
          ''',
          type: 'Value',
          path: 'value.child.value',
        ),
      ];

      for (final entry in cases) {
        final result = await _extractBlueprint(
          '''
            $kSourceStateStubs
            ${entry.declarations}
            class Foo extends StatelessWidget {
              const Foo({required this.value});
              final ${entry.type} value;
              Widget build(BuildContext context) => const Widget();
            }
          ''',
          className: 'Foo',
        );
        expect(result.issues, isEmpty, reason: entry.name);
        final refused = result.blueprint!.rootParams.single;
        expect(refused.isHostData, isFalse, reason: entry.name);
        expect(refused.hostDataShape, isNull, reason: entry.name);
        expect(refused.hostDataProblem?.path, entry.path, reason: entry.name);
      }

      final implementsGetter = await _extractBlueprint(
        '''
          $kSourceStateStubs
          abstract interface class NamedValue {
            String get name;
          }
          final class Value implements NamedValue {
            const Value(this.name);
            @override
            final String name;
          }
          class Foo extends StatelessWidget {
            const Foo({required this.value});
            final Value value;
            Widget build(BuildContext context) => const Widget();
          }
        ''',
        className: 'Foo',
      );
      expect(implementsGetter.issues, isEmpty);
      final interfaceParam = implementsGetter.blueprint!.rootParams.single;
      expect(interfaceParam.isHostData, isTrue);
      final interfaceShape = interfaceParam.hostDataShape;
      if (interfaceShape is! HostDataObjectShape) {
        fail('expected a plain object shape, got $interfaceShape');
      }
      expect(interfaceShape.fields.map((field) => field.wireKey), ['name']);

      final framework = await _extractBlueprint(
        '''
          import 'package:flutter/widgets.dart';
          class Foo extends StatelessWidget {
            const Foo({required this.value, super.key});
            final EdgeInsets value;
            Widget build(BuildContext context) => const SizedBox.shrink();
          }
        ''',
        className: 'Foo',
      );
      expect(framework.issues, isEmpty);
      expect(framework.blueprint!.rootParams.single.isHostData, isFalse);
      expect(
        framework.blueprint!.rootParams.single.hostDataProblem?.path,
        'value',
      );
    });

    test('keeps non-field formals without assigning a readable field',
        () async {
      final result = await _extractBlueprint(
        '''
        $kSourceStateStubs

        class Foo extends StatelessWidget {
          factory Foo({String? label}) => const Foo._();
          const Foo._();
          static String get label => 'fixed';
          Widget build(BuildContext context) => const Widget();
        }
      ''',
        className: 'Foo',
      );

      expect(result.issues, isEmpty);
      final param = result.blueprint!.rootParams.single;
      expect(param.name, 'label');
      expect(param.field, isNull);
      expect(param.isRequired, isFalse);
    });

    test(
        'records application-defined types in root host data params for '
        'read refusal', () async {
      final result = await _extractBlueprint(
        '''
        $kSourceStateStubs

        class Habit {
          const Habit();
          String label() => 'habit';
        }

        class Foo extends StatelessWidget {
          const Foo({required this.title, required this.habits});
          final String title;
          final List<Habit> habits;
          Widget build(BuildContext context) => const Widget();
        }
      ''',
        className: 'Foo',
      );

      expect(result.issues, isEmpty);
      final params = result.blueprint!.rootParams;
      expect(params.map((param) => param.name), ['title', 'habits']);
      expect(params[0].isHostData, isTrue);
      expect(params[1].isHostData, isFalse);
    });

    test('derives StatefulWidget root host data from the widget class',
        () async {
      final result = await _extractBlueprint(
        '''
        $kSourceStateStubs

        class Foo extends StatefulWidget {
          const Foo({required this.title, this.count});
          final String title;
          final int? count;
          _FooState createState() => _FooState();
        }

        class _FooState extends State<Foo> {
          Widget build(BuildContext context) => const Widget();
        }
      ''',
        className: 'Foo',
      );

      expect(result.issues, isEmpty);
      expect(
        result.blueprint!.rootParams.map((param) => param.name),
        ['title', 'count'],
      );
    });

    test('rejects lifecycle methods on the State class', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class ProPaywall extends StatefulWidget {
          const ProPaywall();
          _ProPaywallState createState() => _ProPaywallState();
        }

        class _ProPaywallState extends State<ProPaywall> {
          bool annual = false;
          void initState() {}
          Widget build(BuildContext context) => const Widget();
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.stateShapeUnsupported,
      ]);
      expect(
        result.issues.single.message,
        allOf(
          contains('State lifecycle method initState()'),
          contains('declarative root source state'),
        ),
      );
    });

    test('rejects StatefulWidget roots with unresolvable State class',
        () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class ProPaywall extends StatefulWidget {
          const ProPaywall();
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.stateShapeUnsupported,
      ]);
      expect(
        result.issues.single.message,
        allOf(
          contains('StatefulWidget root ProPaywall'),
          contains('createState()'),
          contains('concrete State class'),
        ),
      );
    });

    test('rejects non-primitive State fields', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class AnimationController {
          const AnimationController();
        }

        class ProPaywall extends StatefulWidget {
          const ProPaywall();
          _ProPaywallState createState() => _ProPaywallState();
        }

        class _ProPaywallState extends State<ProPaywall> {
          AnimationController controller = const AnimationController();
          Widget build(BuildContext context) => const Widget();
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.stateShapeUnsupported,
      ]);
      expect(
        result.issues.single.message,
        allOf(
          contains("State field 'controller' has unsupported type"),
          contains('supports only bool, int, double, num, String, and enum'),
        ),
      );
    });

    test('rejects missing primitive State field initializers', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class ProPaywall extends StatefulWidget {
          const ProPaywall();
          _ProPaywallState createState() => _ProPaywallState();
        }

        class _ProPaywallState extends State<ProPaywall> {
          late bool annual;
          Widget build(BuildContext context) => const Widget();
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.stateShapeUnsupported,
      ]);
    });

    test('rejects non-foldable primitive State field initializers', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        int nonConst() => 1;

        class ProPaywall extends StatefulWidget {
          const ProPaywall();
          _ProPaywallState createState() => _ProPaywallState();
        }

        class _ProPaywallState extends State<ProPaywall> {
          int count = nonConst();
          Widget build(BuildContext context) => const Widget();
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.stateShapeUnsupported,
      ]);
    });

    test('rejects referenced handlers with unrecognised setState bodies',
        () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class GestureDetector extends Widget {
          const GestureDetector({this.onTap, this.child});
          final void Function()? onTap;
          final Widget? child;
        }

        class ProPaywall extends StatefulWidget {
          const ProPaywall();
          _ProPaywallState createState() => _ProPaywallState();
        }

        class _ProPaywallState extends State<ProPaywall> {
          bool annual = false;
          int count = 0;
          void toggle() => setState(() {
                annual = !annual;
                count = 1;
              });
          Widget build(BuildContext context) => GestureDetector(onTap: toggle);
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.stateShapeUnsupported,
      ]);
      expect(
        result.issues.single.message,
        allOf(
          contains("State handler 'toggle' cannot be lowered"),
          contains('single assignment expression'),
        ),
      );
    });

    test('accepts unused ordinary helper methods', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class Text extends Widget {
          const Text(this.text);
          final String text;
        }

        class ProPaywall extends StatefulWidget {
          const ProPaywall();
          _ProPaywallState createState() => _ProPaywallState();
        }

        class _ProPaywallState extends State<ProPaywall> {
          bool annual = false;
          void helper() {
            annual = !annual;
          }
          Widget build(BuildContext context) =>
              Text(annual ? 'Annual' : 'Monthly');
        }
      ''');

      expect(result.issues, isEmpty);
      expect(result.blueprint, isNotNull);
      expect(result.blueprint!.eventHandlers, isEmpty);
    });

    test('accepts State.build() with leading const locals', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class Text extends Widget {
          const Text(this.text);
          final String text;
        }

        class ProPaywall extends StatefulWidget {
          const ProPaywall();
          _ProPaywallState createState() => _ProPaywallState();
        }

        class _ProPaywallState extends State<ProPaywall> {
          bool annual = false;
          Widget build(BuildContext context) {
            const label = 'Ready';
            return Text(label);
          }
        }
      ''');

      expect(result.issues, isEmpty);
      expect(result.blueprint, isNotNull);
    });

    test('captures a final prelude as element-keyed local bindings', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class Text extends Widget {
          const Text(this.text);
          final String text;
        }

        class ProPaywall extends StatefulWidget {
          const ProPaywall();
          _ProPaywallState createState() => _ProPaywallState();
        }

        class _ProPaywallState extends State<ProPaywall> {
          bool annual = false;
          Widget build(BuildContext context) {
            final label = 'Ready';
            return Text(label);
          }
        }
      ''');

      expect(result.issues, isEmpty);
      final blueprint = result.blueprint;
      expect(blueprint, isNotNull);
      expect(blueprint!.localBindings, hasLength(1));
      final binding = blueprint.localBindings.entries.single;
      expect(binding.key.name, 'label');
      expect(binding.value.toSource(), "'Ready'");
    });

    test('leaves localBindings empty for a const-only prelude', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class Text extends Widget {
          const Text(this.text);
          final String text;
        }

        class ProPaywall extends StatefulWidget {
          const ProPaywall();
          _ProPaywallState createState() => _ProPaywallState();
        }

        class _ProPaywallState extends State<ProPaywall> {
          bool annual = false;
          Widget build(BuildContext context) {
            const label = 'Ready';
            return Text(label);
          }
        }
      ''');

      expect(result.issues, isEmpty);
      expect(result.blueprint, isNotNull);
      expect(result.blueprint!.localBindings, isEmpty);
    });

    test('collects a State handler referenced only through a prelude local',
        () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class GestureDetector extends Widget {
          const GestureDetector({this.onTap});
          final void Function()? onTap;
        }

        class ProPaywall extends StatefulWidget {
          const ProPaywall();
          _ProPaywallState createState() => _ProPaywallState();
        }

        class _ProPaywallState extends State<ProPaywall> {
          bool annual = false;
          void toggle() => setState(() => annual = !annual);
          Widget build(BuildContext context) {
            final onTap = toggle;
            return GestureDetector(onTap: onTap);
          }
        }
      ''');

      expect(result.issues, isEmpty);
      expect(result.blueprint, isNotNull);
      expect(result.blueprint!.eventHandlers.keys, contains('toggle'));
    });

    test('rejects a prelude local that is never read', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class Text extends Widget {
          const Text(this.text);
          final String text;
        }

        class ProPaywall extends StatefulWidget {
          const ProPaywall();
          _ProPaywallState createState() => _ProPaywallState();
        }

        class _ProPaywallState extends State<ProPaywall> {
          bool annual = false;
          Widget build(BuildContext context) {
            final unread = 'Ready';
            return Text('Go');
          }
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.buildMethodTooComplex,
      ]);
      expect(result.issues.single.message, contains("'unread'"));
      expect(result.issues.single.message, contains('never read'));
    });

    test('rejects a grouped prelude declaration by name', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class Text extends Widget {
          const Text(this.text);
          final String text;
        }

        class ProPaywall extends StatefulWidget {
          const ProPaywall();
          _ProPaywallState createState() => _ProPaywallState();
        }

        class _ProPaywallState extends State<ProPaywall> {
          bool annual = false;
          Widget build(BuildContext context) {
            const gap = 'a', radius = 'b';
            return Text(gap);
          }
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.buildMethodTooComplex,
      ]);
      expect(result.issues.single.message, contains("'gap, radius'"));
      expect(result.issues.single.message, contains('split'));
    });

    test('rejects an unread local holding a call with an effect', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class Text extends Widget {
          const Text(this.text);
          final String text;
        }

        class Navigator {
          static Object? push(BuildContext context, Object route) => null;
        }

        class ProPaywall extends StatefulWidget {
          const ProPaywall();
          _ProPaywallState createState() => _ProPaywallState();
        }

        class _ProPaywallState extends State<ProPaywall> {
          bool annual = false;
          Widget build(BuildContext context) {
            final pushed = Navigator.push(context, 0);
            return Text('Ready');
          }
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.buildMethodTooComplex,
      ]);
      expect(result.issues.single.message, contains("'pushed'"));
    });

    test('accepts a local read only through another local', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class Text extends Widget {
          const Text(this.text);
          final String text;
        }

        class ProPaywall extends StatefulWidget {
          const ProPaywall();
          _ProPaywallState createState() => _ProPaywallState();
        }

        class _ProPaywallState extends State<ProPaywall> {
          bool annual = false;
          Widget build(BuildContext context) {
            final base = 'Annual';
            final label = base;
            return Text(label);
          }
        }
      ''');

      expect(result.issues, isEmpty);
      expect(result.blueprint, isNotNull);
      expect(result.blueprint!.localBindings, hasLength(2));
    });

    test('counts a local consumed by a non-widget key API as read', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class Text extends Widget {
          const Text(this.text);
          final String text;
        }

        String hostText({String? key}) => key ?? '';

        class ProPaywall extends StatelessWidget {
          const ProPaywall();
          Widget build(BuildContext context) {
            final lookup = 'plan';
            return Text(hostText(key: lookup));
          }
        }
      ''');

      expect(result.issues, isEmpty);
      expect(result.blueprint, isNotNull);
      expect(result.blueprint!.localBindings, hasLength(1));
    });

    test('rejects a direct prelude binding cycle', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class ProPaywall extends StatelessWidget {
          const ProPaywall();
          Widget build(BuildContext context) {
            final Widget child = child;
            return child;
          }
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.buildMethodTooComplex,
      ]);
      expect(result.issues.single.message, contains('cyclic build() binding'));
    });

    test('rejects a transitive prelude binding cycle', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class ProPaywall extends StatelessWidget {
          const ProPaywall();
          Widget build(BuildContext context) {
            final Widget first = second;
            final Widget second = first;
            return first;
          }
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.buildMethodTooComplex,
      ]);
      expect(result.issues.single.message, contains('cyclic build() binding'));
    });

    test('rejects a direct cycle through a discarded widget key', () async {
      final result = await _extractBlueprint('''
        import 'package:flutter/material.dart';

        class ProPaywall extends StatelessWidget {
          const ProPaywall();
          Widget build(BuildContext context) {
            final dynamic child = Text('Ready', key: child);
            return child;
          }
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.buildMethodTooComplex,
      ]);
      expect(result.issues.single.message, contains('cyclic build() binding'));
    });

    test('rejects a transitive cycle through a discarded widget key', () async {
      final result = await _extractBlueprint('''
        import 'package:flutter/material.dart';

        class ProPaywall extends StatelessWidget {
          const ProPaywall();
          Widget build(BuildContext context) {
            final dynamic first = second;
            final dynamic second = Text('Ready', key: first);
            return second;
          }
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.buildMethodTooComplex,
      ]);
      expect(result.issues.single.message, contains('cyclic build() binding'));
    });

    test('rejects grouped final declarations', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class Text extends Widget {
          const Text(this.text);
          final String text;
        }

        class ProPaywall extends StatelessWidget {
          const ProPaywall();
          Widget build(BuildContext context) {
            final first = 'A', second = 'B';
            return Text(first + second);
          }
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.buildMethodTooComplex,
      ]);
    });

    test('rejects grouped const declarations', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class Text extends Widget {
          const Text(this.text);
          final String text;
        }

        class ProPaywall extends StatelessWidget {
          const ProPaywall();
          Widget build(BuildContext context) {
            const first = 'A', second = 'B';
            return Text(first + second);
          }
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.buildMethodTooComplex,
      ]);
    });

    test('rejects a final local without an initializer', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class Text extends Widget {
          const Text(this.text);
          final String text;
        }

        class ProPaywall extends StatelessWidget {
          const ProPaywall();
          Widget build(BuildContext context) {
            final String label;
            return Text('Ready');
          }
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.buildMethodTooComplex,
      ]);
      expect(
        result.issues.single.message,
        contains('no resolved declaration or initializer'),
      );
    });

    test('rejects a late final prelude local', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class Text extends Widget {
          const Text(this.text);
          final String text;
        }

        class ProPaywall extends StatelessWidget {
          const ProPaywall();
          Widget build(BuildContext context) {
            late final label = 'Ready';
            return Text(label);
          }
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.buildMethodTooComplex,
      ]);
    });

    test('rejects State.build() with a reassignable local', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class Text extends Widget {
          const Text(this.text);
          final String text;
        }

        class ProPaywall extends StatefulWidget {
          const ProPaywall();
          _ProPaywallState createState() => _ProPaywallState();
        }

        class _ProPaywallState extends State<ProPaywall> {
          bool annual = false;
          Widget build(BuildContext context) {
            var label = 'Ready';
            return Text(label);
          }
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.buildMethodTooComplex,
      ]);
    });

    test('rejects State.build() with a non-declaration statement', () async {
      final result = await _extractBlueprint('''
        $kSourceStateStubs

        class Text extends Widget {
          const Text(this.text);
          final String text;
        }

        class ProPaywall extends StatefulWidget {
          const ProPaywall();
          _ProPaywallState createState() => _ProPaywallState();
        }

        class _ProPaywallState extends State<ProPaywall> {
          bool annual = false;
          Widget build(BuildContext context) {
            annual = true;
            return Text('Ready');
          }
        }
      ''');

      expect(result.blueprint, isNull);
      expect(result.issues.map((issue) => issue.code), [
        IssueCode.buildMethodTooComplex,
      ]);
    });
  });
}

const String kSourceStateStubs = '''
class Widget {
  const Widget();
}

class BuildContext {}

class Key {
  const Key();
}

abstract class StatelessWidget extends Widget {
  const StatelessWidget({this.key});
  final Key? key;
}

abstract class StatefulWidget extends Widget {
  const StatefulWidget();
}

abstract class State<T extends StatefulWidget> {
  late T widget;
  Widget build(BuildContext context);
  void setState(void Function() fn) {}
}
''';

Future<({SourceBuildBlueprint? blueprint, List<Issue> issues})>
    _extractBlueprint(
  String source, {
  String className = 'ProPaywall',
}) async {
  final inputId = AssetId('apps_examples', 'lib/source_state_fixture.dart');
  final assetMap = {inputId.toString(): source};
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: inputId.package,
    includeFlutter: source.contains('package:flutter/'),
  );
  readerWriter.testing.writeString(inputId, source);

  SourceBuildBlueprint? blueprint;
  var issues = <Issue>[];
  await testBuilder(
    _SourceStateProbeBuilder(
      inputId: inputId,
      className: className,
      onResult: (nextBlueprint, nextIssues) {
        blueprint = nextBlueprint;
        issues = nextIssues;
      },
    ),
    assetMap,
    rootPackage: inputId.package,
    readerWriter: readerWriter,
  );

  return (blueprint: blueprint, issues: issues);
}

class _SourceStateProbeBuilder implements Builder {
  _SourceStateProbeBuilder({
    required this.inputId,
    required this.className,
    required this.onResult,
  });

  final AssetId inputId;
  final String className;
  final void Function(SourceBuildBlueprint? blueprint, List<Issue> issues)
      onResult;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.source_state_probe'],
      };

  @override
  Future<void> build(BuildStep step) async {
    if (step.inputId != inputId) return;
    final library = await step.inputLibrary;
    final sourceClass =
        library.classes.firstWhere((element) => element.name == className);
    final issues = <Issue>[];
    final blueprint = await extractSourceBuildBlueprint(
      sourceClass: sourceClass,
      library: library,
      astNodeFor: (fragment) =>
          step.resolver.astNodeFor(fragment, resolve: true),
      issues: issues,
      location: '${step.inputId.path}#$className',
    );
    onResult(blueprint, issues);
  }
}
