import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';

import 'helpers.dart';

const _textGolden = 'test/fixtures/goldens/context_list_loop.rfwtxt';
const _blobGolden = 'test/fixtures/goldens/context_list_loop.rfw';

void main() {
  test('a context list emits the exact text and binary loop', () async {
    const source = '''
$kStubAnnotationsAndBases

class Column extends Widget {
  const Column({required this.children});
  final List<Widget> children;
}

class Text extends Widget {
  const Text(this.text);
  final String text;
}

@PaywallSource(id: 'context_list_loop')
class ContextListLoop extends StatelessWidget {
  const ContextListLoop({required this.values});
  final List<String> values;

  Widget build(BuildContext context) => Column(
        children: [for (final value in values) Text(value)],
      );
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
      includeFlutter: false,
    );
    const input = 'apps_examples|lib/paywalls/context_list_loop.dart';
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/paywalls/context_list_loop.dart'),
      source,
    );

    final result = await testBuilders(
      [restageCodegenBuilder(BuilderOptions.empty)],
      const {input: source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    expect(result.errors, isEmpty);
    final text = result.readerWriter.testing.readString(
      AssetId('apps_examples', 'assets/paywalls/context_list_loop.rfwtxt'),
    );
    final blob = result.readerWriter.testing.readBytes(
      AssetId('apps_examples', 'assets/paywalls/context_list_loop.rfw'),
    );
    final regenerate =
        Platform.environment['REGEN_CONTEXT_LOOP_GOLDENS'] == '1';
    if (regenerate) {
      File(_textGolden).writeAsStringSync(text);
      File(_blobGolden).writeAsBytesSync(blob);
    }

    expect(text, File(_textGolden).readAsStringSync());
    expect(blob, orderedEquals(File(_blobGolden).readAsBytesSync()));

    final library = fmt.decodeLibraryBlob(blob);
    final root = library.widgets.single.root as fmt.ConstructorCall;
    final loop =
        (root.arguments['children']! as List<Object?>).single! as fmt.Loop;
    final output = loop.output as fmt.ConstructorCall;
    expect((loop.input as fmt.DataReference).parts, ['context', 'values']);
    expect(output.name, 'Text');
    expect((output.arguments['text']! as fmt.LoopReference).loop, 0);
    expect((output.arguments['text']! as fmt.LoopReference).parts, isEmpty);
  });
}
