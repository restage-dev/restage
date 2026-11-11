import 'dart:convert';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/islands/island_registration.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';

import '../helpers.dart';

const _pill = '''
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(4), child: Text(label));
}
''';

const _painted = '''
class Painted extends StatelessWidget {
  const Painted({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: null, child: Text(label));
}
''';

String _surface(
  String body, {
  String imports = '',
  String classes = '',
  String annotation = '@Paywall()',
}) =>
    '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
$imports
part 'restage.generated/mounted.restage.g.dart';

$classes
$annotation
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) => Column(children: [$body]);
}
''';

void main() {
  test('an app widget forwards a key it is given', () async {
    final out = await _compile(
      _surface(
        "AppKeyed(tag: const ValueKey('a'), label: 'x'), "
        "Text('y', key: const ValueKey('a'))",
        classes: r'''
class AppKeyed extends StatelessWidget {
  const AppKeyed({super.key, required this.tag, required this.label});
  final Key tag;
  final String label;
  @override
  Widget build(BuildContext context) => Text(label, key: tag);
}
''',
      ),
    );
    expect(out.errors, isEmpty);
    expect(
      out.text,
      contains('widget AppKeyed = Text(text: args.label, key: args.tag);'),
    );
    // The call site passes the key as a direct site does.
    final direct = RegExp(
      r'Text\(text: "y", key: (data\.context\._h\w+)\)',
    ).firstMatch(out.text)!.group(1);
    expect(out.text, contains('AppKeyed(tag: $direct, label: "x")'));
  });

  test(
    'an annotated widget no library exports warns and still inlines',
    () async {
      final out = await _compile(
        _surface(
          "Pill(label: 'Pro')",
          imports:
              "import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';",
          classes: '/// A pill.\n@RestageWidget()\n$_pill',
        ),
      );
      expect(out.errors, isEmpty);
      expect(out.text, contains('widget Pill = Padding('));
      expect(out.warnings, contains(contains('`Pill` (lib/mounted.dart:')));
      expect(
        out.warnings,
        contains(
          contains(
            'is annotated with `@RestageWidget`, and no '
            '`@RestageLibrary` library exports it.',
          ),
        ),
      );
    },
  );

  test('a delivered widget is published as a shared component', () async {
    final out = await _compile(
      _surface(
        "Pill(label: 'Pro'), GridView.count(crossAxisCount: 2, shrinkWrap: true, children: const [])",
        imports: "import 'package:apps_examples/ui.dart';",
      ),
      otherFiles: {
        'apps_examples|lib/ui.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
export 'pill.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('apps_examples.ui'),
  capabilityVersion: 1,
)
const restageUiLibrary = 0;
''',
        'apps_examples|lib/pill.dart': '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A pill.
@RestageWidget()
class Pill extends StatelessWidget {
  /// Creates a pill.
  const Pill({super.key, required this.label});

  /// The label.
  final String label;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(4), child: Text(label));
}
''',
      },
    );
    expect(out.errors, isEmpty);
    final bundle = out.bundle!;
    final components = bundle.surfaceComponents['paywall/mounted']!;
    expect([for (final c in components) c.name], ['apps_examples.ui.Pill']);
    final component = components.single;
    expect(component.name, 'apps_examples.ui.Pill');
    expect(component.declaration, 'Pill');
    final payload =
        SurfacePayload.decode(component.payload) as BlobSurfacePayload;
    expect(
      [for (final w in fmt.decodeLibraryBlob(payload.blob).widgets) w.name],
      [kSharedComponentEntryName],
    );
    // The editor's pin compares these two fingerprints.
    final surface = Uint8List.fromList(
      bundle.artifacts['assets/paywalls/mounted.rfw']!,
    );
    expect(
      componentFingerprint(
        payload.blob,
        kSharedComponentEntryName,
        const {},
      ).fingerprint,
      component.fingerprint,
    );
    expect(
      componentFingerprint(surface, 'Pill', const {}).fingerprint,
      component.fingerprint,
    );
    // Its own requirements: only the surface needs the grid's floor.
    final surfaceFloor = CapabilitySidecar.fromJson(
      jsonDecode(
            utf8.decode(
              bundle.artifacts['assets/paywalls/mounted.capability.json']!,
            ),
          )
          as Map<String, dynamic>,
    ).manifest.builtInFloor;
    expect(surfaceFloor, greaterThanOrEqualTo(20));
    expect(payload.minClient, lessThan(surfaceFloor));
    expect(payload.requiredLibraries, isEmpty);
  });

  // A widget the build splits fires a shared event the screen doesn't
  // declare; the event is still in the screen's contract.
  test("a split widget's events join the screen's contract", () async {
    final out = await _compile(
      _surface(
        "DismissCard(label: 'Later')",
        imports:
            "import 'package:apps_examples/ui.dart';\n"
            "import 'package:apps_examples/common_events.dart';",
        annotation: "@Screen(id: 'mounted', surface: Surface.general)",
      ),
      otherFiles: {
        'apps_examples|lib/common_events.dart': '''
import 'package:restage/restage.dart';

abstract final class CommonEvents {
  static const dismiss = SurfaceEvent<void>('dismiss');
}
''',
        'apps_examples|lib/ui.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
export 'dismiss_card.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('apps_examples.ui'),
  capabilityVersion: 1,
)
const restageUiLibrary = 0;
''',
        'apps_examples|lib/dismiss_card.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

import 'common_events.dart';

part 'restage.generated/dismiss_card.restage.g.dart';

