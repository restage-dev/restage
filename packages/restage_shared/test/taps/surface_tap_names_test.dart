import 'package:restage_shared/rfw_formats.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

ConstructorCall _root(String body) =>
    parseLibraryFile('widget Root = $body;').widgets.single.root
        as ConstructorCall;

void main() {
  group('surfaceTapElementName', () {
    test('names an element by its first text', () {
      expect(
        surfaceTapElementName(
          _root('''
ElevatedButton(onPressed: event "buy" {}, tooltip: "Purchase",
  child: Row(children: [
    Icon(iconCodepoint: 0xe16a),
    Text(text: "Start\\nfree trial"),
    Text(text: "Later"),
  ]))'''),
        ),
        'Start free trial',
      );
    });

    test('names an element by the literal parts of a joined label', () {
      expect(
        surfaceTapSemanticsLabel(
          _root('Semantics(label: ["Choose ", data.plan, " plan"], '
              'child: Text(text: "x"))'),
        ),
        'Choose plan',
      );
    });

    test('falls back to a semantics label, then a tooltip, then an icon', () {
      expect(
        surfaceTapElementName(
          _root('''
InkWell(onTap: event "go" {}, tooltip: "Tip",
  child: Image(semanticLabel: "Hero art"))'''),
        ),
        'Hero art',
      );
      expect(
        surfaceTapElementName(
          _root('''
IconButton(onPressed: event "go" {}, tooltip: "Open settings",
  icon: Icon(iconCodepoint: 0xe16a))'''),
        ),
        'Open settings',
      );
      expect(
        surfaceTapElementName(
          _root('''
IconButton(onPressed: event "close" {},
  icon: Icon(iconCodepoint: 0xf647))'''),
        ),
        'Close',
      );
    });

    test('an enclosing semantics label overrides what the element shows', () {
      expect(
        surfaceTapElementName(
          _root(
              'TextButton(onPressed: event "go" {}, child: Text(text: "Go"))'),
          semanticsOverride: 'Continue to plans',
        ),
        'Continue to plans',
      );
    });

    test('a Semantics label inside the element names it', () {
      expect(
        surfaceTapElementName(
          _root('''
GestureDetector(onTap: event "go" {},
  child: Semantics(label: "Annual plan", child: Container()))'''),
        ),
        'Annual plan',
      );
    });

    test('text bound to data is not a name', () {
      expect(
        surfaceTapElementName(
          _root('''
TextButton(onPressed: event "go" {},
  child: Text(text: data.title), tooltip: "Fallback")'''),
        ),
        'Fallback',
      );
    });

    test('an element that shows nothing nameable has no name', () {
      expect(
        surfaceTapElementName(
          _root('GestureDetector(onTap: event "go" {}, child: Container())'),
        ),
        isNull,
      );
      expect(
        surfaceTapElementName(
          _root(
              'TextButton(onPressed: event "go" {}, child: Text(text: "  "))'),
        ),
        isNull,
      );
    });

    test('a long name is cut to the name bound', () {
      final name = surfaceTapElementName(
        _root(
          'TextButton(onPressed: event "go" {}, '
          'child: Text(text: "${'word ' * 60}"))',
        ),
      )!;
      expect(name.length, kSurfaceTapNameLimit);
      expect(name, endsWith('…'));
    });
  });

  test('surfaceTapSemanticsLabel reads only a Semantics label', () {
    expect(
      surfaceTapSemanticsLabel(
        _root('Semantics(label: "Annual plan", child: Container())'),
      ),
      'Annual plan',
    );
    expect(surfaceTapSemanticsLabel(_root('Text(text: "Hi")')), isNull);
  });

  group('surfaceIconName', () {
    test('names a material icon without its style suffix', () {
      expect(surfaceIconName(0xf647), 'Close');
      expect(surfaceIconName(0xe092), 'Back');
    });

    test('names a cupertino icon from its own table', () {
      expect(
        surfaceIconName(0xf111, fontFamily: 'CupertinoIcons'),
        'Battery charging',
      );
    });

    test('an unknown code point has no name', () {
      expect(surfaceIconName(0x1), isNull);
    });
  });

  test('humaniseSurfaceId reads an id in words', () {
    expect(humaniseSurfaceId('paywall_annual_offer'), 'Annual offer');
    expect(humaniseSurfaceId('plans-page'), 'Plans page');
    expect(humaniseSurfaceId('welcome'), 'Welcome');
    expect(humaniseSurfaceId(''), '');
  });
}
