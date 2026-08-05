// ENCODE side of a customer map slot: a body that AUTHORS a map at a slot
// whose value shape is the opaque string-keyed map marker compiles that map
// into the ENTRY LIST the decoder reconstructs — `[{key: k, value: v}, …]` —
// never the natural key-keyed spelling `{k: v}`.
//
// The route is by SLOT SHAPE, not by the literal's node type: the map-literal
// node is already claimed by the generic arm serving every other map literal
// in the translator, so a node-type branch would leave the slot's shape
// unknown and encode a customer slot in the forbidden spelling — passing every
// build-time guard and failing only at reconstruction.
//
// Order is asserted against a fixture authored OUT of alphabetical order, so a
// canonicalising regression fails here rather than coincidentally passing.
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// A catalog widget with one property carrying the opaque string-keyed map
/// marker — the shape the slot route gates on.
final Catalog _catalog = catalogWith([
  entry(
    name: 'FieldNotes',
    category: WidgetCategory.decoration,
    properties: [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'glossary',
        type: PropertyType.unknown,
        description: '',
        required: true,
        valueShape: ScalarShape.opaqueStringKeyedMap(),
      ),
    ],
  ),
]);

Future<({String dsl, List<IssueCode> codes})> _encode(String body) async {
  final expr = await parseExpressionFromSourceForTest('''
      enum Tone { soft, loud }

      String unavailable() => 'not encodable';

      Object x() => $body;
    ''');
  final result = ExpressionTranslator(
    catalog: _catalog,
    helpers: HelperRegistry(),
  ).translate(expr);
  return (
    dsl: result.dsl,
    codes: result.issues.map((issue) => issue.code).toList(),
  );
}

void main() {
  test('a map slot emits an entry list, never a key-keyed map', () async {
    final r = await _encode(
      "FieldNotes(glossary: <String, String>{'term': 'meaning'})",
    );

    expect(r.codes, isEmpty);
    expect(r.dsl, 'FieldNotes(glossary: [{key: "term", value: "meaning"}])');
    // The forbidden spelling, asserted as an absence so the positive above
    // cannot drift into it unnoticed.
    expect(r.dsl, isNot(contains('{term:')));
  });

  test('entry order is preserved as authored, not canonicalised', () async {
    // Authored deliberately out of alphabetical order. Sorting would change
    // behaviour rather than normalise bytes: the decoder reconstructs a real
    // Dart Map whose iteration order the customer's build() can observe,
    // unlike record label order which is canonically sorted by design.
    final r = await _encode(
      "FieldNotes(glossary: <String, String>{'zeta': '1', 'alpha': '2'})",
    );

    expect(r.codes, isEmpty);
    expect(
      r.dsl,
      'FieldNotes(glossary: '
      '[{key: "zeta", value: "1"}, {key: "alpha", value: "2"}])',
    );
    // A canonicalising regression would emit alpha first; pin that directly
    // rather than relying on the whole-string match alone.
    expect(r.dsl.indexOf('zeta'), lessThan(r.dsl.indexOf('alpha')));
  });

  test('an enum key emits its member name as a string', () async {
    final r = await _encode(
      "FieldNotes(glossary: <Tone, String>{Tone.loud: 'shout'})",
    );

    expect(r.codes, isEmpty);
    expect(r.dsl, 'FieldNotes(glossary: [{key: "loud", value: "shout"}])');
  });

  // The NEGATIVE half of the routing rule. The four tests above pin what a
  // customer slot does; none of them would notice if the GENERIC arm started
  // doing the same thing. Byte-identity of that arm was measured once at
  // review time, and a one-time measurement does not travel: add a node-type
  // arm tomorrow and every test above stays green while every other map
  // literal in the codebase silently changes spelling. These two pin the
  // boundary itself.
  group('the customer route stays disjoint from the generic map arm', () {
    test(
      'a plain map literal still lowers to the natural key-keyed spelling',
      () async {
        final r = await _encode("<String, String>{'a': 'b'}");

        expect(r.codes, isEmpty);
        expect(r.dsl, '{ a: "b" }');
        // Paired absence: a literal that is not a customer slot value must not
        // acquire the entry-list spelling.
        expect(r.dsl, isNot(contains('key:')));
      },
    );

    test(
      'a customer slot and a plain map literal in ONE body get different '
      'spellings',
      () async {
        // Both arms run over the same expression tree in a single
        // translation. Pinning the two spellings against each other is
        // stronger than pinning either alone: if the paths ever converge,
        // each side's own test still passes while this one cannot.
        final r = await _encode(
          "<String, Object>{'w': "
          "FieldNotes(glossary: <String, String>{'term': 'meaning'})}",
        );

        expect(r.codes, isEmpty);
        expect(
          r.dsl,
          '{ w: FieldNotes(glossary: [{key: "term", value: "meaning"}]) }',
        );
        // The outer map is key-keyed; the customer slot inside it is an entry
        // list. Asserted separately from the whole-string match so a failure
        // says WHICH side moved.
        expect(r.dsl, startsWith('{ w: '));
        expect(r.dsl, contains('[{key: "term", value: "meaning"}]'));
        // The disjointness itself: were the generic arm routed like a customer
        // slot, the outer key would be wrapped as an entry too.
        expect(r.dsl, isNot(contains('{key: "w"')));
      },
    );
  });

  test('one unencodable value suppresses the WHOLE map', () async {
    final r = await _encode(
      "FieldNotes(glossary: <String, String>{'good': 'kept', "
      "'bad': unavailable()})",
    );

    expect(r.codes, isNotEmpty);
    expect(r.dsl, '');
    // The entry that translated successfully must not survive on its own —
    // one map is one value contract, never a half-encoded one.
    expect(r.dsl, isNot(contains('good')));
  });
}
