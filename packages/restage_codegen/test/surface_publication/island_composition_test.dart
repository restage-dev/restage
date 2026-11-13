import 'dart:convert';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../support/surface_build_chain.dart';

// Widgets that render from the app: each is an island where it is placed.
const _widgets = '''
class SpButton extends StatelessWidget {
  // Not const, so building it runs the app's code.
  SpButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onPressed,
        child: CustomPaint(painter: null, child: Text(label)),
      );
}

class PinnedBottomColumn extends StatelessWidget {
  const PinnedBottomColumn({
    super.key,
    required this.bottom,
    required this.children,
    this.padding = EdgeInsets.zero,
  });
  final EdgeInsets padding;
  final Widget bottom;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => CustomScrollView(
        slivers: [
          SliverPadding(padding: padding),
          SliverList(delegate: SliverChildListDelegate(children)),
          SliverFillRemaining(hasScrollBody: false, child: bottom),
        ],
      );
}

class SpBanner extends StatelessWidget {
  const SpBanner.info({super.key, required this.title, required this.rich});
  final String title;
  final Widget rich;
  @override
  Widget build(BuildContext context) => CustomScrollView(
        slivers: [
          SliverList(delegate: SliverChildListDelegate([Text(title), rich])),
        ],
      );
}

class _FirstReminder extends StatelessWidget {
  _FirstReminder(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: null, child: Text(text));
}

class SpOptionCard extends StatelessWidget {
  const SpOptionCard({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.badge,
  });
  final String title;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: CustomPaint(painter: null, child: Text(title)),
      );
}

class _Option {
  const _Option(this.id, this.title);
  final int id;
  final String title;
}

class SpBar extends StatelessWidget implements PreferredSizeWidget {
  SpBar({super.key, required this.title});
  final String title;
  @override
  Size get preferredSize => const Size.fromHeight(40);
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: null, child: Text(title));
}

// Takes an app widget as the one type it is, not as a Widget.
class ButtonFrame extends StatelessWidget {
  const ButtonFrame({super.key, required this.button, this.more = const []});
  final SpButton button;
  final List<SpButton> more;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(4), child: Column(children: [button, ...more]));
}

const List<_Option> _options = [
  _Option(0, 'Sunny'),
  _Option(1, 'Bright'),
  _Option(2, 'Medium'),
  _Option(3, 'Low'),
];
''';

String _surface(String build) =>
    '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
part 'restage.generated/mounted.restage.g.dart';

$_widgets
@Paywall()
final class Mounted extends StatefulWidget {
  const Mounted({super.key});
  @override
  State<Mounted> createState() => _MountedState();
}

