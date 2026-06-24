import 'package:analyzer/error/error.dart' as analyzer;
import 'package:rfw_catalog_compiler/src/ir/diagnostic.dart';

/// Structured-type walk encountered a repeated type while recursing.
const IssueCode structuredCycle = _WalkerIssueCode(
  name: 'structuredCycle',
  uniqueName: 'rfwCatalogCompiler.structuredCycle',
  problemMessage: 'Structured type was encountered again during recursion.',
);

/// Structured-type walk exceeded its configured recursion depth.
const IssueCode structuredDepthExceeded = _WalkerIssueCode(
  name: 'structuredDepthExceeded',
  uniqueName: 'rfwCatalogCompiler.structuredDepthExceeded',
  problemMessage: 'Structured type walk exceeded the configured depth budget.',
);

/// Structured-type walk reached an abstract base type.
const IssueCode abstractTypeAwaitingUnion = _WalkerIssueCode(
  name: 'abstractTypeAwaitingUnion',
  uniqueName: 'rfwCatalogCompiler.abstractTypeAwaitingUnion',
  problemMessage: 'Abstract structured type awaits union resolution.',
);

/// A structured descendant reached as a shallow stub carries abstract-base /
/// union-typed fields that the shallow descendant walk does not resolve.
///
/// The walker materializes a descendant value type as a shallow stub (name,
/// library, location) without re-walking its own fields. When that descendant
/// itself declares fields whose types are registered abstract bases (the
/// types that resolve into discriminated unions on the direct walk path),
/// those references are not discovered through the stub. This is surfaced as
/// an informational diagnostic so an auditor can tell the reference was not
/// followed, rather than mistaking the shallow stub for a complete walk.
const IssueCode descendantUnionReferenceUndiscovered = _WalkerIssueCode(
  name: 'descendantUnionReferenceUndiscovered',
  uniqueName: 'rfwCatalogCompiler.descendantUnionReferenceUndiscovered',
  problemMessage: 'A structured descendant carries abstract-base / union '
      'fields that the shallow descendant walk does not resolve.',
);

/// Structured factory variant has an unsupported parameter type.
const IssueCode structuredFactoryUnsupportedParam = _WalkerIssueCode(
  name: 'structuredFactoryUnsupportedParam',
  uniqueName: 'rfwCatalogCompiler.structuredFactoryUnsupportedParam',
  problemMessage: 'Factory variant has an unsupported parameter type.',
);

/// Structured-type field was excluded by policy.
const IssueCode denylistedPropertyType = _WalkerIssueCode(
  name: 'denylistedPropertyType',
  uniqueName: 'rfwCatalogCompiler.denylistedPropertyType',
  problemMessage: 'Structured-type field was excluded by policy.',
);

/// Structured-type field has no catalog representation.
const IssueCode unsupportedPropertyType = _WalkerIssueCode(
  name: 'unsupportedPropertyType',
  uniqueName: 'rfwCatalogCompiler.unsupportedPropertyType',
  problemMessage: 'Structured-type field has no catalog representation.',
);

/// A union member named in the registry did not resolve to a class element.
const IssueCode unionMemberUnresolved = _WalkerIssueCode(
  name: 'unionMemberUnresolved',
  uniqueName: 'rfwCatalogCompiler.unionMemberUnresolved',
  problemMessage: 'Union member did not resolve to a class element.',
);

/// A union member resolved to a class element that is not a valid concrete
/// subtype of the union's abstract base.
const IssueCode unionMemberInvalid = _WalkerIssueCode(
  name: 'unionMemberInvalid',
  uniqueName: 'rfwCatalogCompiler.unionMemberInvalid',
  problemMessage: 'Union member is not a valid concrete subtype of the '
      'abstract base.',
);

/// The `@RestageLibrary` annotation could not be const-evaluated, or is
/// missing its required `library` field.
const IssueCode restageLibraryMalformed = _WalkerIssueCode(
  name: 'restageLibraryMalformed',
  uniqueName: 'rfwCatalogCompiler.restageLibraryMalformed',
  problemMessage: '@RestageLibrary declaration is malformed or incomplete.',
);

/// `@RestageLibrary` declares a built-in Restage namespace as its own library.
const IssueCode restageLibraryReservedNamespace = _WalkerIssueCode(
  name: 'restageLibraryReservedNamespace',
  uniqueName: 'rfwCatalogCompiler.restageLibraryReservedNamespace',
  problemMessage: 'A customer library must declare its own namespace, not a '
      'built-in Restage namespace.',
);

/// A walked `@RestageWidget` class originates outside the declared package.
const IssueCode restageLibraryForeignWidget = _WalkerIssueCode(
  name: 'restageLibraryForeignWidget',
  uniqueName: 'rfwCatalogCompiler.restageLibraryForeignWidget',
  problemMessage: 'An @RestageWidget class originates outside the package '
      'named by @RestageLibrary.',
);

/// An `@RestageWidget` class is reachable through a library in the
/// `@RestageLibrary` barrel's export closure, but is not itself exposed by
/// the barrel's export namespace (a `show`/`hide` clause excludes it).
///
/// Scope: this is raised only for a library that contributes at least one
/// *exported* `@RestageWidget` — a library whose annotated widgets are all
/// unexported is never visited, so its widgets raise no warning.
const IssueCode restageLibraryUnexportedWidget = _WalkerIssueCode(
  name: 'restageLibraryUnexportedWidget',
  uniqueName: 'rfwCatalogCompiler.restageLibraryUnexportedWidget',
  problemMessage: 'An @RestageWidget class is not exported from the '
      '@RestageLibrary barrel, so it is not catalogued.',
);

final class _WalkerIssueCode extends analyzer.DiagnosticCode {
  const _WalkerIssueCode({
    required super.name,
    required super.problemMessage,
    required super.uniqueName,
  });

  @override
  analyzer.DiagnosticSeverity get severity =>
      analyzer.DiagnosticSeverity.WARNING;

  @override
  analyzer.DiagnosticType get type => analyzer.DiagnosticType.STATIC_WARNING;
}
