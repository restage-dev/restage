import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/lowering_targets.dart';
import 'package:restage_codegen/src/modal_sheet_recognition.dart'
    show modalSheetFunctionOf;
import 'package:restage_codegen/src/number_format_recognition.dart'
    show numberFormatAdoptTarget;
import 'package:restage_codegen/src/surface_vocabulary.dart';
import 'package:restage_codegen/src/theme_recognition.dart'
    show libraryIsFlutter;
import 'package:restage_codegen/src/widget_classifier.dart'
    show customWidgetKey;
import 'package:restage_shared/restage_shared.dart' show WidgetVocabulary;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// What a walk of an app's own libraries found it can render.
@immutable
final class AppVocabularyDerivation {
  /// Pairs the wire-shaped [vocabulary] with the [references] that name it.
  const AppVocabularyDerivation({
    required this.vocabulary,
    required this.references,
    this.installsWholeCatalog = false,
    this.builtInWidgetCount = 0,
  });

  /// The delivery-side vocabulary: namespaced widget names and icon code
  /// points.
  final WidgetVocabulary vocabulary;

  /// The same set in the form generated Dart needs, with each icon rebuilt
  /// field for field rather than reduced to its code point.
  final SurfaceVocabularyReferences references;

  /// Whether app source calls the built-in helper with its own family options.
  final bool installsWholeCatalog;

  /// How many widgets the whole built-in catalog holds.
  final int builtInWidgetCount;
}

/// Derives the vocabulary [libraries] use: every catalog widget constructed
/// anywhere in them, every entry those constructions can be lowered to, and
/// every compile-time icon they name.
///
/// A construction counts when its class keys to a [WidgetEntry.flutterType] in
/// [catalog]; an app class that is not a catalog widget contributes nothing.
/// A named constructor is looked up as well, so `Image.network` reaches the
/// entry the catalog records under that constructor and the entry its bare
/// class names.
///
/// The walk is closed under lowering, so a widget the compiler emits as a
/// different entry — an interpolated `Text` as the rich-text entry, a
/// `PageView` as the pager — carries that entry into the app's over-the-air
/// headroom as well. `lowering_targets.dart` holds the pairings.
///
/// An icon is seen only where a reference resolves to a compile-time constant
/// `IconData` — `Icons.check`, `CupertinoIcons.heart`, or the name of a
/// `const` declaration holding one — and only when that constant names a font
/// family. An `IconData` reached through a variable, a function return, an
/// app-defined wrapper, or written inline as a constructor call rather than
/// named by a constant is out of scope. The walk covers [libraries]
/// themselves, never the packages they depend on.
///
/// Throws a [StateError] when a resolved icon cannot be carried exactly — it
/// carries a field the build cannot rebuild, or two icons disagree on what one
/// family, code point and mirroring renders — so an icon is never delivered
/// with a field silently dropped.
AppVocabularyDerivation deriveAppVocabulary(
  Iterable<ResolvedLibraryResult> libraries,
  Catalog catalog,
) {
  final visitor =
      _AppVocabularyVisitor(_qualifiedNamesByFlutterType(catalog), catalog);
  for (final library in libraries) {
    visitor.libraryIdentity = library.element.identifier;
    for (final unit in library.units) {
      unit.unit.accept(visitor);
    }
  }
  final references = SurfaceVocabularyReferences(
    widgetNames: visitor.widgetNames,
    icons: visitor.iconReferences.references,
  );
  return AppVocabularyDerivation(
    vocabulary: references.vocabulary,
    references: references,
    installsWholeCatalog: visitor.installsWholeCatalog,
    builtInWidgetCount: catalog.widgets
        .where(
          (entry) => WidgetLibrary.builtInLibraries.contains(entry.library),
        )
        .length,
  );
}

/// The wire-shaped half of [deriveAppVocabulary], for callers that need only
/// the delivered vocabulary.
WidgetVocabulary deriveAppWidgetVocabulary(
  Iterable<ResolvedLibraryResult> libraries,
  Catalog catalog,
) =>
    deriveAppVocabulary(libraries, catalog).vocabulary;

/// The vocabulary naming every widget in [entries], for folding the authored
/// surfaces' referenced entries into an app vocabulary.
WidgetVocabulary vocabularyOfCatalogEntries(Iterable<WidgetEntry> entries) =>
    WidgetVocabulary(
      widgetNames: {
        for (final entry in entries)
          WidgetVocabulary.qualifiedName(entry.library.namespace, entry.name),
      },
    );

/// Catalog qualified names keyed by `flutterType`, indexed once so a large
/// app's many constructor calls each cost one lookup. Two entries sharing a
/// `flutterType` both stay — the app may render either.
///
/// A key carries the named constructor wherever the entry does, so
/// `…#Card.filled` indexes separately from `…#Card`.
Map<String, Set<String>> _qualifiedNamesByFlutterType(Catalog catalog) {
  final byFlutterType = <String, Set<String>>{};
  for (final entry in catalog.widgets) {
    (byFlutterType[entry.flutterType] ??= <String>{}).add(
      WidgetVocabulary.qualifiedName(entry.library.namespace, entry.name),
    );
  }
  return byFlutterType;
}

