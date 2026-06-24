import 'package:meta/meta.dart';

/// Identifies one source-level argument of a factory call: either a
/// positional argument by zero-based index, or a named argument by label.
@immutable
final class ArgRef {
  /// References the positional argument at zero-based [index].
  const ArgRef.positional(this.index) : label = null;

  /// References the named argument labelled [label].
  const ArgRef.named(this.label) : index = null;

  /// Zero-based position for a positional reference; null for a named one.
  final int? index;

  /// Argument label for a named reference; null for a positional one.
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is ArgRef && other.index == index && other.label == label;

  @override
  int get hashCode => Object.hash(index, label);
}

/// A named arithmetic kernel. Implementations live alongside the dispatcher;
/// recipes reference kernels by this enum so the reference is type-safe on
/// both the emit and consume sides.
enum TranslatorKernel {
  /// Bit-packs four 0..255 channel values into one 32-bit ARGB integer.
  packArgb,

  /// Quantizes a 0.0..1.0 unit value to a 0..255 byte.
  quantizeUnitToByte,

  /// Formats an ARGB integer as the `0xAARRGGBB` color literal.
  formatColorHex,
}

/// A validation check — a typed rule plus its parameters. A recipe carries
/// the check; the consuming dispatcher carries the executor.
sealed class ValidationCheck {
  /// Const base constructor.
  const ValidationCheck();
}

/// The positional argument count must equal [count].
@immutable
final class ArityExact extends ValidationCheck {
  /// Requires exactly [count] positional arguments.
  const ArityExact(this.count);

  /// The required positional argument count.
  final int count;
}

/// Each positional argument in `[start, endExclusive)` must be an integer
/// literal.
@immutable
final class PositionalsAreIntLiterals extends ValidationCheck {
  /// Requires positionals in the half-open range to be integer literals.
  const PositionalsAreIntLiterals(this.start, this.endExclusive);

  /// First positional index (inclusive).
  final int start;

  /// One past the last positional index.
  final int endExclusive;
}

/// Each integer literal in `[start, endExclusive)` must have a representable
/// (non-overflowing) value.
@immutable
final class PositionalIntsHaveValue extends ValidationCheck {
  /// Requires the integer literals in the range to be non-overflowing.
  const PositionalIntsHaveValue(this.start, this.endExclusive);

  /// First positional index (inclusive).
  final int start;

  /// One past the last positional index.
  final int endExclusive;
}

/// Each integer value in `[start, endExclusive)` must lie within the
/// inclusive `[min, max]` range.
@immutable
final class PositionalIntsInRange extends ValidationCheck {
  /// Requires the integer values in the range to fall within `[min, max]`.
  const PositionalIntsInRange(
    this.start,
    this.endExclusive,
    this.min,
    this.max,
  );

  /// First positional index (inclusive).
  final int start;

  /// One past the last positional index.
  final int endExclusive;

  /// Inclusive lower bound.
  final int min;

  /// Inclusive upper bound.
  final int max;
}

/// The positional argument at [index] must be a numeric literal whose value
/// lies within the inclusive `[min, max]` range.
@immutable
final class PositionalNumLiteralInRange extends ValidationCheck {
  /// Requires positional [index] to be a numeric literal within `[min, max]`.
  const PositionalNumLiteralInRange(this.index, this.min, this.max);

  /// The positional argument index.
  final int index;

  /// Inclusive lower bound.
  final double min;

  /// Inclusive upper bound.
  final double max;
}

/// One validation step. Validations run in recipe order; the first failure
/// wins, emits a single diagnostic, and stops the recipe.
@immutable
final class RecipeValidation {
  /// Creates a validation step.
  const RecipeValidation({
    required this.check,
    required this.issueCode,
    required this.message,
  });

  /// The typed check to apply.
  final ValidationCheck check;

  /// Diagnostic issue code, carried as the issue-code enum's name so this
  /// file needs no dependency on the issue-code definition.
  final String issueCode;

