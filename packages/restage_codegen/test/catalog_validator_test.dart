import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/rfw_formats.dart' show parseLibraryFile;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final catalog = catalogWith([
    entry(
      name: 'Text',
      category: WidgetCategory.decoration,
      properties: [
        prop('text', PropertyType.string, required: true),
        prop('fontSize', PropertyType.real),
      ],
    ),
    entry(
      name: 'Column',
      childrenSlot: ChildrenSlot.list,
      properties: [
        prop('children', PropertyType.widgetList),
      ],
    ),
    // A widget with a REQUIRED widget slot and a REQUIRED widgetList slot, for
    // the required-presence checks. `optionalAside` is a non-required widget
    // slot used to confirm the check does not over-flag optional slots.
    entry(
      name: 'Frame',
      properties: [
        prop('child', PropertyType.widget, required: true),
        prop('rows', PropertyType.widgetList, required: true),
        prop('optionalAside', PropertyType.widget),
      ],
    ),
  ]);

  group('validateModelAgainstCatalog', () {
    test('passes for a valid widget library', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Text(text: "hi");
      ''';
      final library = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final issues = validateModelAgainstCatalog(library, catalog);
      expect(issues, isEmpty);
    });

    test('rejects unknown widget', () {
      const dsl = '''
        import restage.core;
        widget Paywall = NotAWidget();
      ''';
      final library = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final issues = validateModelAgainstCatalog(library, catalog);
      expect(
        issues.map((i) => i.code),
        contains(IssueCode.unknownWidget),
      );
      // The normalised wording explains a custom widget must be referenced
      // from Dart source, not named in hand-authored DSL.
      expect(
        issues.firstWhere((i) => i.code == IssueCode.unknownWidget).message,
        contains('Dart source'),
      );
    });

    test('rejects unknown property', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Text(text: "hi", notARealProp: 1);
      ''';
      final library = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final issues = validateModelAgainstCatalog(library, catalog);
      expect(
        issues.map((i) => i.code),
        contains(IssueCode.unknownProperty),
      );
    });

    test('recurses into widget children', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Column(children: [Text(text: "a"), NotReal()]);
      ''';
      final library = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final issues = validateModelAgainstCatalog(library, catalog);
      expect(
        issues.map((i) => i.code),
        contains(IssueCode.unknownWidget),
      );
    });

    test('passes Column with valid children', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Column(children: [Text(text: "a"), Text(text: "b")]);
      ''';
      final library = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final issues = validateModelAgainstCatalog(library, catalog);
      expect(issues, isEmpty);
    });
  });

  group('validateModelAgainstCatalog — required widget/widgetList presence',
      () {
    test('rejects an omitted required widget slot', () {
      // A required `widget` slot left out decodes to a runtime cast error
      // rather than a build-time diagnostic; surface it at build time.
      const dsl = '''
        import restage.core;
        widget Paywall = Frame(rows: [Text(text: "a")]);
      ''';
      final library = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final issues = validateModelAgainstCatalog(library, catalog);
      expect(
        issues.map((i) => i.code),
        contains(IssueCode.missingRequiredSlot),
      );
      expect(
        issues
            .firstWhere((i) => i.code == IssueCode.missingRequiredSlot)
            .message,
        contains('child'),
      );
    });

    test('rejects an omitted required widgetList slot', () {
      // A required `widgetList` slot left out silently decodes to an empty
      // list (no runtime error at all) — the genuine silent-loss case.
      const dsl = '''
        import restage.core;
        widget Paywall = Frame(child: Text(text: "a"));
      ''';
      final library = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final issues = validateModelAgainstCatalog(library, catalog);
      expect(
        issues.map((i) => i.code),
        contains(IssueCode.missingRequiredSlot),
      );
      expect(
        issues
            .firstWhere((i) => i.code == IssueCode.missingRequiredSlot)
            .message,
        contains('rows'),
      );
    });

    test('passes when both required slots are present', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Frame(child: Text(text: "a"), rows: [Text(text: "b")]);
      ''';
      final library = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final issues = validateModelAgainstCatalog(library, catalog);
      expect(issues, isEmpty);
    });

    test('does not flag an omitted non-required widget slot', () {
      // `optionalAside` is a non-required widget slot; omitting it is valid.
      const dsl = '''
        import restage.core;
        widget Paywall = Frame(child: Text(text: "a"), rows: [Text(text: "b")]);
      ''';
      final library = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final issues = validateModelAgainstCatalog(library, catalog);
      expect(
        issues.map((i) => i.code),
        isNot(contains(IssueCode.missingRequiredSlot)),
      );
    });
  });

  group('validateModelAgainstCatalog — library-local definitions', () {
    test('a reference to a library-local widget definition is valid', () {
      const dsl = '''
        import restage.core;
        widget Local = Text(text: "x");
        widget Paywall = Local();
      ''';
      final library = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final issues = validateModelAgainstCatalog(library, catalog);
      expect(issues, isEmpty);
    });

    test(
        'a library-local reference does not validate its args as catalog '
        'properties', () {
      const dsl = '''
        import restage.core;
        widget Local = Text(text: "x");
        widget Paywall = Local(headline: "Pro", count: 3);
      ''';
      final library = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final issues = validateModelAgainstCatalog(library, catalog);
      // `headline` / `count` bind the local definition's `args.`, not catalog
      // properties — they must not be checked against the catalog.
      expect(issues, isEmpty);
    });

    test('the body of a local definition is still catalog-validated', () {
      const dsl = '''
        import restage.core;
        widget Local = NotAWidget();
        widget Paywall = Local();
      ''';
      final library = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final issues = validateModelAgainstCatalog(library, catalog);
      // `Local` resolves locally, but its body's `NotAWidget` does not.
      expect(issues, hasLength(1));
      expect(issues.single.code, IssueCode.unknownWidget);
      expect(issues.single.message, contains('NotAWidget'));
    });

    test('a non-local unknown widget still errors unknownWidget', () {
      const dsl = '''
        import restage.core;
        widget Paywall = NotAWidget();
      ''';
      final library = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final issues = validateModelAgainstCatalog(library, catalog);
      expect(issues.map((i) => i.code), contains(IssueCode.unknownWidget));
    });
  });
}
