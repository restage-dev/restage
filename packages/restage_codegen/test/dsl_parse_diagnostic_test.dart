import 'package:restage_codegen/src/dsl_parse_diagnostic.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

fmt.ParserException _failure(String text) {
  try {
    fmt.parseLibraryFile(text);
  } on fmt.ParserException catch (error) {
    return error;
  }
  fail('expected a parse failure');
}

void main() {
  test('names the innermost source expression holding the error', () {
    const inner = 'Text(text: oops oops)';
    const outer = 'Column(children: [$inner])';
    const text = 'widget Root = $outer;';
    final detail = dslParseFailureDetail(text, _failure(text), const [
      DslEmissionSource(
        dsl: outer,
        location: 'lib/a.dart:3:10',
        construct: 'Column(...)',
      ),
      DslEmissionSource(
        dsl: inner,
        location: 'lib/a.dart:4:12',
        construct: "Text('x')",
      ),
      DslEmissionSource(
        dsl: 'Text(text: "fine")',
        location: 'lib/a.dart:9:1',
        construct: 'Text(fine)',
      ),
    ]);
    expect(detail, contains("`Text('x')` at lib/a.dart:4:12"));
    expect(detail, contains('oops'));
  });

  test('falls back to the excerpt when no fragment covers the error', () {
    const text = 'widget Root = Text(text: oops oops);';
    final detail = dslParseFailureDetail(text, _failure(text), const []);
    expect(detail, startsWith('The emitted text near the error reads'));
    expect(detail, contains('oops'));
  });

  test('a translation records the source of each emitted fragment', () async {
    final translator = ExpressionTranslator(
      catalog: catalogWith([
        entry(
          name: 'Text',
          properties: [prop('text', PropertyType.string, positional: true)],
        ),
      ]),
      helpers: HelperRegistry(),
    );
    final expr = await parseExpressionForTest("Text('hi')");
    final result = translator.translate(expr, sourcePath: 'lib/a.dart');
    expect(
      result.emissionSources.map((s) => (s.dsl, s.construct)),
      contains(('Text(text: "hi")', "Text('hi')")),
    );
  });
}
