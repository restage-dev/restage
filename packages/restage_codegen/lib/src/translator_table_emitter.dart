import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/translator_recipe.dart';
import 'package:restage_codegen/src/translator_recipes.dart';

/// Renders the built-in translator table — the hand-authored recipes for
/// the framework value types — as `translator_tables.g.dart` source. The
/// entry point the catalog-emit build calls.
String emitBuiltinTranslatorTable() =>
    emitTranslatorTableSource(kHandAuthoredRecipes);

/// Renders [recipes] as the Dart source of `translator_tables.g.dart` — the
/// compiler-internal translator table the recipe dispatcher consumes.
///
/// The result is a `const Map<String, TranslatorRecipe>` keyed by each
/// recipe's `(library, type, variant)` triple, formatted byte-stably so it
/// passes `dart format --set-exit-if-changed` across regenerations.
String emitTranslatorTableSource(List<TranslatorRecipe> recipes) {
  final buf = StringBuffer();
  writeGeneratedHeader(buf);
  buf
    ..writeln('// ignore_for_file: type=lint')
    ..writeln("import 'package:restage_codegen/src/translator_recipe.dart';")
    ..writeln()
    ..writeln('/// Translator recipes keyed by their (library, type, variant) '
        'triple.')
    ..writeln('const Map<String, TranslatorRecipe> kTranslatorRecipes = {');
  for (final recipe in recipes) {
    buf.writeln('  ${_string(recipe.key)}: ${_recipe(recipe)},');
  }
  buf.writeln('};');
  return formatGeneratedDart(buf.toString());
}

String _recipe(TranslatorRecipe r) {
  final args = <String>[
    'typeName: ${_string(r.typeName)}',
    if (r.library != null) 'library: ${_string(r.library!)}',
    if (r.variant != null) 'variant: ${_string(r.variant!)}',
    if (r.validations.isNotEmpty)
      'validations: [${r.validations.map(_validation).join(', ')}]',
    if (r.deferredNamedArgs.isNotEmpty)
      'deferredNamedArgs: {${r.deferredNamedArgs.map(_string).join(', ')}}',
    'emit: ${_fragment(r.emit)}',
    'failureDsl: ${_string(r.failureDsl)}',
  ];
  return 'TranslatorRecipe(${args.join(', ')})';
}

String _validation(RecipeValidation v) =>
    'RecipeValidation(check: ${_check(v.check)}, '
    'issueCode: ${_string(v.issueCode)}, '
    'message: ${_string(v.message)})';

String _check(ValidationCheck c) => switch (c) {
      ArityExact(:final count) => 'ArityExact($count)',
      PositionalsAreIntLiterals(:final start, :final endExclusive) =>
        'PositionalsAreIntLiterals($start, $endExclusive)',
      PositionalIntsHaveValue(:final start, :final endExclusive) =>
        'PositionalIntsHaveValue($start, $endExclusive)',
      PositionalIntsInRange(
        :final start,
        :final endExclusive,
        :final min,
        :final max,
      ) =>
        'PositionalIntsInRange($start, $endExclusive, $min, $max)',
      PositionalNumLiteralInRange(:final index, :final min, :final max) =>
        'PositionalNumLiteralInRange($index, $min, $max)',
    };

String _fragment(EmitFragment f) => switch (f) {
      EmitFragmentLiteral(:final dsl) => 'EmitFragmentLiteral(${_string(dsl)})',
      EmitFragmentArg(
        :final arg,
        :final ifUnset,
        :final asLength,
        :final asDoubleList,
      ) =>
        _emitFragmentArg(arg, ifUnset, asLength, asDoubleList),
      EmitFragmentList(:final items) =>
        'EmitFragmentList([${items.map(_fragment).join(', ')}])',
      EmitFragmentMap(:final entries) =>
        'EmitFragmentMap([${entries.map(_mapEntry).join(', ')}])',
      EmitFragmentKernel(:final kernel, :final inputs) =>
        'EmitFragmentKernel(${_kernel(kernel)}, '
            '[${inputs.map(_value).join(', ')}])',
      EmitFragmentMemberTable(
        :final memberArg,
        :final members,
        :final fallback,
      ) =>
        fallback == null
            ? 'EmitFragmentMemberTable(${_argRef(memberArg)}, '
                '{${_members(members)}})'
            : 'EmitFragmentMemberTable(${_argRef(memberArg)}, '
                '{${_members(members)}}, fallback: ${_fragment(fallback)})',
    };

String _emitFragmentArg(
  ArgRef arg,
  EmitFragment? ifUnset,
  bool asLength,
  bool asDoubleList,
) {
  final parts = <String>[_argRef(arg)];
  if (ifUnset != null) parts.add('ifUnset: ${_fragment(ifUnset)}');
  if (asLength) parts.add('asLength: true');
  if (asDoubleList) parts.add('asDoubleList: true');
  return 'EmitFragmentArg(${parts.join(', ')})';
}

String _members(Map<String, EmitFragment> members) => members.entries
    .map((e) => '${_string(e.key)}: ${_fragment(e.value)}')
    .join(', ');

String _value(EmitValue v) => switch (v) {
      EmitValueArg(:final arg) => 'EmitValueArg(${_argRef(arg)})',
      EmitValueKernel(:final kernel, :final inputs) =>
        'EmitValueKernel(${_kernel(kernel)}, '
            '[${inputs.map(_value).join(', ')}])',
    };

String _mapEntry(EmitMapEntry e) => e.omitWhenArgUnset
    ? 'EmitMapEntry(${_string(e.key)}, ${_fragment(e.value)}, '
        'omitWhenArgUnset: true)'
    : 'EmitMapEntry(${_string(e.key)}, ${_fragment(e.value)})';

String _argRef(ArgRef a) => a.index != null
    ? 'ArgRef.positional(${a.index})'
    : 'ArgRef.named(${_string(a.label!)})';

String _kernel(TranslatorKernel k) => 'TranslatorKernel.${k.name}';

String _string(String s) {
  final escaped = s
      .replaceAll(r'\', r'\\')
      .replaceAll(r'$', r'\$')
      .replaceAll("'", r"\'")
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}
