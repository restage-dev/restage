// Reading a Dart file's directives without resolving it.
//
// Several places need the same two facts out of a source file — what it
// declares as `part`, and which library owns it — long before anything is
// resolved. Each had written the parse and the `part of` rule out again, and
// the copies had already drifted: only one of them knew that `part of` has a
// second, library-name spelling. One rule, one place.

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// Parses [text] as a whole Dart file, without resolving it.
///
/// Diagnostics are tolerated: a file that does not yet analyze still declares
/// which library owns it, and a caller that dropped it for a syntax error
/// would lose a declaration the resolver would have reported on. [path] only
/// attributes positions in that parse, and is required: every caller has one,
/// and a parse whose purpose is reporting positions should not be able to lose
/// them silently.
///
/// Most callers want only the directives; some also read declarations. What
/// they share, and what this name states, is that nothing here is resolved.
CompilationUnit parseUnresolvedDart(String text, {required String path}) =>
    parseString(
      content: text,
      path: path,
      throwIfDiagnostics: false,
    ).unit;

/// What a file's `part of` directive names.
///
/// Dart spells this two ways and they carry different amounts of information,
/// which is the whole reason this is a type rather than a nullable string: a
/// URI locates the owner directly, a library name does not locate it at all.
sealed class PartOwnerReference {
  const PartOwnerReference();
}

/// `part of 'some/library.dart';` — the owner is named by location.
final class PartOwnerUri extends PartOwnerReference {
  /// Creates a URI-form reference.
  const PartOwnerUri(this.uri);

  /// The URI as written, still to be resolved against the part's own location.
  final String uri;
}

/// `part of some.library;` — the deprecated form, which names the owner only
/// by its library name and so cannot be resolved from the part alone.
final class PartOwnerLibraryName extends PartOwnerReference {
  /// Creates a library-name-form reference.
  const PartOwnerLibraryName();
}

/// How [unit] names its owning library, or `null` when [unit] is not a part.
PartOwnerReference? partOwnerReferenceOf(CompilationUnit unit) {
  for (final directive in unit.directives) {
    if (directive is! PartOfDirective) continue;
    final uri = directive.uri?.stringValue;
    return uri == null ? const PartOwnerLibraryName() : PartOwnerUri(uri);
  }
  return null;
}
