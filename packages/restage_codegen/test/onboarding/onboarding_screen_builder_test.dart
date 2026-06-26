import 'dart:typed_data';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('OnboardingScreenBuilder', () {
    test('visitor accepts supported StatefulWidget roots', () async {
      const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

final class _WelcomeScreenState extends State<WelcomeScreen> {
  bool annual = false;

  @override
  Widget build(BuildContext context) =>
      Text(annual ? 'Annual' : 'Monthly');
}
''';

      final result = await runOnboardingVisitorOn({
        'lib/onboarding/screens/welcome.dart': source,
      });

      expect(result.issues, isEmpty);
      expect(result.sources, hasLength(1));
      final sourceFound = result.sources.single;
      expect(sourceFound.build.state!.single.name, 'annual');
    });

    test('valid @OnboardingSource emits descriptor and RFW artifacts',
        () async {
      const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  static const next = OnboardingEvent<void>('next');

  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: onboardingEvent(next),
        child: const Text('Continue'),
      ),
    );
  }
}
''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/onboarding/screens/welcome.dart'),
        source,
      );

      await testBuilder(
        onboardingScreenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/onboarding/screens/welcome.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/onboarding/screens/welcome.rsscreen.g.dart':
              decodedMatches(
            allOf(
              contains("part of 'welcome.dart';"),
              contains('abstract final class WelcomeScreenDescriptor'),
              contains("id: 'welcome'"),
              contains("artifactPath: 'welcome.rfw'"),
            ),
          ),
          'apps_examples|assets/onboarding/screens/welcome.rfwtxt':
              decodedMatches(
            allOf(
              contains('widget OnboardingScreen ='),
              isNot(contains('widget Paywall =')),
              contains('Center'),
              contains('ElevatedButton'),
              contains('Text'),
            ),
          ),
          'apps_examples|assets/onboarding/screens/welcome.rfw':
              _decodesAsRfwLibrary(),
          'apps_examples|assets/onboarding/screens/welcome.capability.json':
              anything,
        },
      );
    });

    test('stateful @OnboardingSource emits root state and handlers', () async {
      const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

final class _WelcomeScreenState extends State<WelcomeScreen> {
  bool annual = false;

  void toggle() {
    setState(() {
      annual = !annual;
    });
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: toggle,
        child: Text(annual ? 'Annual' : 'Monthly'),
      );
}
''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/onboarding/screens/welcome.dart'),
        source,
      );

      await testBuilder(
        onboardingScreenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/onboarding/screens/welcome.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/onboarding/screens/welcome.rsscreen.g.dart':
              decodedMatches(contains('WelcomeScreenDescriptor')),
          'apps_examples|assets/onboarding/screens/welcome.rfwtxt':
              decodedMatches(
            allOf(
              contains('widget OnboardingScreen { annual: false } ='),
              contains(
                'onTap: set state.annual = switch state.annual '
                '{ true: false, false: true }',
              ),
              contains(
                'text: switch state.annual '
                '{ true: "Annual", false: "Monthly" }',
              ),
            ),
          ),
          'apps_examples|assets/onboarding/screens/welcome.rfw':
              const _StatefulRootMatcher('OnboardingScreen', {
            'annual': false,
          }),
          'apps_examples|assets/onboarding/screens/welcome.capability.json':
              anything,
        },
      );
    });

    test('unsupported stateful @OnboardingSource emits no outputs', () async {
      const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

final class _WelcomeScreenState extends State<WelcomeScreen> {
  List<String> labels = const ['Monthly', 'Annual'];

  @override
  Widget build(BuildContext context) => const Center();
}
''';

      final logs = <LogRecord>[];
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/onboarding/screens/welcome.dart'),
        source,
      );

      final result = await testBuilder(
        onboardingScreenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/onboarding/screens/welcome.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
        outputs: const {},
      );
      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        allOf(
          contains('State field'),
          contains('unsupported type'),
        ),
      );
    });

    test('onboardingEvent payload map lowers to an RFW event body', () async {
      const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  static const analyticsTap =
      OnboardingEvent<Map<String, Object?>>('analyticsTap');

  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: onboardingEvent(
          analyticsTap,
          const {'ctaId': 'primary', 'secret': 'internal'},
        ),
        child: const Text('Track'),
      ),
    );
  }
}
''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/onboarding/screens/welcome.dart'),
        source,
      );

      await testBuilder(
        onboardingScreenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/onboarding/screens/welcome.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/onboarding/screens/welcome.rsscreen.g.dart':
              decodedMatches(contains('WelcomeScreenDescriptor')),
          'apps_examples|assets/onboarding/screens/welcome.rfwtxt':
              decodedMatches(
            contains(
              'event "analyticsTap" { ctaId: "primary", secret: "internal" }',
            ),
          ),
          'apps_examples|assets/onboarding/screens/welcome.rfw':
              _decodesAsRfwLibrary(),
          'apps_examples|assets/onboarding/screens/welcome.capability.json':
              anything,
        },
      );
    });

    test('onboardingEvent scalar value wraps under the reserved value key',
        () async {
      // The producer side of `.capture()`: a scalar event value must reach the
      // RFW event as `{ value: <v> }` (not a bare scalar a runtime map-decode
      // would drop), so a flow `.capture()` reading the reserved key resolves.
      const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  static const rating = OnboardingEvent<int>('rating');

  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: onboardingEvent(rating, 42),
        child: const Text('Rate'),
      ),
    );
  }
}
''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/onboarding/screens/welcome.dart'),
        source,
      );

      await testBuilder(
        onboardingScreenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/onboarding/screens/welcome.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/onboarding/screens/welcome.rsscreen.g.dart':
              anything,
          'apps_examples|assets/onboarding/screens/welcome.rfwtxt':
              decodedMatches(contains('event "rating" { value: 42 }')),
          'apps_examples|assets/onboarding/screens/welcome.rfw':
              _decodesAsRfwLibrary(),
          'apps_examples|assets/onboarding/screens/welcome.capability.json':
              anything,
        },
      );
    });

    test('filename / id mismatch rejects outputs with a diagnostic', () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'wrong.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const Center();
}
''';

      final logs = <LogRecord>[];
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/onboarding/screens/wrong.dart'),
        source,
      );

      final result = await testBuilder(
        onboardingScreenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/onboarding/screens/wrong.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
        outputs: const {},
      );
      expect(result.succeeded, isFalse);
      expect(logs.map((log) => log.message).join('\n'), contains('filename'));
    });

    test('missing part directive rejects outputs with a diagnostic', () async {
      const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const Center();
}
''';

      final logs = <LogRecord>[];
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/onboarding/screens/welcome.dart'),
        source,
      );

      final result = await testBuilder(
        onboardingScreenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/onboarding/screens/welcome.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
        outputs: const {},
      );
      expect(result.succeeded, isFalse);
      expect(logs.map((log) => log.message).join('\n'), contains('part'));
    });

    test('local OnboardingSource annotation lookalikes are ignored', () async {
      const source = '''
import 'package:flutter/widgets.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const Center();
}

final class OnboardingSource {
  const OnboardingSource({required this.id});
  final String id;
}
''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/onboarding/screens/welcome.dart'),
        source,
      );

      final result = await testBuilder(
        onboardingScreenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/onboarding/screens/welcome.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: const {},
      );
      expect(result.succeeded, isTrue);
    });

    test('paywall helper calls reject outputs in onboarding screens', () async {
      final cases = <String, String>{
        'paywallEvent': '''
ElevatedButton(
  onPressed: paywallEvent('restore'),
  child: const Text('Continue'),
)
''',
        'paywallPurchase': '''
ElevatedButton(
  onPressed: paywallPurchase(slot: 'primary'),
  child: const Text('Continue'),
)
''',
        'paywallPriceFor': '''
Text(paywallPriceFor(slot: 'primary'))
''',
      };

      for (final entry in cases.entries) {
        final source = _screenWithBody(entry.value);
        final logs = <LogRecord>[];
        final readerWriter = await readerWriterWithFilesystemSources(
          rootPackage: 'apps_examples',
        );
        readerWriter.testing.writeString(
          AssetId('apps_examples', 'lib/onboarding/screens/welcome.dart'),
          source,
        );

        final result = await testBuilder(
          onboardingScreenBuilder(BuilderOptions.empty),
          {'apps_examples|lib/onboarding/screens/welcome.dart': source},
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          onLog: logs.add,
          outputs: const {},
        );
        expect(result.succeeded, isFalse, reason: entry.key);
        expect(
          logs.map((log) => log.message).join('\n'),
          contains(entry.key),
          reason: entry.key,
        );
      }
    });

    test('generated descriptor symbol collision rejects outputs', () async {
      final cases = <String, String>{
        'class': 'abstract final class WelcomeScreenDescriptor {}',
        'enum': 'enum WelcomeScreenDescriptor { value }',
        'mixin': 'mixin WelcomeScreenDescriptor {}',
        'extension': 'extension WelcomeScreenDescriptor on Object {}',
        'extension type':
            'extension type WelcomeScreenDescriptor(Object value) {}',
        'typedef': 'typedef WelcomeScreenDescriptor = Object;',
        'function': 'void WelcomeScreenDescriptor() {}',
        'getter': 'Object get WelcomeScreenDescriptor => Object();',
        'setter': 'set WelcomeScreenDescriptor(Object value) {}',
        'variable': 'final WelcomeScreenDescriptor = Object();',
      };

      for (final entry in cases.entries) {
        final source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

${entry.value}

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const Center();
}
''';

        final logs = <LogRecord>[];
        final readerWriter = await readerWriterWithFilesystemSources(
          rootPackage: 'apps_examples',
        );
        readerWriter.testing.writeString(
          AssetId('apps_examples', 'lib/onboarding/screens/welcome.dart'),
          source,
        );

        final result = await testBuilder(
          onboardingScreenBuilder(BuilderOptions.empty),
          {'apps_examples|lib/onboarding/screens/welcome.dart': source},
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          onLog: logs.add,
          outputs: const {},
        );
        expect(result.succeeded, isFalse, reason: entry.key);
        expect(
          logs.map((log) => log.message).join('\n'),
          contains('WelcomeScreenDescriptor'),
          reason: entry.key,
        );
      }
    });

    test('unresolved onboardingEvent arguments reject outputs', () async {
      const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  static const next = OnboardingEvent<void>('next');

  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: onboardingEvent(WelcomeScreen.nxt),
        child: const Text('Continue'),
      ),
    );
  }
}
''';

      final logs = <LogRecord>[];
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/onboarding/screens/welcome.dart'),
        source,
      );

      final result = await testBuilder(
        onboardingScreenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/onboarding/screens/welcome.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
        outputs: const {},
      );
      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        allOf(
          contains('Expected a static OnboardingEvent field reference'),
          contains('WelcomeScreen.nxt'),
        ),
      );
    });

    test('local OnboardingEvent lookalikes reject outputs', () async {
      const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  static const fake = OnboardingEvent<void>('fake');

  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: onboardingEvent(fake),
        child: const Text('Continue'),
      ),
    );
  }
}

final class OnboardingEvent<T> {
  const OnboardingEvent(this.id);
  final String id;
}
''';

      final logs = <LogRecord>[];
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/onboarding/screens/welcome.dart'),
        source,
      );

      final result = await testBuilder(
        onboardingScreenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/onboarding/screens/welcome.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
        outputs: const {},
      );
      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        allOf(
          contains('Expected a static OnboardingEvent field reference'),
          contains('fake'),
        ),
      );
    });

    test(
        'a malformed token in a screen source fails the build instead of '
        'shipping a silently-recovered blob', () async {
      // The builder resolves with `allowSyntaxErrors: true`. An incomplete
      // hex literal `0x` is a scanner error whose parser recovery would
      // otherwise yield a structurally-valid widget tree and ship a clean
      // blob with the bad token dropped. The syntactic-error pass fails it.
      const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(width: 0x);
}
''';

      final logs = <LogRecord>[];
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/onboarding/screens/welcome.dart'),
        source,
      );

      final result = await testBuilder(
        onboardingScreenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/onboarding/screens/welcome.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
        outputs: const {},
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        contains('[malformedSourceInput]'),
      );
    });

    test(
        'a syntax error that prevents screen discovery still fails the build '
        'instead of silently skipping', () async {
      // A top-level syntactic error severe enough that no `@OnboardingSource`
      // class is discovered would otherwise hit the no-sources early-return
      // and silently produce no output. The syntactic-error pass runs before
      // that early-return, so the malformed file is diagnosed.
      const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

      final logs = <LogRecord>[];
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/onboarding/screens/welcome.dart'),
        source,
      );

      final result = await testBuilder(
        onboardingScreenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/onboarding/screens/welcome.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
        outputs: const {},
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        contains('[malformedSourceInput]'),
      );
    });
  });
}

String _screenWithBody(String body) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  static const next = OnboardingEvent<void>('next');

  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: $body,
    );
  }
}
''';

Matcher _decodesAsRfwLibrary() => predicate<List<int>>(
      (bytes) {
        fmt.decodeLibraryBlob(Uint8List.fromList(bytes));
        return true;
      },
      'RFW library bytes decodable by decodeLibraryBlob',
    );

class _StatefulRootMatcher extends Matcher {
  const _StatefulRootMatcher(this.name, this.expectedState);

  final String name;
  final Map<String, Object?> expectedState;

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! List<int>) return false;
    final fmt.RemoteWidgetLibrary decoded;
    try {
      decoded = fmt.decodeLibraryBlob(Uint8List.fromList(item));
    } on fmt.ParserException catch (e) {
      matchState['decodeError'] = e;
      return false;
    }
    if (decoded.widgets.length != 1) {
      matchState['shape'] = 'expected 1 widget, got ${decoded.widgets.length}';
      return false;
    }
    final root = decoded.widgets.single;
    if (root.name != name) {
      matchState['shape'] = "expected widget name '$name', got '${root.name}'";
      return false;
    }
    final initialState = root.initialState ?? const <String, Object?>{};
    if (initialState.length != expectedState.length) {
      matchState['shape'] = 'expected state $expectedState, got '
          '$initialState';
      return false;
    }
    for (final entry in expectedState.entries) {
      if (initialState[entry.key] != entry.value) {
        matchState['shape'] = 'expected state ${entry.key}=${entry.value}, '
            'got ${initialState[entry.key]}';
        return false;
      }
    }
    return true;
  }

  @override
  Description describe(Description description) =>
      description.add("a .rfw blob with stateful root widget '$name'");

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    if (matchState.containsKey('decodeError')) {
      return mismatchDescription
          .add('failed to decode blob: ')
          .addDescriptionOf(matchState['decodeError']);
    }
    if (matchState.containsKey('shape')) {
      return mismatchDescription.add(matchState['shape'] as String);
    }
    return mismatchDescription.add('did not decode to the expected root');
  }
}
