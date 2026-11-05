import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

// An app widget whose build passes on the key it was given inlines; one whose
// build creates its own key renders from the app, and says how to fix that.
void main() {
  late RestageSurfacePublicationBundle bundle;

  setUpAll(() async {
    const source = r'''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/keys.restage.g.dart';

class OwnKey extends StatelessWidget {
  const OwnKey({super.key});
  @override
  Widget build(BuildContext context) => const Text('own', key: ValueKey('own'));
}

class SuperKey extends StatelessWidget {
  const SuperKey({super.key});
  @override
  Widget build(BuildContext context) => Text('super', key: key);
}

class StateKey extends StatefulWidget {
  const StateKey({super.key});
  @override
  State<StateKey> createState() => _StateKeyState();
}

class _StateKeyState extends State<StateKey> {
  @override
  Widget build(BuildContext context) => Text('state', key: widget.key);
}

class ParamKey extends StatelessWidget {
  const ParamKey({super.key, required this.tag});
  final Key tag;
  @override
  Widget build(BuildContext context) => Text('param', key: tag);
}

@Paywall(id: 'keys')
final class Keys extends StatelessWidget {
  const Keys({super.key});
  @override
  Widget build(BuildContext context) => const Column(children: [
        OwnKey(),
        SuperKey(key: ValueKey('s')),
        StateKey(key: ValueKey('w')),
        ParamKey(tag: ValueKey('p')),
      ]);
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: true,
    );
    final id = AssetId('apps_examples', 'lib/paywalls/keys.dart');
    readerWriter.testing.writeString(id, source);
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      {id.toString(): source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    bundle = RestageSurfacePublicationBundle.fromJson(
      jsonDecode(
        readerWriter.testing.readString(
          AssetId(
            'apps_examples',
            kRestageSurfacePublicationCompilerBundlePath,
          ),
        ),
      ),
    );
  });

  String design() => utf8.decode(
    bundle.ownedOutputs.entries
        .singleWhere((entry) => entry.key.endsWith('keys.rfwtxt'))
        .value,
  );

  test('a forwarded key inlines the widget', () {
    final dsl = design();
    expect(
      dsl,
      contains('widget SuperKey = Text(text: "super", key: args.key)'),
    );
    expect(
      dsl,
      contains('widget StateKey = Text(text: "state", key: args.key)'),
    );
    expect(
      dsl,
      contains('widget ParamKey = Text(text: "param", key: args.tag)'),
    );
    expect(dsl, contains('SuperKey(key: data.context._h'));
    expect(dsl, contains('StateKey(key: data.context._h'));
    expect(dsl, contains('ParamKey(tag: data.context._h'));
  });

  test('a key the build creates renders the widget from the app', () {
    final islands = [
      for (final site in bundle.splitSites)
        if (site.kind == SplitSiteKind.island) site,
    ];
    expect(islands.map((site) => site.widget), ['OwnKey']);
    expect(
      islands.single.reason,
      "`OwnKey` renders from your app's code because its build() creates its "
      "own key (`ValueKey('own')`). Try passing the key in through "
      "`OwnKey`'s constructor.",
    );
  });
}
