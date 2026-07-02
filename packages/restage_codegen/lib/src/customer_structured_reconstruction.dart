/// The build-time reconstruction recipe for a customer structured type.
///
/// This is a CODEGEN concern, NOT a wire concern (the delivered blob never
/// reads it — the generated factory encodes the arg order in emitted code), so
/// it
/// lives in the discovery sidecar, threaded to the factory emitter, and never
/// touches the customer catalog wire format. It exists because a customer
/// reconstruction variant's `parameters` are empty (the enumerator never
/// populates them), so the emitter can't read arg kind/order from the wire — it
/// reads this plan, derived from the SAME analyzer walk the admissibility
/// predicate uses, so the two can't disagree.
library;

/// One placed argument of a [ReconstructionPlan]: the materialized field it is
/// sourced from, whether it is passed by name (`field: value`) or positionally
/// (`value`), whether the constructor param is required, and — for an OPTIONAL
/// NON-NULLABLE param — the reproduced ctor default to coalesce an absent wire
/// value against. Dart positional params CANNOT be passed by name, so `isNamed`
/// must match the ctor param exactly or the generated factory won't compile.
/// `isRequired` (from the analyzer param, since the lowered field's `required`
/// is not populated) drives the fail-closed decode: a required field throws on
/// a missing wire value rather than fabricating one.
///
/// `defaultCode` / `defaultEnumValue` carry the reproduced default an OPTIONAL
/// NON-NULLABLE param must coalesce its (`T?`) decode against, or the generated
/// factory won't compile. Exactly one is set (or neither):
///  * `defaultCode` — a primitive literal source (`'new'`, `0`, `true`),
///    emitted as-is.
///  * `defaultEnumValue` — the enum CONSTANT name (`soft`) of a customer-enum
///    default, which the emitter qualifies through the field's import alias
///    (`s0.Tone.soft`) so it resolves.
/// Both are `null` for a required param (fail-closed covers absence) and for an
/// optional NULLABLE param (the nullable decode assigns directly). An optional
/// non-nullable param whose default is NOT reproducible (a const constructor, a
/// framework const the generated library can't name) is not placed — the whole
/// type is excluded-loud (a predicate gap), never a silent value loss or a
/// non-compiling fallback.
typedef ReconstructionArg = ({
  String fieldName,
  bool isNamed,
  bool isRequired,
  String? defaultCode,
  String? defaultEnumValue,
});

/// The recipe to reconstruct a customer structured value: the constructor to
/// call (`null` = the unnamed ctor) and its placed arguments IN CONSTRUCTOR
/// DECLARATION ORDER.
///
/// Only *placed* params appear (a param sourced from a materialized field). An
/// optional param with no field is validly omitted (its default applies); the
/// positional-hole predicate guarantees no field-positional follows an omitted
/// positional, so emitting the placed args in order is faithful. A REQUIRED
/// param that cannot be placed is a predicate gap — the plan build returns
/// `null` and the type is excluded-loud, NEVER reconstructed with a partial
/// plan or a fabricated arg.
typedef ReconstructionPlan = ({
  String? namedConstructor,
  List<ReconstructionArg> args,
});