/// A card that dismisses its surface.
@RestageWidget()
class DismissCard extends StatelessWidget {
  /// Creates a card.
  const DismissCard({super.key, required this.label});

  /// The label.
  final String label;

  @override
  Widget build(BuildContext context) => Column(children: [
        CustomPaint(child: Text(label)),
        TextButton(
          onPressed: context.surfaceEvent(CommonEvents.dismiss),
          child: Text(label),
        ),
      ]);
}
''',
      },
    );
    expect(out.errors, isEmpty);
    expect(out.text, contains('widget DismissCard = DismissCard__split('));
    expect(out.part, contains('MountedSurfaceDismissEvent'));
  });

  test('a split inside a split brings its events too', () async {
    final out = await _compile(
      _surface(
        "OuterCard(label: 'Later')",
        imports:
            "import 'package:apps_examples/ui.dart';\n"
            "import 'package:apps_examples/common_events.dart';",
        annotation: "@Screen(id: 'mounted', surface: Surface.general)",
        // Another screen places the inner card, so it splits too.
        classes: '''
@Screen(id: 'other', surface: Surface.general)
final class Other extends StatelessWidget {
  const Other({super.key});
  @override
  Widget build(BuildContext context) => const DismissCard(label: 'Now');
}
''',
      ),
      otherFiles: {
        'apps_examples|lib/common_events.dart': '''
import 'package:restage/restage.dart';

abstract final class CommonEvents {
  static const dismiss = SurfaceEvent<void>('dismiss');
}
''',
        'apps_examples|lib/ui.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
export 'dismiss_card.dart';
export 'outer_card.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('apps_examples.ui'),
  capabilityVersion: 1,
)
const restageUiLibrary = 0;
''',
        'apps_examples|lib/dismiss_card.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

import 'common_events.dart';

part 'restage.generated/dismiss_card.restage.g.dart';

/// A card that dismisses its surface.
@RestageWidget()
class DismissCard extends StatelessWidget {
  /// Creates a card.
  const DismissCard({super.key, required this.label});

  /// The label.
  final String label;

