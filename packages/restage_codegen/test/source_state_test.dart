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

    test('rejects State.build() with non-const locals', () async {
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

abstract class StatelessWidget extends Widget {
  const StatelessWidget();
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
    includeFlutter: false,
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
