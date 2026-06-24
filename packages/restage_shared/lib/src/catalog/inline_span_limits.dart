/// The maximum nesting depth of an `inlineSpan` (`Text.rich` / `TextSpan`)
/// wire value.
///
/// Single source of truth shared by two surfaces: the build-time translator
/// (which defers loud when an authored span tree nests deeper than this, so the
/// emitted blob never relies on runtime truncation for correctness) and the
/// runtime decoder (which uses it as a hostile-wire backstop, terminating a
/// pathologically deep tree rather than overflowing the stack). Pinning both to
/// one value is what keeps the translator from ever emitting a tree the decoder
/// would silently truncate.
const int kMaxInlineSpanDepth = 32;
