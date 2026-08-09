/// A Dart grammar position where Restage emits an identifier.
enum DartIdentifierPosition {
  /// Prefix in an import directive (`import '...' as prefix`).
  importPrefix,

  /// Name of a declared or referenced Dart type.
  typeName,

  /// Selector for a named constructor (`Type.name`).
  constructorSelector,

  /// Selector for a member or top-level declaration (`owner.name`).
  memberSelector,

  /// Name in a named parameter declaration.
  namedParameter,

  /// Label in a named argument.
  namedArgument,

  /// Name in a record type or record literal.
  recordField,
}

/// Whether [value] is a public ASCII identifier legal at [position].
///
/// Dart's contextual and built-in identifiers are legal in several of the
/// positions Restage emits. Only hard keywords are rejected in those positions;
/// type names apply their narrower grammar separately. A leading underscore is
/// syntactically valid but library-private, so it is never public.
bool isPublicDartIdentifier(
  String value, {
  required DartIdentifierPosition position,
}) {
  if (value.startsWith('_') || !_identifierPattern.hasMatch(value)) {
    return false;
  }
  return switch (position) {
    DartIdentifierPosition.constructorSelector when value == 'new' => true,
    DartIdentifierPosition.importPrefix ||
    DartIdentifierPosition.typeName =>
      !_dartHardKeywords.contains(value) &&
          !_dartBuiltInIdentifiers.contains(value),
    DartIdentifierPosition.constructorSelector ||
    DartIdentifierPosition.memberSelector ||
    DartIdentifierPosition.namedParameter ||
    DartIdentifierPosition.namedArgument ||
    DartIdentifierPosition.recordField =>
      !_dartHardKeywords.contains(value),
  };
}

/// Whether [symbolName] is a public Dart type identity from [libraryUri].
///
/// Dart's built-in `dynamic`, `Function`, and `void` type spellings are not
/// ordinary type declaration names. They remain valid only when the identity is
/// explicitly or implicitly from `dart:core`.
bool isPublicDartTypeIdentity(String? libraryUri, String symbolName) {
  if ((libraryUri == null || libraryUri == 'dart:core') &&
      _dartCoreTypeKeywords.contains(symbolName)) {
    return true;
  }
  return isPublicDartIdentifier(
    symbolName,
    position: DartIdentifierPosition.typeName,
  );
}

/// Whether [value] can be emitted as an unquoted RFW map key or path part.
///
/// RFW's identifier grammar is intentionally narrower than Dart's: `$` is a
/// legal Dart identifier character but not an RFW one. Callers must quote a
/// valid Dart name when this returns false; they must not narrow Dart
/// identifier admission to the RFW subset.
bool isRfwIdentifier(String value) => _rfwIdentifierPattern.hasMatch(value);

final RegExp _identifierPattern = RegExp(r'^[A-Za-z$][A-Za-z0-9_$]*$');
final RegExp _rfwIdentifierPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

const Set<String> _dartCoreTypeKeywords = {'dynamic', 'Function', 'void'};

// Keywords that cannot be used as identifiers in any emitted name position.
// Contextual and built-in identifiers are deliberately absent.
const Set<String> _dartHardKeywords = {
  'assert',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'default',
  'do',
  'else',
  'enum',
  'extends',
  'false',
  'final',
  'finally',
  'for',
  'if',
  'in',
  'is',
  'new',
  'null',
  'rethrow',
  'return',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'var',
  'void',
  'while',
  'with',
};

// Built-in spellings that parse as ordinary identifiers in named parameters
// and selectors, but are forbidden as import prefixes and type names.
const Set<String> _dartBuiltInIdentifiers = {
  'abstract',
  'as',
  'covariant',
  'deferred',
  'dynamic',
  'export',
  'extension',
  'external',
  'factory',
  'Function',
  'get',
  'implements',
  'import',
  'interface',
  'late',
  'library',
  'mixin',
  'operator',
  'part',
  'required',
  'set',
  'static',
  'typedef',
};