  @override
  Widget build(BuildContext context) => Column(children: [
        CustomPaint(child: Text(label)),
        TextButton(
          onPressed: context.surfaceEvent(CommonEvents.dismiss),
          child: Text(label),
        ),
      ]);
}
''',
        'apps_examples|lib/outer_card.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

import 'dismiss_card.dart';

part 'restage.generated/outer_card.restage.g.dart';

/// A card that holds a dismiss card.
@RestageWidget()
class OuterCard extends StatelessWidget {
  /// Creates a card.
  const OuterCard({super.key, required this.label});

  /// The label.
  final String label;

  @override
  Widget build(BuildContext context) => Column(children: [
        CustomPaint(child: Text(label)),
        DismissCard(label: label),
      ]);
}
''',
      },
    );
    expect(out.errors, isEmpty);
    expect(out.text, contains('widget OuterCard = OuterCard__split('));
    expect(out.part, contains('MountedSurfaceDismissEvent'));
  });

  // Reached only through the outer card, the inner card is an island of
  // the outer card's build; its own build fires the event.
  test("an island inside a split brings its build's events", () async {
    final out = await _compile(
      _surface(
        "OuterCard(label: 'Later')",
        imports:
            "import 'package:apps_examples/ui.dart';\n"
            "import 'package:apps_examples/common_events.dart';",
        annotation: "@Screen(id: 'mounted', surface: Surface.general)",
      ),
      otherFiles: {
        'apps_examples|lib/common_events.dart': '''
import 'package:restage/restage.dart';

abstract final class CommonEvents {
  static const dismiss = SurfaceEvent<void>('dismiss');
}
''',
        'apps_examples|lib/ui.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
export 'dismiss_card.dart';
export 'outer_card.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('apps_examples.ui'),
  capabilityVersion: 1,
)
const restageUiLibrary = 0;
''',
        'apps_examples|lib/dismiss_card.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

import 'common_events.dart';

part 'restage.generated/dismiss_card.restage.g.dart';

/// A card that dismisses its surface.
@RestageWidget()
class DismissCard extends StatelessWidget {
  /// Creates a card.
  const DismissCard({super.key, required this.label});

  /// The label.
  final String label;

  @override
  Widget build(BuildContext context) => Column(children: [
        CustomPaint(child: Text(label)),
        TextButton(
          onPressed: context.surfaceEvent(CommonEvents.dismiss),
          child: Text(label),
        ),
      ]);
}
''',
        'apps_examples|lib/outer_card.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

import 'dismiss_card.dart';

part 'restage.generated/outer_card.restage.g.dart';

/// A card that holds a dismiss card.
@RestageWidget()
class OuterCard extends StatelessWidget {
  /// Creates a card.
  const OuterCard({super.key, required this.label});

  /// The label.
  final String label;

  @override
  Widget build(BuildContext context) => Column(children: [
        CustomPaint(child: Text(label)),
        DismissCard(label: label),
      ]);
}
''',
      },
    );
    expect(out.errors, isEmpty);
    expect(out.text, contains('widget OuterCard = OuterCard__split('));
    expect(out.part, contains('MountedSurfaceDismissEvent'));
  });

  group('a custom widget that does not fully inline', () {
    Map<String, String> files({required bool part}) => {
      'apps_examples|lib/ui.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
export 'plan_card.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('apps_examples.ui'),
  capabilityVersion: 1,
)
const restageUiLibrary = 0;
''',
      'apps_examples|lib/plan_card.dart':
          '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
${part ? "part 'restage.generated/plan_card.restage.g.dart';" : ''}

/// A plan card.
@RestageWidget()
class PlanCard extends StatelessWidget {
  /// Creates a card.
  const PlanCard({super.key, required this.label});

  /// The label.
  final String label;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label),
        CustomPaint(child: Text(label)),
      ]);
}
''',
    };

    test('is split, its wrapper generated in its own part', () async {
      final out = await _compile(
        _surface(
          "PlanCard(key: const ValueKey('pro'), label: 'Pro')",
          imports: "import 'package:apps_examples/ui.dart';",
        ),
        otherFiles: files(part: true),
      );
      // Delivered: the text. From the app: the painter, as the wrapper's
      // island; the wrapper keeps the placement's key.
      expect(out.errors, isEmpty);
      expect(
        out.text,
        contains(
          'widget PlanCard = PlanCard__split(key: args.key, '
          'label: args.label, restageIsland: args.restageIsland, '
          'restageItems: args.restageItems, '
          'restageWidget: __RestageBuilderContinuation(',
        ),
      );
      expect(
        out.text,
        contains(
          '(restageWidget) => Column(children: '
          '[Text(text: args.label), PlanCard_CustomPaint_0(',
        ),
      );
      expect(
        out.text,
        contains('widget Paywall = Column(children: [PlanCard('),
      );
      final part = utf8.decode(
        out
            .bundle!
            .ownedOutputs['lib/restage.generated/plan_card.restage.g.dart']!,
      );
      expect(part, contains(r'const restageSplit$PlanCard ='));
      expect(out.bundle!.splitRegistrations, [
        (
          namespace: 'apps_examples.ui',
          library: 'package:apps_examples/plan_card.dart',
          name: r'restageSplit$PlanCard',
        ),
      ]);
      await _expectAnalyzesClean({
        'apps_examples|lib/plan_card.dart': files(
          part: true,
        )['apps_examples|lib/plan_card.dart']!,
        'apps_examples|lib/restage.generated/plan_card.restage.g.dart': part,
        'apps_examples|lib/ui.dart': files(
          part: true,
        )['apps_examples|lib/ui.dart']!,
      });
      // Its island registers app-wide in its own library, and the surface's
      // mount registers it with the wrapper.
      expect(
        out.bundle!.splitSites.map((site) => (site.mount, site.name)),
        contains((
          'PlanCard__split',
          'apps_examples.islands:PlanCard_CustomPaint_0',
        )),
      );
      expect(out.part, contains(r'restageSplit$PlanCard'));
      expect(out.part, contains(r'restageIslands$PlanCard_CustomPaint_0'));
      // The design and the app's build key the wrapper by one name, so its
      // State moves between them.
      expect(out.text, contains('restageIsland: "mounted_PlanCard_0"'));
      expect(
        out.part.replaceAll(RegExp(r'\s+'), ' '),
        contains(
          r"_restageRecording.island( 'mounted_PlanCard_0', PlanCard(",
        ),
      );
      expect(
        out.part.replaceAll(RegExp(r'\s+'), ' '),
        contains(r'place: restageSplitApp$PlanCard, )'),
      );
      expect(part, contains(r'Widget restageSplitApp$PlanCard('));
      await _expectAnalyzesClean({
        'apps_examples|lib/mounted.dart': _surface(
          "PlanCard(key: const ValueKey('pro'), label: 'Pro')",
          imports: "import 'package:apps_examples/ui.dart';",
        ),
        'apps_examples|lib/restage.generated/mounted.restage.g.dart': out.part,
        'apps_examples|lib/plan_card.dart': files(
          part: true,
        )['apps_examples|lib/plan_card.dart']!,
        'apps_examples|lib/restage.generated/plan_card.restage.g.dart': part,
        'apps_examples|lib/ui.dart': files(
          part: true,
        )['apps_examples|lib/ui.dart']!,
      });
    });

    // Every name the mount needs beside the class, refused in one problem.
    const hiddenRows = [
      (
        'shows only the class',
        'show PlanCard',
        [
          r'restageSplit$PlanCard',
          r'restageIslands$PlanCard_CustomPaint_0',
          r'restageSplitApp$PlanCard',
        ],
      ),
      (
        'shows the class and its registrations',
        r'show PlanCard, restageSplit$PlanCard, '
            r'restageIslands$PlanCard_CustomPaint_0',
        [r'restageSplitApp$PlanCard'],
      ),
      (
        'hides the function that wraps the app widget',
        r'hide restageSplitApp$PlanCard',
        [r'restageSplitApp$PlanCard'],
      ),
    ];
    String hiddenProblem(List<String> missing) {
      final names = [for (final name in missing) '`$name`'];
      final listed = names.length == 1
          ? names.single
          : '${names.take(names.length - 1).join(', ')} and ${names.last}';
      return "`MountedSurface` can't register `PlanCard`. lib/mounted.dart "
          'imports `PlanCard` with a `show` or `hide` list that leaves out '
          '$listed, which Restage generates beside `PlanCard`. Try importing '
          'that library without `show` or `hide`, or adding '
          "${names.length == 1 ? listed : 'them'} to its `show` list.";
    }

    Future<void> expectPartAnalyzes(
      String source,
      String part,
      RestageSurfacePublicationBundle? bundle,
    ) => _expectAnalyzesClean(
      {
        'apps_examples|lib/mounted.dart': source,
        'apps_examples|lib/restage.generated/mounted.restage.g.dart': part,
        'apps_examples|lib/plan_card.dart': files(
          part: true,
        )['apps_examples|lib/plan_card.dart']!,
        'apps_examples|lib/restage.generated/plan_card.restage.g.dart': utf8
            .decode(
              bundle!
                  .ownedOutputs['lib/restage.generated/plan_card.restage.g.dart']!,
            ),
        'apps_examples|lib/ui.dart': files(
          part: true,
        )['apps_examples|lib/ui.dart']!,
      },
    );

    for (final (name, combinator, missing) in hiddenRows) {
      test('fails the build when the import $name', () async {
        final source = _surface(
          "PlanCard(label: 'Pro')",
          imports: "import 'package:apps_examples/ui.dart' $combinator;",
        );
        final out = await _compile(source, otherFiles: files(part: true));
        expect(out.errors.join('\n'), contains(hiddenProblem(missing)));
        expect(out.bundle, isNull);
      });
    }

    test(
      'following the refusal once gives the placement its identity',
      () async {
        final refused = await _compile(
          _surface(
            "PlanCard(label: 'Pro')",
            imports: "import 'package:apps_examples/ui.dart' show PlanCard;",
          ),
          otherFiles: files(part: true),
        );
        final problem = refused.errors.firstWhere(
          (error) => error.contains("can't register `PlanCard`"),
        );
        final named = RegExp(
          r'leaves out (.*), which Restage',
        ).firstMatch(problem)!.group(1)!;
        final shown = [
          for (final match in RegExp(r'`([^`]+)`').allMatches(named))
            match.group(1)!,
        ];
        final source = _surface(
          "PlanCard(label: 'Pro')",
          imports:
              "import 'package:apps_examples/ui.dart' "
              "show PlanCard, ${shown.join(', ')};",
        );
        final out = await _compile(source, otherFiles: files(part: true));
        expect(out.errors, isEmpty);
        expect(
          out.warnings.where((warning) => warning.contains("can't register")),
          isEmpty,
        );
        expect(out.text, contains('restageIsland: "mounted_PlanCard_0"'));
        expect(
          out.part.replaceAll(RegExp(r'\s+'), ' '),
          contains(
            r"_restageRecording.island( 'mounted_PlanCard_0', PlanCard(",
          ),
        );
        await expectPartAnalyzes(source, out.part, out.bundle);
      },
    );

    for (final (kind, annotation) in [
      ('paywall', '@Paywall()'),
      ('general screen', "@Screen(id: 'mounted', surface: Surface.general)"),
    ]) {
      test('a $kind splits it with one identity on both paths', () async {
        final source = _surface(
          "PlanCard(label: 'Pro')",
          imports: "import 'package:apps_examples/ui.dart';",
          annotation: annotation,
        );
        final out = await _compile(source, otherFiles: files(part: true));
        expect(out.errors, isEmpty);
        expect(
          out.warnings.where((warning) => warning.contains('PlanCard')),
          isEmpty,
        );
        expect(out.text, contains('widget PlanCard = PlanCard__split('));
        expect(out.text, contains('restageIsland: "mounted_PlanCard_0"'));
        expect(
          out.part.replaceAll(RegExp(r'\s+'), ' '),
          contains(
            r"_restageRecording.island( 'mounted_PlanCard_0', PlanCard("
            r"label: 'Pro'), place: restageSplitApp$PlanCard, )",
          ),
        );
        await expectPartAnalyzes(source, out.part, out.bundle);
      });
    }

    test('renders whole from the app when its library has no part', () async {
      final out = await _compile(
        _surface(
          "PlanCard(label: 'Pro')",
          imports: "import 'package:apps_examples/ui.dart';",
        ),
        otherFiles: files(part: false),
      );
      expect(out.errors, isEmpty);
      expect(out.text, isNot(contains('__split')));
      // Its factory builds it where the design places it, keyed as the
      // app's build keys it, so its State moves between the two.
      expect(
        out.text,
        contains('PlanCard(label: "Pro", restageIsland: "mounted_PlanCard_0")'),
      );
      expect(
        out.part.replaceAll(RegExp(r'\s+'), ' '),
        contains(
          r"_restageRecording.island( 'mounted_PlanCard_0', PlanCard("
          r"label: 'Pro'), place: RestageRecording.itself, )",
        ),
      );
      expect(
        out.warnings,
        contains(
          contains(
            "Designs can't change what's inside `PlanCard` "
            '(lib/plan_card.dart:',
          ),
        ),
      );
    });
  });

  test("a split widget's State callback crosses from its wrapper", () async {
    final out = await _compile(
      _surface(
        "TallyCard(label: 'A')",
        imports: "import 'package:apps_examples/tally_card.dart';",
      ),
      otherFiles: {
        'apps_examples|lib/tally_card.dart': r'''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'restage.generated/tally_card.restage.g.dart';

