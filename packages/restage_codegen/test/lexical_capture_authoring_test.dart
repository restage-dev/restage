import 'dart:io';

import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_compiler_core/src/rfw_program_envelope.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';
import 'support/lexical_callback_authoring.dart';

void main() {
  test('authored nested callbacks preserve proven lexical ownership', () async {
    final (source, catalog) = await compileLexicalCallback();
    final fixture = File(
      Directory.current.path.endsWith('restage_codegen')
          ? '../restage_core/test/fixtures/lexical_callbacks.rfwtxt'
          : 'packages/restage_core/test/fixtures/lexical_callbacks.rfwtxt',
    );
    if (Platform.environment['WRITE_LEXICAL_FIXTURE'] == '1')
      fixture.writeAsStringSync(source);
    expect(fixture.readAsStringSync(), source);
    final library = rfw.parseLibraryFile(source);
    expect(deriveSurfaceCapability(library, catalog).builtInFloor, 24);
    final root = library.widgets.single.root as rfw.ConstructorCall;
    final outer = decodeRfwProgramEnvelope(root.arguments['builder'])!;
    expect(outer.values.locals, isNotEmpty);
    final column = outer.bodies.single.widget as rfw.ConstructorCall;
    final collection = decodeRfwProgramEnvelope(
      column.arguments['children'],
      context: ValueOperationContext(locals: outer.values.locals),
    )!;
    final first = collection.bodies.first.widget as rfw.ConstructorCall;
    final nested = first.arguments['builder'];
    expect(() => decodeRfwProgramEnvelope(nested), throwsFormatException);
    final scope = RfwProgramScope([root], operations: const {});
    final inner = scope.decode(nested)!;
    expect(inner.values.outerLocals.keys, outer.values.locals.keys);
    expect(
      () => RfwProgramScope([first], operations: const {}),
      throwsFormatException,
    );
    final invalid = ValueOperationContext(
      locals: {
        for (final key in outer.values.locals.keys) key: ValueType.string,
      },
    );
    expect(
      () => decodeRfwProgramEnvelope(nested, context: invalid),
      throwsFormatException,
    );
  });
}