final class _AppVocabularyVisitor extends RecursiveAstVisitor<void> {
  _AppVocabularyVisitor(this._qualifiedNamesByFlutterType, this._catalog);

  final Map<String, Set<String>> _qualifiedNamesByFlutterType;
  final Catalog _catalog;

  /// The library whose units are being walked, for a failure message.
  String libraryIdentity = '';

  final Set<String> widgetNames = <String>{};
  final IconReferenceCollector iconReferences = IconReferenceCollector();

  /// Set where the walked source builds the whole built-in catalog itself.
  bool installsWholeCatalog = false;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructor = node.constructorName.element;
    final cls =
        constructor?.enclosingElement ?? node.constructorName.type.element;
    if (cls is ClassElement) {
      final classKey = customWidgetKey(cls);
      _addQualifiedNames(_qualifiedNamesByFlutterType[classKey]);
      // A dozen entries key on a named constructor, so `Image.network` is
      // looked up under its own key as well as the bare class's.
      final member = constructor?.name ?? instanceCreationMemberName(node);
      if (member != null && member.isNotEmpty) {
        _addQualifiedNames(_qualifiedNamesByFlutterType['$classKey.$member']);
        if (_buildsWholeCatalog(cls, member)) installsWholeCatalog = true;
      }
      _collectLowerings(node, cls);
    }
    super.visitInstanceCreationExpression(node);
  }

  void _addQualifiedNames(Set<String>? names) {
    if (names != null) widgetNames.addAll(names);
  }

  /// Whether a construction is the SDK's whole-catalog install.
  bool _buildsWholeCatalog(ClassElement cls, String member) =>
      member == 'builtIn' &&
      cls.name == 'RestageWidgetLibraries' &&
      cls.library.identifier.startsWith('package:restage/');

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (modalSheetFunctionOf(node) != null) {
      _addTargets(kCallLowerings[node.methodName.name]);
    }
    // A named constructor stays a call where the analyzer did not rewrite it.
    final receiver = node.target;
    if (isTextRichInvocation(node) &&
        receiver is SimpleIdentifier &&
        libraryIsFlutter(receiver.element)) {
      _addTargets(const [kTextRichLowering]);
    }
    super.visitMethodInvocation(node);
  }

  /// What a compiled surface could name [node] as, beyond the entry its own
  /// class keys to. Gated on framework identity, as the lowerings are.
  void _collectLowerings(InstanceCreationExpression node, ClassElement cls) {
    if (!libraryIsFlutter(cls)) return;
    // Resolved class identity is independent of import-prefix AST spelling.
    final typeName = cls.name ?? instanceCreationTypeName(node);
    _addTargets(kAliasedWidgetLowerings[typeName]);
    if (typeName == 'Text') _addTargets(_textLowerings(node));
  }

  /// The entries a `Text` can be emitted as; a plain one yields none. Both
  /// formatting entries are named together rather than re-deriving which
  /// `intl` constructor picks which.
  List<LoweringTarget> _textLowerings(InstanceCreationExpression node) {
    final args = node.argumentList.arguments;
    final first = args.firstWhereOrNull((a) => a is! NamedExpression);
    final formats =
        first is MethodInvocation && numberFormatAdoptTarget(first) != null;
    return <LoweringTarget>[
      if (textLowersToRichText(node)) kTextRichLowering,
      if (formats) kPriceLowering,
      if (formats) kFormattedNumberLowering,
    ];
  }

  /// Adds every catalog entry [targets] names. A target the loaded catalog
  /// does not carry adds nothing.
  void _addTargets(Iterable<LoweringTarget>? targets) {
    for (final target in targets ?? const <LoweringTarget>[]) {
      for (final entry in target.resolve(_catalog)) {
        widgetNames.add(
          WidgetVocabulary.qualifiedName(entry.library.namespace, entry.name),
        );
      }
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _collectIconConstant(node.element);
    super.visitSimpleIdentifier(node);
  }

  /// Reads a const `IconData` behind [element] the way the translator does:
  /// the accessor's variable, then its constant fields.
  void _collectIconConstant(Element? element) {
    if (element is! PropertyAccessorElement) return;
    final variable = element.variable;
    final icon = variable.computeConstantValue();
    if (icon == null || !isIconDataValue(icon)) return;
    try {
      iconReferences.add(iconDataReference(icon));
    } on IconFontFamilyMissing {
      // The vocabulary is keyed by family, so an icon naming none is outside
      // what this walk censuses. A surface that renders one still fails.
      return;
    } on IconCarriageFailure catch (failure) {
      throw StateError(
        '$libraryIdentity names the icon ${_displayName(variable)}, but '
        '${failure.reason}.',
      );
    }
  }
}

/// The icon as its source spells it, for a failure message.
String _displayName(PropertyInducingElement variable) {
  final name = variable.name ?? '<unnamed>';
  final owner = variable.enclosingElement;
  final ownerName = owner is InterfaceElement ? owner.name : null;
  return ownerName == null ? name : '$ownerName.$name';
}
