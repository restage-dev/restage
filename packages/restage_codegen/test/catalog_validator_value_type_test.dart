import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/rfw_formats.dart' show parseLibraryFile;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Property-value-TYPE validation at the catalog-validation boundary.
///
/// `validateModelAgainstCatalog` historically validated widget names and
/// property *names* only, never property-value *types* — so a wrong-typed
/// literal (`width: "infinity"`, `padding: "zero"`) passed validation, landed
/// in the blob, and the runtime typed decode silently nulled it. The governing
/// invariant is: every input is either correctly lowered or rejected with an
/// actionable build-time diagnostic, never a silent wrong/degraded blob.
///
/// A literal scalar/list/map whose runtime shape is incompatible with the
/// slot's declared [PropertyType] must now produce a build-time diagnostic.
/// Runtime-resolved values (data references, `switch`, event handlers, nested
/// widgets) are NOT type-checked — only literals.
void main() {
  // A catalog whose property types span the silent-loss-relevant kinds and the
  // must-stay-valid enum/numeric kinds.
  final catalog = catalogWith([
    entry(
      name: 'SizedBox',
      properties: [
        prop('width', PropertyType.length),
        prop('height', PropertyType.length),
        prop('child', PropertyType.widget),
      ],
    ),
    entry(
      name: 'Container',
      properties: [
        prop('padding', PropertyType.edgeInsets),
        prop('color', PropertyType.color),
        prop('alignment', PropertyType.alignment),
        prop('child', PropertyType.widget),
      ],
    ),
    entry(
      name: 'Row',
      childrenSlot: ChildrenSlot.list,
      properties: [
        prop('mainAxisAlignment', PropertyType.enumValue),
        prop('crossAxisAlignment', PropertyType.enumValue),
        prop('children', PropertyType.widgetList),
      ],
    ),
    entry(
      name: 'Text',
      properties: [
        prop('text', PropertyType.string, positional: true),
        prop('fontWeight', PropertyType.fontWeight),
        prop('fontSize', PropertyType.real),
        prop('locale', PropertyType.locale),
      ],
    ),
    entry(
      name: 'AnimatedOpacity',
      properties: [
        prop('opacity', PropertyType.real),
        prop('duration', PropertyType.duration),
        prop('curve', PropertyType.curve),
        prop('child', PropertyType.widget),
      ],
    ),
  ]);

  List<Issue> validate(String dsl) => validateModelAgainstCatalog(
        parseLibraryFile(dsl, sourceIdentifier: 'test'),
        catalog,
      );

  group('property-value-type validation — silent-loss cases now diagnose', () {
    test('S1: a string on a length slot (width: "infinity") diagnoses', () {
      const dsl = '''
        import restage.core;
        widget Paywall = SizedBox(width: "infinity");
      ''';
      // RED today: validation is name-only → returns empty → silent loss.
      expect(
        validate(dsl),
        isNotEmpty,
        reason: 'a string in a `length` slot must produce a build-time '
            'diagnostic, never a silently-nulled blob',
      );
    });

    test('S2: a string on an edgeInsets slot (padding: "zero") diagnoses', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Container(padding: "zero");
      ''';
      expect(validate(dsl), isNotEmpty);
    });

    test('a string on a color slot (color: "transparent") diagnoses', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Container(color: "transparent");
      ''';
      expect(validate(dsl), isNotEmpty);
    });

    test('a number on a string slot (text: 42) diagnoses', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Text(text: 42);
      ''';
      expect(validate(dsl), isNotEmpty);
    });

    test('S3: a string on an alignment slot (alignment: "center") diagnoses',
        () {
      // The `alignment` decoder (`ArgumentDecoders.alignment`) reads a
      // `{x, y}` map and returns null for any non-map — so a bare member-name
      // string is the same silent-loss vector as S1/S2, not a valid enum
      // string. It must diagnose, never pass through as `"center"`.
      const dsl = '''
        import restage.core;
        widget Paywall = Container(alignment: "center");
      ''';
      expect(validate(dsl), isNotEmpty);
    });

    test('a number on a locale slot (locale: 42) diagnoses', () {
      // The `locale` decoder reads a bare BCP-47 string; a number is the
      // wrong type and would be silently nulled.
      const dsl = '''
        import restage.core;
        widget Paywall = Text(text: "hi", locale: 42);
      ''';
      expect(validate(dsl), isNotEmpty);
    });

    test('a number on a curve slot (curve: 42) diagnoses', () {
      // The curve decoder reads a bare curve-name string. A number would be
      // silently nulled and Flutter's constructor default would be used.
      const dsl = '''
        import restage.core;
        widget Paywall = AnimatedOpacity(opacity: 1.0, duration: 200, curve: 42);
      ''';
      expect(validate(dsl), isNotEmpty);
    });

    test(
        'a non-canonical fontWeight member-name (fontWeight: "bogus") '
        'diagnoses', () {
      // `enumValue<FontWeight>(FontWeight.values, …)` resolves only the nine
      // `w100`..`w900` member names; any other string is silently nulled to the
      // slot default. The validator backstops the canonical member set (the
      // translator already canonicalises FontWeight aliases to their wN name).
      const dsl = '''
        import restage.core;
        widget Paywall = Text(text: "hi", fontWeight: "bogus");
      ''';
      expect(validate(dsl), isNotEmpty);
    });

    test(
        'an unsupported real Curves member (curve: "fastEaseInToSlowEaseOut") '
        'diagnoses', () {
      // `fastEaseInToSlowEaseOut` is a real `Curves` member, but it is outside
      // the runtime decoder's closed lookup table, so it is silently nulled to
      // the framework default. The validator backstops the supported curve
      // vocabulary the same way it backstops the canonical fontWeight set.
      const dsl = '''
        import restage.core;
        widget Paywall = AnimatedOpacity(
          opacity: 1.0,
          duration: 200,
          curve: "fastEaseInToSlowEaseOut",
        );
      ''';
      expect(validate(dsl), isNotEmpty);
    });

    test('an int on a double slot (width: 5) diagnoses', () {
      // The runtime `v<double>` decode is EXACT (`value is double`): an `int`
      // at a `length`/`real` slot is silently nulled. The codegen normalises
      // authored ints to doubles, so this catches a non-normalised / hand-
      // authored bare int.
      const dsl = '''
        import restage.core;
        widget Paywall = SizedBox(width: 5);
      ''';
      expect(validate(dsl), isNotEmpty);
    });

    test('a double on an int slot (color: 1.5) diagnoses', () {
      // The runtime `v<int>` decode is EXACT: a `double` at a `color` /
      // `integer` / `duration` slot is silently nulled.
      const dsl = '''
        import restage.core;
        widget Paywall = Container(color: 1.5);
      ''';
      expect(validate(dsl), isNotEmpty);
    });

    test('a bare number on a structured slot (padding: 8) diagnoses', () {
      // `edgeInsets` decodes from a `[l,t,r,b]` list; no structured/list/map
      // decoder accepts a top-level scalar, so a bare number is silent loss.
      const dsl = '''
        import restage.core;
        widget Paywall = Container(padding: 8);
      ''';
      expect(validate(dsl), isNotEmpty);
    });

    test('a wrong-typed literal in a switch branch diagnoses', () {
      // A `switch` is runtime-resolved, but EACH branch's literal is a
      // candidate value for the same slot, so each must be slot-valid. The
      // false branch binds a string to a `color` slot → silent loss.
      const dsl = '''
        import restage.core;
        widget Paywall = Container(
          color: switch state.selected { true: 0xFF000000, false: "bad" },
        );
      ''';
      expect(validate(dsl), isNotEmpty);
    });
  });

  group('property-value-type validation — valid bindings stay clean', () {
    test('enum-string on an enumValue slot (mainAxisAlignment) is valid', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Row(
          mainAxisAlignment: "center",
          crossAxisAlignment: "stretch",
          children: [],
        );
      ''';
      expect(validate(dsl), isEmpty);
    });

    test('enum-string on a fontWeight slot is valid', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Text(text: "hi", fontWeight: "w600");
      ''';
      expect(validate(dsl), isEmpty);
    });

    test('a number on a length / real slot is valid', () {
      const dsl = '''
        import restage.core;
        widget Paywall = SizedBox(width: 24.0, height: 92.0);
      ''';
      expect(validate(dsl), isEmpty);
    });

    test('an edgeInsets list on an edgeInsets slot is valid', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Container(padding: [28.0, 48.0, 28.0, 32.0]);
      ''';
      expect(validate(dsl), isEmpty);
    });

    test('an int on a color slot is valid', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Container(color: 0xFF6FD6C6);
      ''';
      expect(validate(dsl), isEmpty);
    });

    test('a data reference is never type-checked (runtime-resolved)', () {
      // `data.theme.colorScheme.primary` on a color slot is valid; the value
      // is resolved at render time, so the literal-type rule must skip it.
      const dsl = '''
        import restage.core;
        widget Paywall = Container(color: data.theme.colorScheme.primary);
      ''';
      expect(validate(dsl), isEmpty);
    });

    test('a switch with correctly-typed branch literals is valid', () {
      // The switch resolves at runtime, but each branch literal is checked
      // against the slot type — both branches here are valid int colors.
      const dsl = '''
        import restage.core;
        widget Paywall = Container(
          color: switch state.selected { true: 0xFF000000, false: 0x00000000 },
        );
      ''';
      expect(validate(dsl), isEmpty);
    });

    test('an {x, y} map on an alignment slot is valid', () {
      // The legitimate lowering of `Alignment.center` is the `{x, y}` map the
      // decoder expects — a non-scalar, so the literal-type rule must not
      // flag it.
      const dsl = '''
        import restage.core;
        widget Paywall = Container(alignment: { x: 0.0, y: 0.0 });
      ''';
      expect(validate(dsl), isEmpty);
    });

    test('a BCP-47 string on a locale slot (locale: "en-US") is valid', () {
      // The `locale` decoder reads a bare string and parses it into a
      // `Locale`; flagging a string here would be a false positive that
      // rejects valid authoring.
      const dsl = '''
        import restage.core;
        widget Paywall = Text(text: "hi", locale: "en-US");
      ''';
      expect(validate(dsl), isEmpty);
    });

    test('a curve-name string on a curve slot is valid', () {
      const dsl = '''
        import restage.core;
        widget Paywall = AnimatedOpacity(
          opacity: 1.0,
          duration: 200,
          curve: "easeInOut",
        );
      ''';
      expect(validate(dsl), isEmpty);
    });
  });

  group('structured-field scalar boundary — documented scope of the check', () {
    // The scalar-value type check reaches TOP-LEVEL scalar slots only. It does
    // not descend into a map literal bound to a structured slot to type-check a
    // nested field's scalar against the structured recipe's per-field types.
    // That structured-field-scalar correctness is closed by emitter-arm
    // discipline (and the emit-layer guard), not by this validator. These tests
    // pin that documented scope so a future change that broadens or narrows it
    // is a deliberate, visible decision rather than a silent drift.

    test(
        'a wrong-typed scalar nested in a structured map is NOT flagged by the '
        'validator (closed by emitter-arm discipline, not here)', () {
      // The `{x, y}` alignment map is the structured-map shape the decoder
      // expects; a nested non-numeric value would be silently dropped by the
      // structured decoder at runtime, but the validator does not descend into
      // the map's fields to catch it — by design, this class is closed at the
      // emit layer, owned elsewhere.
      const dsl = '''
        import restage.core;
        widget Paywall = Container(alignment: { x: 0.0, y: "bad" });
      ''';
      expect(
        validate(dsl),
        isEmpty,
        reason: 'the validator type-checks top-level scalar slots only; a '
            'scalar nested inside a structured map is closed by emitter-arm '
            'discipline and the emit-layer guard, not by this validator',
      );
    });

    test(
        'the top-level scalar floor still fires when the SLOT itself takes a '
        'scalar of the wrong type', () {
      // The boundary above is about NESTED scalars inside a map. The top-level
      // floor is unaffected: a bare scalar of the wrong type bound directly to
      // a slot is still rejected. This guards against the documentation being
      // mis-read as "the validator no longer checks scalars at all".
      const dsl = '''
        import restage.core;
        widget Paywall = SizedBox(width: "infinity");
      ''';
      expect(validate(dsl), isNotEmpty);
    });
  });
}
