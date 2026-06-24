import 'package:restage_codegen/src/rfw_emitter.dart';
import 'package:restage_shared/rfw_formats.dart';
import 'package:test/test.dart';

void main() {
  group('emitPaywallLibrary', () {
    test('wraps fragment in canonical envelope', () {
      final text = emitPaywallLibrary('Scaffold(body: Text(text: "hi"))');
      // Expected output (whitespace exact):
      const expected = '''
import restage.core;
import restage.material;
import restage.cupertino;

widget Paywall = Scaffold(body: Text(text: "hi"));
''';
      expect(text, expected);
    });

    test('emitted text round-trips via parseLibraryFile', () {
      final text = emitPaywallLibrary('Text(text: "hi")');
      final lib = parseLibraryFile(text, sourceIdentifier: 'test');
      expect(lib.widgets, hasLength(1));
      expect(lib.widgets.first.name, 'Paywall');
    });

    test('generic emitter supports a non-paywall root widget', () {
      final text = emitRemoteWidgetLibrary(
        'Text(text: "hi")',
        rootWidgetName: onboardingScreenRootWidgetName,
      );
      expect(text, contains('widget OnboardingScreen = Text(text: "hi");'));
      expect(text, isNot(contains('widget Paywall =')));

      final lib = parseLibraryFile(text, sourceIdentifier: 'test');
      expect(lib.widgets.single.name, 'OnboardingScreen');
    });

    test('renders root widget state before the root `=`', () {
      final text = emitRemoteWidgetLibrary(
        'Text(text: state.label)',
        rootWidgetName: paywallRootWidgetName,
        rootWidgetState: {'label': '"ready"'},
      );

      expect(
        text,
        contains(
          'widget Paywall { label: "ready" } = Text(text: state.label);',
        ),
      );
      final lib = parseLibraryFile(text, sourceIdentifier: 'test');
      final paywall =
          lib.widgets.singleWhere((widget) => widget.name == 'Paywall');
      expect(paywall.initialState, isNotNull);
      expect(paywall.initialState!['label'], 'ready');
    });

    test('stateless root widget output keeps the existing byte shape', () {
      final text = emitRemoteWidgetLibrary(
        'Text(text: "hi")',
        rootWidgetName: paywallRootWidgetName,
      );

      expect(text, contains('widget Paywall = Text(text: "hi");'));
      expect(text, isNot(contains('widget Paywall {')));
    });

    test('binary-encodes via encodeLibraryBlob', () {
      final text = emitPaywallLibrary('Text(text: "hi")');
      final lib = parseLibraryFile(text, sourceIdentifier: 'test');
      final bytes = encodeLibraryBlob(lib);
      expect(bytes, isNotEmpty);
      // RFW binary blobs start with a magic signature; verify length
      // is reasonable (much less than 1MB for a simple paywall).
      expect(bytes.length, lessThan(1024));
      // First few bytes are the RFW magic; we don't assert exact values
      // since they're an implementation detail of binary.dart.
    });

    test('handles empty fragment gracefully', () {
      // An empty fragment is a degenerate case (translator failed) — the
      // emitter still wraps it, and parseLibraryFile will raise. We don't
      // test the failure mode here; just verify the envelope structure.
      final text = emitPaywallLibrary('Text(text: "")');
      expect(text, contains('widget Paywall ='));
      expect(text, contains('import restage.core;'));
    });

    test('prepends custom-widget definitions before the Paywall widget', () {
      final text = emitPaywallLibrary(
        'AcmeCard()',
        widgetDefinitions: {
          'AcmeCard': 'Container(child: Text(text: "Pro"))',
        },
      );
      expect(
        text,
        contains('widget AcmeCard = Container(child: Text(text: "Pro"));'),
      );
      expect(text, contains('widget Paywall = AcmeCard();'));
      // The definition is declared before the Paywall widget.
      expect(
        text.indexOf('widget AcmeCard ='),
        lessThan(text.indexOf('widget Paywall =')),
      );
      // The library round-trips with both widgets.
      final lib = parseLibraryFile(text, sourceIdentifier: 'test');
      expect(
        lib.widgets.map((w) => w.name),
        containsAll(['AcmeCard', 'Paywall']),
      );
    });

    test(
        'renders a stateful definition with the initial-state map between '
        'the name and `=`', () {
      final text = emitPaywallLibrary(
        'AcmeToggle()',
        widgetDefinitions: {
          'AcmeToggle': 'Text(text: switch state.on { true: "on", '
              'false: "off" })',
        },
        widgetDefinitionStates: const {
          'AcmeToggle': {'on': 'false'},
        },
      );
      expect(
        text,
        contains(
          'widget AcmeToggle { on: false } = Text(text: switch state.on { '
          'true: "on", false: "off" });',
        ),
      );
      // The parsed library exposes the initial state on the widget
      // declaration — the canonical RFW state container.
      final lib = parseLibraryFile(text, sourceIdentifier: 'test');
      final toggle = lib.widgets.firstWhere((w) => w.name == 'AcmeToggle');
      expect(toggle.initialState, isNotNull);
      expect(toggle.initialState!['on'], isFalse);
    });

    test(
        'renders multiple state fields in declaration order with their '
        'literal values', () {
      final text = emitPaywallLibrary(
        'AcmeMulti()',
        widgetDefinitions: {
          'AcmeMulti': 'Text(text: state.label)',
        },
        widgetDefinitionStates: const {
          'AcmeMulti': {
            'on': 'false',
            'count': '0',
            'scale': '1.5',
            'label': '"ready"',
          },
        },
      );
      // The state block preserves the order the translator provided it in.
      expect(
        text,
        contains(
          'widget AcmeMulti { on: false, count: 0, scale: 1.5, '
          'label: "ready" } = Text(text: state.label);',
        ),
      );
      final lib = parseLibraryFile(text, sourceIdentifier: 'test');
      final multi = lib.widgets.firstWhere((w) => w.name == 'AcmeMulti');
      expect(multi.initialState, isNotNull);
      expect(multi.initialState!['on'], isFalse);
      expect(multi.initialState!['count'], 0);
      expect(multi.initialState!['scale'], 1.5);
      expect(multi.initialState!['label'], 'ready');
    });

    test(
        'a stateful widget whose state map is empty emits no state block — '
        "the binary form makes 'no state' and 'empty state' indistinguishable",
        () {
      final text = emitPaywallLibrary(
        'AcmeStateless()',
        widgetDefinitions: const {
          'AcmeStateless': 'Text(text: "hello")',
        },
        widgetDefinitionStates: const {
          'AcmeStateless': <String, String>{},
        },
      );
      // No `{ }` block in the emitted line — same shape a stateless
      // definition would have.
      expect(
        text,
        contains('widget AcmeStateless = Text(text: "hello");'),
      );
      expect(text, isNot(contains('AcmeStateless {')));
    });
  });
}