  /// Verbatim diagnostic text. May contain the literal token `{value}`,
  /// which the dispatcher substitutes with the offending value.
  final String message;
}

/// A node producing a scalar value for kernel input.
sealed class EmitValue {
  /// Const base constructor.
  const EmitValue();
}

/// The raw literal scalar value of a captured argument.
@immutable
final class EmitValueArg extends EmitValue {
  /// Captures the literal scalar value of the argument referenced by [arg].
  const EmitValueArg(this.arg);

  /// The argument whose literal value is captured.
  final ArgRef arg;
}

/// A kernel call producing a scalar; inputs may themselves be kernels.
@immutable
final class EmitValueKernel extends EmitValue {
  /// Runs [kernel] over the evaluated [inputs] to produce a scalar.
  const EmitValueKernel(this.kernel, this.inputs);

  /// The kernel to run.
  final TranslatorKernel kernel;

  /// The kernel's scalar-producing inputs.
  final List<EmitValue> inputs;
}

/// A node producing a DSL string fragment.
sealed class EmitFragment {
  /// Const base constructor.
  const EmitFragment();
}

/// A verbatim DSL string — a literal-prefix injection or a sentinel default.
@immutable
final class EmitFragmentLiteral extends EmitFragment {
  /// Emits [dsl] verbatim.
  const EmitFragmentLiteral(this.dsl);

  /// The verbatim DSL string.
  final String dsl;
}

/// Recursively translates a captured argument expression. [ifUnset] supplies
/// a sentinel fragment when [arg] names an absent named argument.
@immutable
final class EmitFragmentArg extends EmitFragment {
  /// Translates the argument referenced by [arg], or emits [ifUnset] when a
  /// referenced named argument is absent.
  const EmitFragmentArg(
    this.arg, {
    this.ifUnset,
    this.asLength = false,
    this.asDoubleList = false,
  });

  /// The argument to translate.
  final ArgRef arg;

  /// Sentinel fragment used when a referenced named argument is absent.
  final EmitFragment? ifUnset;

  /// When true, the translated fragment is coerced to a double-formatted
  /// literal (`24` → `24.0`). Set this on positional slots that flow into
  /// an rfw `source.v<double>(...)` strict cast — without coercion an
  /// author-written int literal is silently nulled at decode time.
  final bool asLength;

  /// When true, a list-literal argument has each element coerced to a
  /// double-formatted literal (`[0, 1]` → `[0.0, 1.0]`). Set this on slots
  /// that flow into an rfw `list<double>` decode (e.g. a gradient's `stops`) —
  /// without coercion an author-written int element is silently nulled to
  /// `0.0` at decode time. The list analogue of [asLength].
  final bool asDoubleList;
}

/// A DSL list `[a, b, ...]`. Slot order is [items] order; broadcast is the
/// same [ArgRef] appearing in multiple items.
@immutable
final class EmitFragmentList extends EmitFragment {
  /// Emits [items] as a DSL list.
  const EmitFragmentList(this.items);

  /// The list's ordered item fragments.
  final List<EmitFragment> items;
}

/// One entry of an [EmitFragmentMap].
@immutable
final class EmitMapEntry {
  /// Creates a map entry mapping [key] to [value].
  const EmitMapEntry(this.key, this.value, {this.omitWhenArgUnset = false});

  /// The DSL map key.
  final String key;

  /// The fragment producing the entry's value.
  final EmitFragment value;

  /// When true, the entry is omitted if its value resolves from an absent
  /// named argument.
  final bool omitWhenArgUnset;
}

/// A DSL map `{k: v, ...}`.
@immutable
final class EmitFragmentMap extends EmitFragment {
  /// Emits [entries] as a DSL map.
  const EmitFragmentMap(this.entries);

  /// The map's ordered entries.
  final List<EmitMapEntry> entries;
}

