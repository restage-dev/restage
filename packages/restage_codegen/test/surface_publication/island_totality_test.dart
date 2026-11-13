// Ordinary Flutter source in a surface builds: what the design can't hold
// renders from the app, and the generated part analyzes clean.

import 'dart:convert';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';

import '../helpers.dart';
import '../support/surface_build_chain.dart';

void main() {
  group('a refused surface', () {
    String screen(String name, String build) =>
        """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/$name.restage.g.dart';

@Screen(id: '$name', surface: Surface.onboarding)
final class ${_className(name)} extends StatefulWidget {
  const ${_className(name)}({super.key});
  @override
  State<${_className(name)}> createState() => _${_className(name)}State();
}

class _${_className(name)}State extends State<${_className(name)}> {
  bool _on = false;
  void _off() => setState(() => _on = false);
  void _turnOn() => setState(() => _on = true);
  @override
  Widget build(BuildContext context) => $build;
}
""";
    // A measured callback that runs a different handler in each arm refuses.
    const refusing =
        "TextButton(onPressed: _on ? _off : _turnOn, child: const Text('go'))";
    const building =
        "TextButton(onPressed: _turnOn, child: Text(_on ? 'on' : 'off'))";

    test('fails the whole build, naming its own error', () async {
      final build = await _build({
        'lib/good.dart': screen('good', building),
        'lib/bad.dart': screen('bad', refusing),
      });
      expect(build.succeeded, isFalse);
      expect(build.errors.join('\n'), contains('can run only one handler'));
      // The surface that would build gets no part either.
      expect(build.part('good'), isNull);
      expect(build.part('bad'), isNull);
      expect(build.result['result'], 'failed');
      expect(
        (build.result['errors']! as List).join('\n'),
        contains('can run only one handler'),
      );
    });
  });

  group('a build that reaches beyond its own declarations', () {
    String screen(String name, String body, {String top = ''}) =>
        """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/$name.restage.g.dart';

$top

$body
""";

    test('renders a recursive helper from the app', () async {
      final part = await _builtPart(
        screen('tree', """
@Screen(id: 'tree', surface: Surface.onboarding)
final class Tree extends StatelessWidget {
  const Tree({super.key, this.depth = 3});
  final int depth;
  Widget _a(int n) => n == 0 ? const Text('leaf') : Row(children: [_b(n - 1)]);
  Widget _b(int n) => Padding(padding: const EdgeInsets.all(2), child: _a(n));
  @override
  Widget build(BuildContext context) =>
      Column(children: [const Text('Tree'), _a(depth)]);
}
"""),
        'tree',
        // The rest of the surface is still measured.
        designs: (text) => expect(text, contains('MeasurementPresented')),
      );
      expect(part, contains('_restageSurface._a('));
    });

    test('uses a build inherited from a base class in its library', () async {
      final part = await _builtPart(
        screen(
          'page',
          """
@Screen(id: 'page', surface: Surface.onboarding)
final class Page extends BasePage {
  const Page({super.key});
  @override
  Widget body(BuildContext context) => const Text('hello');
}
""",
          top: '''
abstract class BasePage extends StatelessWidget {
  const BasePage({super.key});
  Widget body(BuildContext context);
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: SafeArea(child: body(context)));
}
''',
        ),
        'page',
      );
      expect(part, contains('_restageSurface.body(context)'));
    });

    test("keeps an author's own `_restage` names", () async {
      final part = await _builtPart(
        screen('label', """
@Screen(id: 'label', surface: Surface.onboarding)
final class Label extends StatelessWidget {
  const Label({super.key});
  @override
  Widget build(BuildContext context) {
    final _restageLabel = 'x';
    debugPrint(_restageLabel);
    return Text(_restageLabel);
  }
}
"""),
        'label',
      );
      expect(part, contains("final _restageLabel = 'x';"));
    });

    for (final (shape, declaration, body) in [
      (
        'an app function',
        "String _restageLocal_headline() => 'app';",
        "if (flag) {\n      final headline = 'block';\n"
            '      return Text(headline);\n    }\n'
            '    return Text(_restageLocal_headline());',
      ),
      (
        'an app final',
        "final _restageLocal_label2 = 'app2';",
        "if (flag) {\n      final label = 'one';\n      return Text(label);"
            '\n    }\n    return Text(_restageLocal_label2);',
      ),
      (
        'a local',
        '',
        'final _restageCount = flag ? 1 : 2;\n'
            r"    return Text('$_restageCount');",
      ),
    ]) {
      test('keeps $shape named with the `_restage` prefix', () async {
        await _builtPart(
          screen('probed', """
@Paywall(id: 'probed')
final class Probed extends StatelessWidget {
  const Probed({super.key, this.flag = false});
  final bool flag;
  @override
  Widget build(BuildContext context) {
    $body
  }
}
""", top: declaration),
          'probed',
        );
      });
    }

    test('refuses a name the generated code also declares', () async {
      final build = await _build({
        'lib/label.dart': screen('label', """
@Screen(id: 'label', surface: Surface.onboarding)
final class Label extends StatelessWidget {
  const Label({super.key});
  @override
  Widget build(BuildContext context) {
    final _restageDesign = 'x';
    return Text(_restageDesign);
  }
}
"""),
      });
      expect(build.succeeded, isFalse);
      expect(
        build.errors.join('\n'),
        contains(
          'the code Restage generates for this surface uses the same name',
        ),
      );
    });

    test('calls the overrides of an inherited build', () async {
      final part = await _builtPart(
        screen(
          'page',
          """
@Screen(id: 'page', surface: Surface.onboarding)
final class Page extends BasePage {
  const Page({super.key});
  @override
  String get title => 'page title';
  @override
  Widget header() => const Text('page header');
}
""",
          top: '''
abstract class BasePage extends StatelessWidget {
  const BasePage({super.key});
  String get title => 'base title';
  Widget header() => const Text('base header');
  @override
  Widget build(BuildContext context) =>
      Column(children: [Text(title), header()]);
}
''',
        ),
        'page',
        designs: (text) => expect(text, isNot(contains('base'))),
      );
      expect(part, contains('_restageSurface.header()'));
      expect(part, contains('_restageSurface.title'));
    });

    test('names the base class of an inherited build it refuses', () async {
      final build = await _build({
        'lib/page.dart': screen(
          'page',
          """
@Screen(id: 'page', surface: Surface.onboarding)
final class Page extends StatefulWidget {
  const Page({super.key});
  @override
  State<Page> createState() => _PageState();
}

class _PageState extends BaseState<Page> {
  @override
  Widget content() => const Text('hello');
}
""",
          top: '''
abstract class BaseState<T extends StatefulWidget> extends State<T> {
  Widget content();
  @override
  Widget build(BuildContext context) => Column(children: [content()]);
}
''',
        ),
      });
      expect(build.succeeded, isFalse);
      expect(
        build.errors.join('\n'),
        contains(
          '`_PageState` inherits build() from `BaseState`. Restage generates '
          'code only from a build() the State class declares. Try declaring '
          'build() in `_PageState`.',
        ),
      );
    });

    test('names the library of an inherited build it refuses', () async {
      final build = await _build({
        'lib/base_page.dart': '''
import 'package:flutter/material.dart';

abstract class BasePage extends StatelessWidget {
  const BasePage({super.key});
  @override
  Widget build(BuildContext context) => const Text('base');
}
''',
        'lib/page.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'base_page.dart';

part 'restage.generated/page.restage.g.dart';

@Screen(id: 'page', surface: Surface.onboarding)
final class Page extends BasePage {
  const Page({super.key});
}
''',
      });
      expect(build.succeeded, isFalse);
      expect(
        build.errors.join('\n'),
        contains(
          '`Page` inherits build() from `BasePage` in '
          "package:apps_examples/base_page.dart. The generated code can't read "
          'that library. Try declaring build() in `Page`, or declaring '
          '`BasePage` in this library.',
        ),
      );
    });

    test('names the mixin of an inherited build it refuses', () async {
      final build = await _build({
        'lib/page.dart': screen(
          'page',
          """
@Screen(id: 'page', surface: Surface.onboarding)
final class Page extends StatelessWidget with TailBuild {
  const Page({super.key});
}
""",
          top: '''
mixin TailBuild on StatelessWidget {
  Widget tail() => const Text('tail');
  @override
  Widget build(BuildContext context) =>
      Column(children: [const Text('mixin build'), tail()]);
}
''',
        ),
      });
      expect(build.succeeded, isFalse);
      expect(
        build.errors.join('\n'),
        contains(
          '[unrecognizedMethodCall] build: '
          "`Column(children: [const Text('mixin build'), tail()])` "
          '(lib/page.dart:',
        ),
      );
      expect(
        build.errors.join('\n'),
        contains(
          "Restage can't compile a build() inherited from the mixin "
          '`TailBuild`. Try declaring it in a base class the screen extends.',
        ),
      );
      expect(build.errors.join('\n'), isNot(contains('inside ``')));
    });
  });

  group('a flow step without its own surface', () {
    String step(String state, String build) =>
        """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/first_run.restage.g.dart';

@Screen(id: 'step')
final class Step1 extends StatefulWidget {
  const Step1({super.key});
  static const next = SurfaceEvent<void>('next');
  @override
  State<Step1> createState() => _Step1State();
}

class _Step1State extends State<Step1> with SingleTickerProviderStateMixin {
$state
  @override
  Widget build(BuildContext context) $build
}

@FlowGraph(id: 'first_run', surface: Surface.onboarding)
const firstRun = FlowDefinition(
  start: Step1,
  transitions: [Transition.complete(Step1.next)],
);
""";

    test('keeps a State with dispose() in its step mount', () async {
      final part = await _builtPart(
        step(
          '  final _c = TextEditingController();\n'
              '  @override\n'
              '  void dispose() { _c.dispose(); super.dispose(); }',
          '=> TextField(controller: _c);',
        ),
        'first_run',
      );
      expect(part, contains(r'restageStepMount$step('));
      expect(part, contains('_c.dispose();'));
    });

    test('keeps a State with a controller field and initState()', () async {
      final part = await _builtPart(
        step(
          '  late final AnimationController _a = AnimationController( '
              'vsync: this, duration: const Duration(seconds: 1));\n'
              '  @override\n'
              '  void initState() { super.initState(); _a.forward(); }',
          "=> FadeTransition(opacity: _a, child: const Text('x'));",
        ),
        'first_run',
      );
      // The kept wrapper and the State's lifecycle run in the step mount.
      expect(part, contains(r"stepMounts: {'step': restageStepMount$step}"));
      expect(part, contains('_a.forward();'));
      expect(part, contains('FadeTransition(opacity: _a,'));
    });

    test('keeps a nullable field and a computed setState', () async {
      await _builtPart(
        step(
          '  String? note;\n'
              '  int _count = 0;\n'
              "  void _set() => setState(() => note = 'x');\n"
              '  void _bump() => setState(() => _count = _count * 2 + 1);',
          r"=> Column(children: [Text(note ?? 'none'), Text('$_count'), "
              "TextButton(onPressed: _set, child: const Text('set')), "
              "TextButton(onPressed: _bump, child: const Text('bump'))]);",
        ),
        'first_run',
      );
    });

    test('copies build statements the design does not hold', () async {
      await _builtPart(
        step(
          '  bool big = false;',
          "{ final label = 'x'; if (big) return const Text('big'); "
              "return const Text('small'); }",
        ),
        'first_run',
      );
    });
  });

  group('a measured tap whose closure sets State', () {
    String screen(
      String build, {
      String state = '  int _count = 0;',
      String annotation = "@Screen(id: 'probe', surface: Surface.onboarding)",
      String trailer = '',
    }) =>
        """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/probe.restage.g.dart';

$annotation
final class Probe extends StatefulWidget {
  const Probe({super.key});
  static const next = SurfaceEvent<void>('next');
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
$state
  @override
  Widget build(BuildContext context) => $build;
}
$trailer
""";

    test('moves the State into the mount and stays measured', () async {
      final part = await _builtPart(
        screen(
          'GestureDetector(onTap: () => setState(() => _count++), '
          "child: const Text('tap'))",
        ),
        'probe',
        designs: (text) =>
            expect(text, contains('__restage_measurement_tap_v1')),
      );
      expect(part, contains('() => setState(() => _count++)'));
    });

    test('builds when a sibling reads State the design keeps', () async {
      await _builtPart(
        screen(
          'Column(children: [Text(_label), GestureDetector(onTap: () => '
          "setState(() => _label = _label + 'a'), child: const Text('tap'))])",
          state: "  String _label = 'a';",
        ),
        'probe',
      );
    });

    test('builds in a flow step without its own surface', () async {
      await _builtPart(
        screen(
          'TextButton(onPressed: () => setState(() => _count++), '
          r"child: Text('$_count'))",
          annotation: "@Screen(id: 'probe')",
          trailer: '''
@FlowGraph(id: 'probe_flow', surface: Surface.onboarding)
const probeFlow = FlowDefinition(
  start: Probe,
  transitions: [Transition.complete(Probe.next)],
);
''',
        ),
        'probe',
      );
    });
  });

  test('a step with its own surface keeps its State in the flow', () async {
    final part = await _builtPart(
      """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/first_run.restage.g.dart';

@Screen(id: 'step', surface: Surface.onboarding)
final class Step1 extends StatefulWidget {
  const Step1({super.key});
  static const next = SurfaceEvent<void>('next');
  @override
  State<Step1> createState() => _Step1State();
}

class _Step1State extends State<Step1> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
      vsync: this, duration: const Duration(seconds: 1));
  @override
  void initState() { super.initState(); _a.forward(); }
  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _a, child: const Text('x'));
}

@FlowGraph(id: 'first_run', surface: Surface.onboarding)
const firstRun = FlowDefinition(
  start: Step1,
  transitions: [Transition.complete(Step1.next)],
);
""",
      'first_run',
    );
    expect(part, contains(r"stepMounts: {'step': restageStepMount$step}"));
  });
}

String _className(String name) => name[0].toUpperCase() + name.substring(1);

/// Builds [sources] and returns the result, each generated part, and the
/// build result it recorded.
Future<
  ({
    bool succeeded,
    List<String> errors,
    List<String> warnings,
    String? Function(String name) part,
    Map<String, Object?> result,
  })
>
_build(Map<String, String> sources) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final warnings = <String>[];
  final result = await testBuilders(
    _builders,
    {
      for (final entry in sources.entries)
        'apps_examples|${entry.key}': entry.value,
    },
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) {
      if (record.level == Level.WARNING) warnings.add(record.message);
    },
  );
  String? part(String name) {
    final id = AssetId(
      'apps_examples',
      'lib/restage.generated/$name.restage.g.dart',
    );
    return readerWriter.testing.exists(id)
        ? readerWriter.testing.readString(id)
        : null;
  }

  return (
    succeeded: result.succeeded,
    errors: result.errors.toList(),
    warnings: warnings,
    part: part,
    result:
        jsonDecode(
              readerWriter.testing.readString(
                AssetId(
                  'apps_examples',
                  '.restage/build/metadata/restage.build.json',
                ),
              ),
            )
            as Map<String, Object?>,
  );
}

final List<Builder> _builders = surfaceBuildChain(
  config: const {'bundled_runtime': true},
);

/// Builds [source] as `lib/[name].dart`, expects success, and returns its
/// generated part after checking that it analyzes without errors. [designs]
/// receives the text of every emitted blob.
Future<String> _builtPart(
  String source,
  String name, {
  Map<String, String> otherFiles = const {},
  void Function(String text)? designs,
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final result = await testBuilders(
    _builders,
    {'apps_examples|lib/$name.dart': source, ...otherFiles},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  final partPath = 'lib/restage.generated/$name.restage.g.dart';
  final part = readerWriter.testing.readString(
    AssetId('apps_examples', partPath),
  );
  final errors = await resolveWorkspaceSources(
    {
      'apps_examples|lib/$name.dart': source,
      'apps_examples|$partPath': part,
      ...otherFiles,
    },
    (resolver) async {
      final library = await resolver.libraryFor(
        AssetId.parse('apps_examples|lib/$name.dart'),
      );
      final resolved = await library.session.getResolvedLibraryByElement(
        library,
      );
      if (resolved is! ResolvedLibraryResult) return ['did not resolve'];
      return [
        for (final unit in resolved.units)
          for (final diagnostic in unit.diagnostics)
            if (diagnostic.severity == Severity.error) diagnostic.toString(),
      ];
    },
    resolverFor: 'apps_examples|lib/$name.dart',
    rootPackage: 'apps_examples',
  );
  expect(errors, isEmpty, reason: part);
  if (designs != null) {
    final bundle = RestageSurfacePublicationBundle.fromJson(
      jsonDecode(
        readerWriter.testing.readString(
          AssetId(
            'apps_examples',
            kRestageSurfacePublicationCompilerBundlePath,
          ),
        ),
      ),
    );
    designs(
      [
        for (final entry in bundle.artifacts.entries)
          if (entry.key.endsWith('.rfw'))
            fmt.decodeLibraryBlob(Uint8List.fromList(entry.value)).toString(),
      ].join('\n'),
    );
  }
  return part;
}