var tallies = 0;

/// A card that counts its taps.
@RestageWidget(library: WidgetLibrary.custom('apps_examples.ui'))
class TallyCard extends StatefulWidget {
  /// Creates a card.
  const TallyCard({super.key, required this.label});

  /// The label.
  final String label;

  @override
  State<TallyCard> createState() => _TallyCardState();
}

class _TallyCardState extends State<TallyCard> {
  late final int _id = ++tallies;
  var _taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => setState(() => _taps++),
        child: Text('${widget.label} #$_id: $_taps'),
      );
}
''',
        'apps_examples|lib/ui.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
export 'tally_card.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('apps_examples.ui'),
  capabilityVersion: 1,
)
const restageUiLibrary = 0;
''',
      },
    );
    expect(out.errors, isEmpty);
    expect(out.text, contains('widget TallyCard = TallyCard__split('));
    expect(out.text, contains('onTap: {nativeEvent: restageWidget.values._h'));
    // The surface's mount registers the wrapper it places.
    expect(out.warnings.where((w) => w.contains("can't register")), isEmpty);
    expect(out.part, contains(r'libraries: [restageSplit$TallyCard]'));
  });

  test("a split widget's data-class argument analyzes clean", () async {
    const tile = r'''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'restage.generated/plan_tile.restage.g.dart';

/// A plan.
class Plan {
  /// Creates a plan.
  const Plan({required this.name});

  /// The plan's name.
  final String name;
}

/// A tile that shows a plan.
@RestageWidget(library: WidgetLibrary.custom('apps_examples.ui'))
class PlanTile extends StatelessWidget {
  /// Creates a tile.
  const PlanTile({super.key, required this.plan});

  /// The plan shown.
  @RestageProperty(description: 'The plan shown.', required: true)
  final Plan plan;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(plan.name),
        CustomPaint(child: Text(plan.name)),
      ]);
}
''';
    const ui = '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
export 'plan_tile.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('apps_examples.ui'),
  capabilityVersion: 1,
)
const restageUiLibrary = 0;
''';
    final out = await _compile(
      _surface(
        "PlanTile(plan: const Plan(name: 'Pro'))",
        imports: "import 'package:apps_examples/ui.dart';",
      ),
      otherFiles: {
        'apps_examples|lib/plan_tile.dart': tile,
        'apps_examples|lib/ui.dart': ui,
      },
    );
    expect(out.errors, isEmpty);
    expect(out.text, contains('widget PlanTile = PlanTile__split('));
    final part = utf8.decode(
      out
          .bundle!
          .ownedOutputs['lib/restage.generated/plan_tile.restage.g.dart']!,
    );
    // The wrapper's build decodes the widget from its source once.
    final build = part.substring(part.indexOf('Widget build('));
    expect(RegExp(r'\b_restageWidget\b(?!\$)').allMatches(build), hasLength(1));
    expect(build, contains('_restageSurface.plan'));
    await _expectAnalyzesClean({
      'apps_examples|lib/plan_tile.dart': tile,
      'apps_examples|lib/restage.generated/plan_tile.restage.g.dart': part,
      'apps_examples|lib/ui.dart': ui,
    });
  });

  test("a split widget's recorded text scaler reaches its body", () async {
    final out = await _compile(
      _surface(
        "ScaledCard(label: 'A')",
        imports: "import 'package:apps_examples/scaled_card.dart';",
      ),
      otherFiles: {
        'apps_examples|lib/scaled_card.dart': r'''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'restage.generated/scaled_card.restage.g.dart';

/// A card whose label follows the app's text scale.
@RestageWidget(library: WidgetLibrary.custom('apps_examples.ui'))
class ScaledCard extends StatefulWidget {
  /// Creates a card.
  const ScaledCard({super.key, required this.label});

  /// The label.
  final String label;

  @override
  State<ScaledCard> createState() => _ScaledCardState();
}

class _ScaledCardState extends State<ScaledCard> {
  @override
  Widget build(BuildContext context) => Text(widget.label,
      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.5));
}
''',
        'apps_examples|lib/ui.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
export 'scaled_card.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('apps_examples.ui'),
  capabilityVersion: 1,
)
const restageUiLibrary = 0;
''',
      },
    );
    expect(out.errors, isEmpty);
    expect(out.text, contains('widget ScaledCard = ScaledCard__split('));
    expect(out.text, contains('textScaler: restageWidget.values._h'));
    final part = utf8
        .decode(
          out
              .bundle!
              .ownedOutputs['lib/restage.generated/scaled_card.restage.g.dart']!,
        )
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(part, contains('textScalers: _restageRecording.scalers'));
    expect(part, contains('"kind": "native"'));
  });

  group('a custom widget from a path package', () {
    const card = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'restage.generated/plan_card.restage.g.dart';

/// A plan card.
@RestageWidget()
class PlanCard extends StatelessWidget {
  /// Creates a plan card.
  const PlanCard({super.key, required this.label});

  /// The label.
  final String label;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label),
        CustomPaint(child: Text(label)),
      ]);
}
''';
    const barrel = '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
export 'plan_card.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('sprout_design.ui'),
  capabilityVersion: 1,
)
const restageUiLibrary = 0;
''';
    const partPath =
        'sprout_design|lib/restage.generated/plan_card.restage.g.dart';
    final app = _surface(
      "PlanCard(label: 'Pro')",
      imports: "import 'package:sprout_design/plan_card.dart';",
    );

    late Map<String, String> package;
    setUpAll(() async {
      // The package's own build, which commits the wrapper part.
      package = await _buildPackage('sprout_design', {
        'sprout_design|lib/plan_card.dart': card,
        'sprout_design|lib/ui.dart': barrel,
      });
    });
    Map<String, String> sources({String? part}) => {
      'sprout_design|lib/plan_card.dart': card,
      'sprout_design|lib/ui.dart': barrel,
      for (final MapEntry(:key, :value) in package.entries)
        'sprout_design|$key': value,
      if (part != null) partPath: part,
    };

    test('splits through the wrapper its own build generated', () async {
      final part = package[partPath.split('|').last];
      expect(part, isNotNull);
      expect(part, contains(r'const restageSplit$PlanCard ='));
      expect(part, contains(r'const restageSplitDefinition$PlanCard ='));
      // The app's build reads it.
      final out = await _compile(app, otherFiles: sources());
      expect(out.errors, isEmpty);
      expect(
        out.text,
        contains(
          'widget PlanCard = PlanCard__split(key: args.key, label: args.label',
        ),
      );
      expect(
        out.bundle!.ownedOutputs.keys,
        isNot(contains('lib/restage.generated/plan_card.restage.g.dart')),
      );
      expect(out.bundle!.splitRegistrations, [
        (
          namespace: 'sprout_design.ui',
          library: 'package:sprout_design/plan_card.dart',
          name: r'restageSplit$PlanCard',
        ),
      ]);
      // Its island registers in its own package's islands library, app-wide
      // and with the surface's mount.
      expect(out.warnings.where((w) => w.contains("can't register")), isEmpty);
      expect(out.part, contains(r'restageIslands$PlanCard_CustomPaint_0'));
      final islands = islandRegistration(
        'apps_examples',
        out.bundle!.splitSites,
      );
      expect(
        islands!.registrations,
        contains("WidgetLibrary.custom('sprout_design.islands')"),
      );
    });

    test('renders whole from the app without that wrapper', () async {
      final out = await _compile(
        app,
        otherFiles: sources(part: "part of '../plan_card.dart';\n"),
      );
      expect(out.errors, isEmpty);
      expect(out.text, isNot(contains('__split')));
      expect(
        out.warnings,
        contains(
          contains(
            "Designs can't change what's inside `PlanCard` "
            '(lib/plan_card.dart:',
          ),
        ),
      );
      expect(
        out.warnings,
        contains(
          contains(
            'in package sprout_design) because the code '
            'Restage generates for it in sprout_design is missing or out of '
            'date.',
          ),
        ),
      );
    });
  });

  group('a typed callback that calls the app crosses as its closure', () {
    const toggle = r'''
class AppToggle extends StatelessWidget {
  const AppToggle({super.key, required this.onChanged});
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Switch(value: false, onChanged: onChanged);
}

String describeValue(double value) => 'at $value';
''';
    for (final (name, body, expected) in [
      (
        'that returns a value',
        'Slider(value: 0.5, onChanged: (v) {}, '
            'semanticFormatterCallback: (v) => describeValue(v))',
        [r'semanticFormatterCallback: {nativeEvent: data.context._h'],
      ),
      (
        'at a direct site',
        "Switch(value: false, onChanged: (on) => debugPrint('d \$on'))",
        [r'Switch(value: false, onChanged: {nativeEvent: data.context._h'],
      ),
      (
        'through an app widget',
        "AppToggle(onChanged: (on) => debugPrint('t \$on'))",
        [
          'widget AppToggle = Switch(value: false, onChanged: args.onChanged);',
          r'AppToggle(onChanged: {nativeEvent: data.context._h',
        ],
      ),
    ]) {
      test(name, () async {
        final out = await _compile(_surface(body, classes: toggle));
        expect(out.errors, isEmpty);
        expect(out.islands, isEmpty);
        for (final fragment in expected) {
          expect(out.text, contains(fragment));
        }
      });
    }
  });

  group('a widget kept as the app builds it', () {
    const kept = '''
@RenderInApp()
class Kept extends StatelessWidget {
  const Kept({super.key});
  @override
  Widget build(BuildContext context) => const Text('kept');
}
''';
    for (final (name, body, classes, island) in [
      (
        'is never lowered inside a builder closure',
        'LayoutBuilder(builder: (context, constraints) => const Kept())',
        kept,
        'LayoutBuilder',
      ),
      (
        'is never lowered inside an app widget it is composed in',
        'const Holder()',
        '''
$kept
class Holder extends StatelessWidget {
  const Holder({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Kept());
}
''',
        'Holder',
      ),
    ]) {
      test(name, () async {
        final out = await _compile(_surface(body, classes: classes));
        // It stays in the app inside the island its enclosing widget forms.
        expect(out.errors, isEmpty);
        expect(out.islands, [island]);
        expect(out.text, isNot(contains('"kept"')));
      });
    }
  });

  test(
    'an island placed at spots the copy cannot tell apart says so',
    () async {
      final out = await _compile('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
part 'restage.generated/mounted.restage.g.dart';

$_painted
@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) {
    final card = Padding(padding: EdgeInsets.zero, child: Painted(label: 'x'));
    final first = card;
    final second = card;
    return Column(children: [first, second]);
  }
}
''');
      expect(out.errors, isEmpty);
      expect(
        out.warnings,
        contains(
          matches(
            RegExp(
              r"`Painted` \(lib/mounted\.dart:\d+:\d+\) is placed in more than "
              r"one spot through `card`, and Restage can't tell those spots "
              r'apart here, so its State resets when a new design is shown\. '
              r'Try giving each spot its own value\.',
            ),
          ),
        ),
      );
    },
  );

  group('a build the copy runs as written compiles', () {
    for (final (name, build, List<String>? islands) in [
      (
        'with a local function',
        '''{
    Widget row(String text) => Text(shout(text));
    return Column(children: [row('a'), row('b')]);
  }''',
        ['row', 'row'],
      ),
      (
        'with a spread of a helper list',
        '''=> Column(children: [const Text('h'), ..._rows(['a', 'b'])]);

  List<Widget> _rows(List<String> names) =>
      [for (final name in names) Text(shout(name))];''',
        <String>[],
      ),
      (
        'with a spread of a member helper over an input list',
        '''=> Column(children: [const Text('h'), ..._rows(names)]);

  List<Widget> _rows(List<String> names) =>
      [for (final name in names) Text(shout(name))];''',
        null,
      ),
      (
        'with a spread of a top-level helper over an input list',
        "=> Column(children: [const Text('h'), ...rows(names)]);",
        null,
      ),
      (
        'with a spread of a top-level helper over a const list',
        "=> Column(children: [const Text('h'), ...rows(const ['a', 'b'])]);",
        null,
      ),
      (
        'with a spread of a top-level helper over a computed list',
        "=> Column(children: [const Text('h'), "
            "...rows([for (final n in names) if (n.isNotEmpty) n])]);",
        null,
      ),
    ]) {
      test(name, () async {
        final source =
            '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
part 'restage.generated/mounted.restage.g.dart';

String shout(String text) => text.toUpperCase();

List<Widget> rows(List<String> names) =>
    [for (final name in names) Text(shout(name))];

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, this.names = const ['a', 'b']});
  final List<String> names;
  @override
  Widget build(BuildContext context) $build
}
''';
        final out = await _compile(source);
        expect(out.errors, isEmpty);
        if (islands != null) expect(out.islands, islands);
        await _expectAnalyzesClean({
          'apps_examples|lib/mounted.dart': source,
          'apps_examples|lib/restage.generated/mounted.restage.g.dart':
              out.part,
        });
      });
    }
  });

  group("a surface's own fields promote as the app's do", () {
    for (final (name, field, read, direct) in [
      ('a private final field promotes', '_label', '_label', true),
      ('a public field stays unpromoted', 'label', 'label!', false),
    ]) {
      test(name, () async {
        final source =
            '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
part 'restage.generated/mounted.restage.g.dart';

String shout(String text) => text.toUpperCase();

@Paywall()
final class Mounted extends StatelessWidget {
  const Mounted({super.key, String? label}) : $field = label;
  final String? $field;
  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('top'),
        if ($field != null) Text(shout($read)),
      ]);
}
''';
        final out = await _compile(source);
        expect(out.errors, isEmpty);
        expect(
          out.part,
          direct
              ? isNot(contains('get _restageArgument'))
              : contains('get _restageArgument'),
        );
        await _expectAnalyzesClean({
          'apps_examples|lib/mounted.dart': source,
          'apps_examples|lib/restage.generated/mounted.restage.g.dart':
              out.part,
        });
      });
    }
  });

  group('an app widget whose build returns its own widget argument', () {
    for (final (name, body, classes, delivered, absent) in [
      (
        'inlines as that argument',
        "Hears(onContext: (context) {}, child: const Text('x'))",
        '''
class Hears extends StatelessWidget {
  const Hears({super.key, required this.onContext, required this.child});
  final void Function(BuildContext context) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
''',
        'Column(children: [Text(text: "x")])',
        'widget Hears',
      ),
      (
        'inlines through another that passes it on',
        "Outer(child: const Text('x'))",
        '''
class Inner extends StatelessWidget {
  const Inner({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
class Outer extends StatelessWidget {
  const Outer({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Inner(child: child);
}
''',
        'Column(children: [Text(text: "x")])',
        'widget Outer',
      ),
      (
        'picks between two as a switch declaration',
        "Pick(on: true, a: const Text('a'), b: const Text('b'))",
        '''
class Pick extends StatelessWidget {
  const Pick({super.key, required this.on, required this.a, required this.b});
  final bool on;
  final Widget a;
  final Widget b;
  @override
  Widget build(BuildContext context) => on ? a : b;
}
''',
        'widget Pick = switch args.on',
        'widget Pick = args.',
      ),
      (
        'stays a declaration when it wraps the argument',
        "Wrap1(child: const Text('x'))",
        '''
class Wrap1 extends StatelessWidget {
  const Wrap1({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(child: child);
}
''',
        'widget Wrap1 = Center(child: args.child);',
        'widget Wrap1 = args.',
      ),
    ]) {
      test(name, () async {
        final out = await _compile(_surface(body, classes: classes));
        expect(out.errors, isEmpty);
        expect(out.islands, isEmpty);
        expect(out.text, contains(delivered));
        expect(out.text, isNot(contains(absent)));
        // The payload parses: every declaration's root is a call or a switch.
        fmt.parseLibraryFile(out.text);
      });
    }
  });

  group('an app widget a surface reaches', () {
    for (final (name, source, otherFiles, inlined, island) in [
      (
        'inlines when it is pure composition',
        _surface("Pill(label: 'Pro')", classes: _pill),
        const <String, String>{},
        'widget Pill = Padding(',
        null,
      ),
      (
        'inlines when it is private',
        _surface(
          "_Pill(label: 'Pro')",
          classes: _pill
              .replaceAll('Pill', '_Pill')
              .replaceAll('super.key, ', ''),
        ),
        const <String, String>{},
        'widget _Pill = Padding(',
        null,
      ),
      (
        'inlines the app widgets it composes',
        _surface(
          "Card2(label: 'Pro')",
          classes:
              '''
$_pill
class Card2 extends StatelessWidget {
  const Card2({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Center(child: Pill(label: label));
}
''',
        ),
        const <String, String>{},
        'widget Pill = Padding(',
        null,
      ),
      (
        'inlines under a build statement',
        _surface('', classes: _pill).replaceFirst(
          'Widget build(BuildContext context) => Column(children: []);',
          '''Widget build(BuildContext context) {
    try {
      return Pill(label: 'Pro');
    } on StateError {
      return const Text('error');
    }
  }''',
        ),
        const <String, String>{},
        'widget Pill = Padding(',
        null,
      ),
      (
        'becomes an island when it does not lower',
        _surface("Painted(label: 'Pro')", classes: _painted),
        const <String, String>{},
        null,
        'mounted_Painted_0',
      ),
      (
        'becomes an island when its build computes what a design cannot',
        _surface(
          "Tinted(tint: 2, child: const Text('a'))",
          classes: '''
class Tinted extends StatelessWidget {
  const Tinted({super.key, required this.child, this.tint = 0});
  final Widget child;
  final int tint;
  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Color(0xFF000000 + tint), child: child);
}
''',
        ),
        const <String, String>{},
        null,
        'mounted_Tinted_0',
      ),
      (
        'inlines from a path package',
        _surface(
          "Pill(label: 'Pro')",
          imports: "import 'package:sprout_design/pill.dart';",
        ),
        {'sprout_design|lib/pill.dart': _pillLibrary},
        'widget Pill = Padding(',
        null,
      ),
      (
        'stays an island from a hosted package',
        _surface(
          "Pill(label: 'Pro')",
          imports: "import 'package:flutter_bloc/pill.dart';",
        ),
        {'flutter_bloc|lib/pill.dart': _pillLibrary},
        null,
        'mounted_Pill_0',
      ),
    ]) {
      test(name, () async {
        final out = await _compile(source, otherFiles: otherFiles);
        expect(out.errors, isEmpty);
        if (inlined != null) {
          expect(out.text, contains(inlined));
          expect(out.part, isNot(contains('restageIslands\$')));
        }
        if (island != null) {
          expect(out.text, isNot(contains('widget Pill =')));
          expect(out.part, contains('restageIslands\$$island'));
        }
        await _expectAnalyzesClean({
          'apps_examples|lib/mounted.dart': source,
          'apps_examples|lib/restage.generated/mounted.restage.g.dart':
              out.part,
          ...otherFiles,
        });
      });
    }
  });
}

const _pillLibrary = '''
import 'package:flutter/widgets.dart';

$_pill''';

Future<
  ({
    String text,
    String part,
    List<String> errors,
    List<String> warnings,
    List<String> islands,
    RestageSurfacePublicationBundle? bundle,
  })
>
_compile(
  String source, {
  Map<String, String> otherFiles = const {},
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final warnings = <String>[];
  // Another package's files are its committed sources, never built here,
  // and the app depends on it.
  final dependencies = <String>{};
  for (final entry in otherFiles.entries) {
    if (!entry.key.startsWith('apps_examples|')) {
      final id = AssetId.parse(entry.key);
      readerWriter.testing.writeString(id, entry.value);
      dependencies.add(id.package);
    }
  }
  if (dependencies.isNotEmpty) {
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'pubspec.yaml'),
      'name: apps_examples\ndependencies:\n'
      '${[for (final d in dependencies) '  $d: any\n'].join()}',
    );
  }
  final result = await testBuilders(
    [
      restageSourceRosterBuilder(
        const BuilderOptions({'bundled_runtime': true}, isRoot: true),
      ),
      userCatalogJsonBuilder(BuilderOptions.empty),
      restagePackageSurfaceCompilerBuilder(
        const BuilderOptions({'bundled_runtime': true}, isRoot: true),
      ),
      restageGeneratedDartBuilder(
        const BuilderOptions({'bundled_runtime': true}),
      ),
      restageOutputsBuilder(const BuilderOptions({'bundled_runtime': true})),
    ],
    {
      'apps_examples|lib/mounted.dart': source,
      for (final entry in otherFiles.entries)
        if (entry.key.startsWith('apps_examples|')) entry.key: entry.value,
    },
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) {
      if (record.level == Level.WARNING) warnings.add(record.message);
    },
  );
  if (!result.succeeded) {
    return (
      text: '',
      part: '',
      errors: [for (final e in result.errors) '$e'],
      warnings: warnings,
      islands: const <String>[],
      bundle: null,
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
    // The surface's text, wherever its kind keeps it.
    text: utf8.decode(
      bundle.ownedOutputs.entries
          .firstWhere((entry) => entry.key.endsWith('/mounted.rfwtxt'))
          .value,
    ),
    part: readerWriter.testing.readString(
      AssetId('apps_examples', 'lib/restage.generated/mounted.restage.g.dart'),
    ),
    errors: <String>[],
    warnings: warnings,
    islands: [
      for (final site in bundle.splitSites)
        if (site.kind.name == 'island') site.widget,
    ],
    bundle: bundle,
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
      expect([
        for (final unit in resolved.units)
          for (final diagnostic in unit.diagnostics)
            if (diagnostic.severity != Severity.info)
              '${unit.path}: ${diagnostic.message}',
      ], isEmpty);
    },
    resolverFor: entry,
    rootPackage: 'apps_examples',
  );
}

// The outputs the build of package [root] writes, by package path.
Future<Map<String, String>> _buildPackage(
  String root,
  Map<String, String> files,
) async {
  // The app fixture's sources, so the package resolves the SDK.
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final result = await testBuilders(
    [
      restageSourceRosterBuilder(
        const BuilderOptions({'bundled_runtime': true}, isRoot: true),
      ),
      userCatalogJsonBuilder(BuilderOptions.empty),
      restagePackageSurfaceCompilerBuilder(
        const BuilderOptions({'bundled_runtime': true}, isRoot: true),
      ),
      restageGeneratedDartBuilder(
        const BuilderOptions({'bundled_runtime': true}),
      ),
    ],
    files,
    rootPackage: root,
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  // Its committed parts and the catalog its build hands dependents.
  return {
    for (final id in readerWriter.testing.assets)
      if (id.package == root &&
          (id.path.endsWith('.restage.g.dart') ||
              id.path.startsWith('lib/src/widget_catalog/')))
        id.path: readerWriter.testing.readString(id),
  };
}