/// A kernel producing a final DSL fragment from scalar inputs.
@immutable
final class EmitFragmentKernel extends EmitFragment {
  /// Runs [kernel] over the evaluated [inputs] to produce a DSL fragment.
  const EmitFragmentKernel(this.kernel, this.inputs);

  /// The kernel to run.
  final TranslatorKernel kernel;

  /// The kernel's scalar-producing inputs.
  final List<EmitValue> inputs;
}

/// Const-member-table lookup: the value of [memberArg] selects a fragment
/// from [members] by member name. When the referenced argument is not a
/// member reference (e.g. it is a constructor call) the lookup misses and
/// [fallback] is emitted instead — or the empty fragment when [fallback] is
/// null.
@immutable
final class EmitFragmentMemberTable extends EmitFragment {
  /// Selects a fragment from [members] keyed by the member name of the
  /// argument referenced by [memberArg]; emits [fallback] on a miss.
  const EmitFragmentMemberTable(
    this.memberArg,
    this.members, {
    this.fallback,
  });

  /// The argument whose member name selects the fragment.
  final ArgRef memberArg;

  /// Member name to fragment mapping.
  final Map<String, EmitFragment> members;

  /// Fragment emitted when [memberArg] resolves to a non-member expression
  /// (such as a constructor call), letting a recipe route that case through
  /// a recursive translation. Null falls back to the empty fragment.
  final EmitFragment? fallback;
}

/// The translator-table key for a `(library, typeName, variant)` triple.
///
/// `library` is null for framework / globally-unique types (`Color`,
/// `Offset`, …) and the owning catalog-library namespace (`restage.core`,
/// `restage.material`, …) for library-scoped structured types. Carrying the
/// library dimension keeps two same-named library types from colliding in a
/// consolidated table.
String recipeKey({
  required String? library,
  required String typeName,
  required String? variant,
}) =>
    '${library ?? ''}#$typeName${variant == null ? '' : '.$variant'}';

/// Converts a single Dart factory call of a known `(library, typeName,
/// variant)` triple into an RFW DSL fragment. Pure data: structural shaping
/// is the [emit] tree; arithmetic is delegated to named [TranslatorKernel]s.
@immutable
final class TranslatorRecipe {
  /// Creates a translator recipe.
  const TranslatorRecipe({
    required this.typeName,
    required this.emit,
    required this.failureDsl,
    this.library,
    this.variant,
    this.validations = const [],
    this.deferredNamedArgs = const {},
  });

  /// Owning catalog-library namespace, or null for framework / globally
  /// unique types such as `Color` and `Offset`.
  final String? library;

  /// Source-level type name, e.g. `Color`, `Offset`.
  final String typeName;

  /// Named constructor / factory name, or null for the unnamed constructor.
  final String? variant;

  /// Validation steps; run in order, first failure wins.
  final List<RecipeValidation> validations;

  /// Output-shape tree.
  final EmitFragment emit;

  /// DSL string emitted when a validation fails.
  final String failureDsl;

  /// Named arguments the source type supports but this recipe does NOT yet
  /// lower — a present-but-deferred field. When a call sets one of these, the
  /// dispatcher defers LOUD (one diagnostic, the [failureDsl] result) rather
  /// than silently dropping the field, which a recipe that merely omits an
  /// [EmitMapEntry] for the field would do. Empty (the common case) means
  /// every supported field is mapped — there is nothing to defer.
  ///
  /// Distinct from "unmapped but harmless" args (e.g. a callback or debug
  /// knob with no wire representation and no rendered effect): those are
  /// simply absent from both [emit] and this set, and ignored. Only a field
  /// whose omission would silently change the rendered result belongs here.
  final Set<String> deferredNamedArgs;

  /// Table key for the recipe's `(library, typeName, variant)` triple.
  String get key =>
      recipeKey(library: library, typeName: typeName, variant: variant);
}
