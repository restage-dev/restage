import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
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
        $kSourceStateStubs

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
          Widget build(BuildContext context) => const Widget();
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
      expect(params[0].defaultValueCode, isNull);
      expect(params[1].defaultValueCode, isNull);
      expect(params[2].defaultValueCode, 'null');
      expect(params[2].hasNullDefault, isTrue);
      expect(params[3].defaultValueCode, "'Welcome'");
      expect(params[3].hasNonNullDefault, isTrue);
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