class _MountedState extends State<Mounted> {
  int _selected = 0;
  @override
  Widget build(BuildContext context) $build
}
''';

void main() {
  group('an app widget passed straight to another one', () {
    for (final (name, build) in [
      (
        'as a widget argument beside a list',
        '''=> PinnedBottomColumn(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 42),
        bottom: SpButton(
          label: 'Continue',
          onPressed: () => setState(() => _selected = 1),
        ),
        children: [Text('Pick \$_selected')],
      );''',
      ),
      (
        'as the only argument, through a named constructor',
        "=> Column(children: [const Text('Ready'), "
            "SpBanner.info(title: 'Note', rich: _FirstReminder('At \$_selected'))]);",
      ),
    ]) {
      test('$name analyzes clean', () async {
        final source = _surface(build);
        final out = await _compile(source);
        expect(out.errors, isEmpty);
        // The inner widget is built once, in its own island.
        final wraps = RegExp(
          r"_restageRecording\.island\(\s*'([^']*)'",
        ).allMatches(out.part).map((m) => m[1]).toList();
        expect(wraps, hasLength(wraps.toSet().length), reason: out.part);
        await _expectAnalyzesClean({
          'apps_examples|lib/mounted.dart': source,
          'apps_examples|lib/restage.generated/mounted.restage.g.dart':
              out.part,
        });
      });
    }
  });

  // islandNarrowPlacement: an app widget written where only its own type
  // fits makes the widget around it render from the app, so the design never
  // passes the narrow place a Widget.
  group('an app widget where only its own type fits', () {
    for (final (name, build) in [
      (
        'a named argument',
        '''=> ButtonFrame(
        button: SpButton(label: 'Go \$_selected', onPressed: () {}),
      );''',
      ),
      (
        'a list literal typed with it',
        '''=> Column(children: <SpButton>[
        SpButton(label: 'Go \$_selected', onPressed: () {}),
      ]);''',
      ),
      (
        'an app bar a helper returns',
        '''=> Scaffold(appBar: _bar(), body: Text('\$_selected'));
  PreferredSizeWidget _bar() => SpBar(title: 'Bar \$_selected');''',
      ),
      (
        'an element under a condition',
        '''=> ButtonFrame(
        button: SpButton(label: 'Go', onPressed: () {}),
        more: [if (_selected > 0) SpButton(label: 'More', onPressed: () {})],
      );''',
      ),
    ]) {
      test('in $name, the widget around it is the island', () async {
        final source = _surface(build);
        final out = await _compile(source);
        expect(out.errors, isEmpty);
        // What encloses it renders from the app; it is never placed alone.
        expect(out.islands, isNotEmpty);
        expect(out.islands, isNot(contains(contains('SpButton'))));
        expect(out.islands, isNot(contains(contains('SpBar'))));
        await _expectAnalyzesClean({
          'apps_examples|lib/mounted.dart': source,
          'apps_examples|lib/restage.generated/mounted.restage.g.dart':
              out.part,
        });
      });
    }
  });

  group('an app widget in a loop the design unrolls', () {
    const card = '''SpOptionCard(
            title: option.title,
            selected: _selected == option.id,
            onTap: () => setState(() => _selected = option.id),
          )''';
    String names(List<String> ordinals) => [
      for (final o in ordinals)
        "'$o':'mounted_${o.replaceAll('.', '_')}_SpOptionCard_0',",
    ].join();
    final four = [
      'for(finaloptionin_restageRecording.unrolled(0,_options))',
      "_restageRecording.unrolledKey(const{${names(['0', '1', '2', '3'])}},"
          'const[0],)',
    ];
    for (final (name, build, shapes) in [
      (
        'over a const list',
        '''=> Column(children: [
        for (final option in _options)
          $card,
      ]);''',
        four,
      ),
      (
        'spread with a sibling',
        '''=> Column(children: [
        for (final option in _options) ...[
          $card,
          const SizedBox(height: 8),
        ],
      ]);''',
        four,
      ),
      (
        'with design content',
        '''=> Column(children: [
        for (final option in _options)
          SpOptionCard(
            title: option.title,
            badge: 'New',
            selected: _selected == option.id,
            onTap: () => setState(() => _selected = option.id),
          ),
      ]);''',
        four,
      ),
      (
        'inside another unrolled loop',
        '''=> Column(children: [
        for (final row in const [0, 1])
          for (final option in _options)
            Row(children: [Text('\$row'), $card]),
      ]);''',
        [
          'for(finaloptionin_restageRecording.unrolled(1,_options))',
          '_restageRecording.unrolledKey(const{'
              "${names([
                for (final r in ['0', '1'])
                  for (final o in ['0', '1', '2', '3']) '$r.$o',
              ])}},"
              'const[0,1],)',
        ],
      ),
    ]) {
      test('$name places each iteration as its own island', () async {
        final source = _surface(build);
        final out = await _compile(source);
        expect(out.errors, isEmpty);
        // The card wraps in one island, named by the iteration that runs.
        expect(
          RegExp(r'_restageRecording\.island\(').allMatches(out.part),
          hasLength(1),
          reason: out.part,
        );
        final squashed = out.part.replaceAll(RegExp(r'\s'), '');
        for (final text in shapes) {
          expect(squashed, contains(text));
        }
        await _expectAnalyzesClean({
          'apps_examples|lib/mounted.dart': source,
          'apps_examples|lib/restage.generated/mounted.restage.g.dart':
              out.part,
        });
      });
    }
  });
}

Future<({String text, String part, List<String> errors, List<String> islands})>
_compile(String source) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final result = await testBuilders(
    [
      ...surfaceBuildChain(config: const {'bundled_runtime': true}),
    ],
    {'apps_examples|lib/mounted.dart': source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  if (!result.succeeded) {
    return (
      text: '',
      part: '',
      errors: [for (final e in result.errors) '$e'],
      islands: const <String>[],
    );
  }
  final bundle = RestageSurfacePublicationBundle.fromJson(
    jsonDecode(
          readerWriter.testing.readString(
            AssetId(
              'apps_examples',
              kRestageSurfacePublicationCompilerBundlePath,
            ),
          ),
        )
        as Map<String, Object?>,
  );
  return (
    text: utf8.decode(
      bundle.ownedOutputs.entries
          .firstWhere((entry) => entry.key.endsWith('/mounted.rfwtxt'))
          .value,
    ),
    part: readerWriter.testing.readString(
      AssetId('apps_examples', 'lib/restage.generated/mounted.restage.g.dart'),
    ),
    errors: <String>[],
    islands: [
      for (final site in bundle.splitSites)
        if (site.kind.name == 'island') site.widget,
    ],
  );
}

Future<void> _expectAnalyzesClean(Map<String, String> sources) async {
  final entry = sources.keys.first;
  await resolveWorkspaceSources(
    sources,
    (resolver) async {
      final library = await resolver.libraryFor(AssetId.parse(entry));
      final resolved = await library.session.getResolvedLibraryByElement(
        library,
      );
      if (resolved is! ResolvedLibraryResult) {
        throw StateError('$entry did not resolve.');
      }
      // The fixture's own unused declarations are not the generated code's.
      expect([
        for (final unit in resolved.units)
          for (final diagnostic in unit.diagnostics)
            if (diagnostic.severity == Severity.error ||
                diagnostic.severity == Severity.warning &&
                    unit.path.contains('restage.generated'))
              '${unit.path}: ${diagnostic.message}',
      ], isEmpty);
    },
    resolverFor: entry,
    rootPackage: 'apps_examples',
  );
}
