import 'dart:io';

import 'package:restage_codegen/src/translator_table_emitter.dart';

/// Emits the compiler-internal translator recipe table consumed by the
/// codegen recipe dispatcher.
///
/// Run from the workspace root:
///
///     dart run restage_codegen:emit_translator_table
///
/// The translator table is a cross-library artifact (its recipes span
/// the curated libraries) and so is emitted on its own, separate from the
/// per-library catalog emission that `build_runner` drives.
void main() {
  final out = File(
    'packages/restage_codegen/lib/src/widget_catalog/translator_tables.g.dart',
  );
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(emitBuiltinTranslatorTable());
  stdout.writeln('[emit_translator_table] OK');
}
