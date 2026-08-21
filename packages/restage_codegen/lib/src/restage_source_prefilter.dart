// The one place a package-wide walk decides which of its candidate assets are
// worth resolving.
//
// A walk that calls `libraryFor` on every `lib/**.dart` asset pays for each
// file's transitive import closure and registers that whole closure as an
// input of the build step. On a large application that dominates the build.
// Reading a file's text instead is a single-file input and orders of magnitude
// cheaper.
//
// Note what this does and does not change about incrementality: the scan still
// reads every file, so every file is still an input and an edit anywhere still
// re-triggers the walk. What changes is the cost of the pass — a scan rather
// than a resolve — and the size of the invalidation set, which no longer
// reaches outside the package through the import closure.
//
// Every Restage declaration is introduced by an annotation. That annotation is
// spelled either in the file that declares it, or in an alias declared in
// another file — and building an alias means naming the annotation class, so
// the declaring file is itself scanned. Both are followed; see the alias pass
// below.

import 'dart:convert';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/authored_library_predicate.dart';
import 'package:restage_codegen/src/dart_source_parsing.dart';
import 'package:restage_codegen/src/screen_source_admission.dart'
    show isRfwScreenSourceInput;

const String _authoredDartGlob = 'lib/**.dart';

/// The annotation names that introduce a customer widget or its library.
const List<String> _widgetTokenNames = ['RestageWidget', 'RestageLibrary'];

/// The annotation names that introduce a surface source — a screen, a paywall,
/// or a flow — in either the canonical or the deprecated spelling.
const List<String> _surfaceTokenNames = [
  'Screen',
  'Paywall',
  'FlowGraph',
  'ScreenSource',
  'OnboardingSource',
  'PaywallSource',
  'FlowSource',
  'OnboardingFlow',
];

/// One lane's annotation vocabulary: the names, and the question the scan asks
/// of a file's raw text.
///
/// The names are needed as names, not only as a pattern — the alias pass has to
/// recognise `const card = RestageWidget(...)`, which is a declaration written
/// with the class, not an annotation written with it.
final class RestageTokenSet {
  RestageTokenSet._(this.names) : _pattern = _tokenPattern(names);

  /// The annotation class names this lane admits.
  final List<String> names;

  final RegExp _pattern;

  /// Whether [source] mentions any of [names], as an identifier or as an
  /// annotation written in the canonical const-instance spelling.
  bool hasMatch(String source) => _pattern.hasMatch(source);

  /// Whether a file annotating a declaration `@[name]` would be selected.
  ///
  /// The census asks this about a name rather than about a line of source, so
  /// it probes the contract instead of synthesising something that happens to
  /// match the pattern.
  bool wouldSelectAnnotation(String name) => hasMatch('@$name()');
}

/// Raw-source identifiers meaning a file may declare a customer widget or a
/// customer widget library.
@visibleForTesting
final RestageTokenSet restageWidgetSourceTokens =
    RestageTokenSet._(_widgetTokenNames);

/// Raw-source identifiers meaning a file may declare a Restage surface source
/// — a screen, a paywall, or a flow — in either the canonical or the
/// deprecated spelling.
///
/// One pattern serves the package roster and the package surface compiler:
/// they walk the same assets for the same declarations, and a filter that
/// admitted different files for each would let the two disagree about what the
/// package contains.
///
/// Visible for testing only. The lane helpers below are the way in: a walk
/// that took this set and chose its own `resolvable` could select different
/// files from the walk it is meant to match, and the disagreement would show
/// up as a surface missing from a green build. The annotation makes reaching
/// past them an analyzer warning rather than a convention.
@visibleForTesting
final RestageTokenSet restageSurfaceSourceTokens =
    RestageTokenSet._(_surfaceTokenNames);

/// Raw-source identifiers meaning a file may declare EITHER a customer widget
/// or a surface source.
///
/// The native screen index reads both vocabularies out of one pass over the
/// package — canonical screens by library identity, deprecated screens, and
/// customer widgets for the name-collision check — so it selects on the union
/// rather than running two walks.
final RestageTokenSet _widgetOrSurfaceTokens = RestageTokenSet._([
  ..._widgetTokenNames,
  ..._surfaceTokenNames,
]);

/// The libraries a customer-widget walk must resolve.
Future<List<AssetId>> selectRestageWidgetCandidates(
  BuildStep buildStep, {
  bool Function(AssetId)? resolvable,
}) =>
    _selectPackageWide(
      buildStep,
      tokens: restageWidgetSourceTokens,
      resolvable: resolvable,
    );

/// The libraries a surface-source walk must resolve.
///
/// This is the roster's discovery set, and the surface compiler consumes the
/// same one rather than deriving a second.
Future<List<AssetId>> selectRestageSurfaceCandidates(BuildStep buildStep) =>
    _selectPackageWide(
      buildStep,
      tokens: restageSurfaceSourceTokens,
      resolvable: isAuthoredDartLibraryAsset,
    );

/// The libraries the native screen index must resolve.
///
/// That index admits a source on three grounds and only two of them are
/// annotations: surface tokens (canonical screens, looked up by library
/// identity), widget tokens (the component-name collision check), and — with
/// no annotation at all — a **location**. A library at
/// `lib/<onboarding|message|survey>/screens/<id>.dart` is put through screen
/// admission whether or not it is annotated, and that is where its syntax
/// errors are reported. Selecting on tokens alone would delete that
/// diagnostic: the build would simply stop failing.
Future<List<AssetId>> selectRestageNativeScreenCandidates(
  BuildStep buildStep, {
  required bool Function(AssetId) resolvable,
}) =>
    _selectPackageWide(
      buildStep,
      tokens: _widgetOrSurfaceTokens,
      resolvable: resolvable,
      // Composed rather than passed straight through: a file this walk will
      // not resolve is not one it can examine, whatever its location says.
      // Admitting it and dropping it later reaches the same outcome by a
      // longer road, and the road is where the two rules could contradict
      // each other. `lib/onboarding/screens/welcome.g.dart`, which an
      // ordinary code generator writes next to an annotated screen, is
      // exactly that case.
      alwaysInclude: (asset) =>
          isRfwScreenSourceInput(asset) && resolvable(asset),
    );

/// Scans every `lib/**.dart` for [tokens] and returns the selection, narrowed
/// to what [resolvable] admits.
///
/// **Scanning is wider than resolving, deliberately.** A walk that will not
/// resolve a given file can still need it scanned: that file may be a `part`
/// whose owning library the walk does resolve, and the owner need spell no
/// token itself. Narrowing the scan instead of the result drops the
/// declaration from a green build.
///
/// [resolvable] is the caller's own view of what it will resolve, which is not
/// always [isAuthoredDartLibraryAsset] — two indexes carry their own, slightly
/// weaker, notion of an authored asset.
Future<List<AssetId>> _selectPackageWide(
  BuildStep buildStep, {
  required RestageTokenSet tokens,
  bool Function(AssetId)? resolvable,
  bool Function(AssetId)? alwaysInclude,
}) async {
  return selectRestageCandidateLibraries(
    buildStep,
    candidates: await buildStep.findAssets(Glob(_authoredDartGlob)).toList(),
    tokens: tokens,
    alwaysInclude: alwaysInclude,
    resolvable: resolvable,
  );
}

/// The subset of [candidates] a package-wide walk must resolve.
///
/// A candidate is selected when its own raw text spells one of [tokens], and a
/// selected `part` additionally selects the library that owns it — a part is
/// never resolved directly, so its declarations reach the walk only through
/// its owner, and the owner need not spell the annotation itself.
///
/// The owning library is joined syntactically, from the part's `part of`
/// directive: by URI when the part names one, otherwise by finding the
/// candidate whose `part` directive names this part. A part whose owner cannot
/// be identified at all returns every candidate — the walk then costs what it
/// cost before this filter existed rather than dropping a declaration. A part
/// whose owner is
/// identified but is not a candidate does not, because resolving everything
/// would not reach that owner either.
///
/// [alwaysInclude] selects a candidate whatever its text says. A walk that
/// admits a file on something other than an annotation — a location, say —
/// needs that admission to survive a filter keyed on annotations. It is the
/// caller's job not to admit what it will not resolve; nothing here can tell
/// a deliberate carve-out from a wiring mistake, so the lane that composes the
/// two answers is where they are reconciled.
///
/// [resolvable] is the caller's own view of what it will resolve, applied to
/// the result rather than to the scan: a file this walk will not resolve can
/// still be a `part` whose owner it does. Dropping a **joined owner** loses
/// the declaration written in the part that named it, so that case warns.
///
/// The result is sorted and duplicate-free, so a walk over it emits
/// byte-identical artifacts across runs.
///
/// An annotation reached through an alias declared in another file — `const rw
/// = RestageWidget(...)` there, `@rw` here, or the `typedef` form — is
/// followed: the declaring file names the annotation class and is therefore
/// scanned, which is what makes the alias findable at all.
@visibleForTesting
Future<List<AssetId>> selectRestageCandidateLibraries(
  BuildStep buildStep, {
  required Iterable<AssetId> candidates,
  required RestageTokenSet tokens,
  bool Function(AssetId)? alwaysInclude,
  bool Function(AssetId)? resolvable,
}) async {
  final candidateSet = candidates.toSet();
  final ordered = candidateSet.toList()..sort();
  final selected = <AssetId>{};
  // Each owner pulled in because a token-bearing part named it, mapped to
  // every such part. Tracked separately from the rest of the selection so a
  // walk that cannot resolve an owner can say whose declarations it is
  // losing — all of them, not whichever was seen last.
  final partsByOwner = <AssetId, List<AssetId>>{};
  // Parts whose `part of` names a library name rather than a URI. Their owner
  // can only be found by looking at what the other candidates declare.
  final partsAwaitingOwner = <AssetId>[];

  /// [selection] restricted to what [resolvable] admits, warning for each
  /// owner it drops.
  ///
  /// Every exit goes through this, so a path cannot forget to narrow.
  List<AssetId> narrow(List<AssetId> selection) {
    if (resolvable == null) return selection;
    final kept = <AssetId>[];
    for (final asset in selection) {
      if (resolvable(asset)) {
        kept.add(asset);
        continue;
      }
      final parts = partsByOwner[asset];
      if (parts == null) continue;
      // Dropping an owner loses the declarations written in every part that
      // named it. That was true before any of this filtering existed — the
      // walk never resolved such a library either — but it was silent, and
      // silence is what made it hard to find.
      final named =
          (parts.map((part) => part.path).toList()..sort()).join(', ');
      log.warning(
        '${asset.path} is not a library this walk resolves, so the Restage '
        'source declared in $named is not discovered. Move the declarations '
        'into a library this walk covers.',
      );
    }
    return kept;
  }

  // Set when a shape is met that the join cannot read; the caller then gets
  // every candidate rather than a selection that might be missing something.
  var giveUp = false;
  // Every name that reaches one of these annotations: the tokens themselves,
  // plus each alias found so far. `fresh` holds the ones no re-scan has looked
  // for yet.
  final known = {...tokens.names};
  final fresh = <String>{};
  // Selected files whose unit has already been read, so the alias pass does
  // not parse them a second time.
  final parsed = <AssetId>{};

  /// Reads [unit]'s alias declarations, then selects [candidate] and, if it is
  /// a `part`, the library that owns it.
  Future<void> take(AssetId candidate, String text) async {
    if (!selected.add(candidate)) return;

    final unit = parseUnresolvedDart(text, path: candidate.path);
    parsed.add(candidate);
    for (final name in _aliasNamesIn(unit, known)) {
      if (known.add(name)) fresh.add(name);
    }

    final reference = partOwnerReferenceOf(unit);
    if (reference == null) return;
    if (reference is! PartOwnerUri) {
      // The library-name form names no location, so the owner can only be
      // found by looking at what the other candidates declare.
      partsAwaitingOwner.add(candidate);
      return;
    }
    final owner = _resolveRelative(reference.uri, from: candidate);
    if (owner == null) {
      log.info(
        '${candidate.path} declares a `part of` URI that does not name an '
        'asset, so every Dart library in this package will be resolved.',
      );
      giveUp = true;
      return;
    }
    // An owner outside the candidate set is outside the walk, so resolving
    // everything would not find its declarations either. Say so and move on
    // rather than paying for a scan that cannot help.
    if (!candidateSet.contains(owner)) {
      // A warning, not a note: unlike the two fallbacks below, which announce
      // a cost, this announces that something the author wrote is not being
      // discovered — and a builder's `info` is invisible outside a verbose
      // build.
      log.warning(
        '${candidate.path} is owned by ${owner.uri}, which this walk does not '
        'cover; declarations in that part are not discovered.',
      );
      return;
    }
    selected.add(owner);
    partsByOwner.putIfAbsent(owner, () => []).add(candidate);
  }

  for (final candidate in ordered) {
    final text = await _scanText(buildStep, candidate);
    if (alwaysInclude?.call(candidate) != true && !tokens.hasMatch(text)) {
      continue;
    }
    await take(candidate, text);
    if (giveUp) return narrow(ordered);
  }

  await _takeAliasUsers(
    buildStep,
    ordered: ordered,
    selected: selected,
    parsed: parsed,
    known: known,
    fresh: fresh,
    take: take,
  );
  if (giveUp) return narrow(ordered);

  if (partsAwaitingOwner.isNotEmpty) {
    final owners = await _ownersDeclaringParts(
      buildStep,
      ordered: ordered,
      parts: partsAwaitingOwner.toSet(),
    );
    if (owners == null) return narrow(ordered);
    selected.addAll(owners.keys);
    for (final entry in owners.entries) {
      partsByOwner.putIfAbsent(entry.key, () => []).addAll(entry.value);
    }
  }

  return narrow(selected.toList()..sort());
}

/// Selects the candidates that annotate a declaration with an alias of one of
/// the lane's annotation names, iterating until no new alias is found.
///
/// An annotation can be reached through a name other than the class's own:
/// `const card = RestageWidget(...)` in one file, `@card` in another; or
/// `typedef RW = RestageWidget;` and `@RW(...)`. The lookup seam resolves both,
/// so a filter that did not would drop the declaration silently — and the file
/// using the alias spells nothing to scan for.
///
/// The pass is cheap because of where an alias can be declared: naming the
/// annotation class is the only way to build one, so **a declaring file in
/// this package is always already selected**, and [take] has already read its
/// unit. A package with no alias — nearly all of them — does no work here at
/// all. Only when one exists does the pass re-read the unselected candidates,
/// and only their bytes come from build_runner's cache; each read decodes
/// again.
///
/// The package qualifier is the limit, not a hedge. Only this package's
/// candidates are ever scanned, so an alias declared in a **dependency** is
/// never learned and the file annotating with it is not selected — while the
/// resolver, which does cross package boundaries, would have accepted it. The
/// README and CHANGELOG state this, and a test pins it.
///
/// [known] is every name that reaches an annotation and [fresh] the ones no
/// re-scan has looked for yet; [take] adds to both as it selects.
Future<void> _takeAliasUsers(
  BuildStep buildStep, {
  required List<AssetId> ordered,
  required Set<AssetId> selected,
  required Set<AssetId> parsed,
  required Set<String> known,
  required Set<String> fresh,
  required Future<void> Function(AssetId, String) take,
}) async {
  // Each round can only add names and candidates, both finite, so this
  // terminates; the bound is belt-and-braces against a future edit.
  for (var round = 0; round < ordered.length + 1; round++) {
    // A library pulled in because it owns a token-bearing part was selected
    // without being read, and can declare an alias like any other file.
    for (final asset in selected.toList()) {
      if (!parsed.add(asset)) continue;
      final unit = parseUnresolvedDart(
        await _scanText(buildStep, asset),
        path: asset.path,
      );
      for (final name in _aliasNamesIn(unit, known)) {
        if (known.add(name)) fresh.add(name);
      }
    }
    if (fresh.isEmpty) return;

    final pattern = _aliasUsePattern(fresh);
    fresh.clear();
    var found = false;
    for (final candidate in ordered) {
      if (selected.contains(candidate)) continue;
      final text = await _scanText(buildStep, candidate);
      if (!pattern.hasMatch(text)) continue;
      // May itself declare a further alias, which lands in `fresh`.
      await take(candidate, text);
      found = true;
    }
    if (!found && fresh.isEmpty) return;
  }
}

/// The names in [unit] that alias one of [known].
///
/// Matched on the name as written, because nothing here is resolved: any
/// segment of the leading identifier chain being a known name is enough, which
/// covers `Token(...)`, `prefix.Token(...)`, `Token.named(...)` and an alias of
/// an alias.
///
/// Every `const` declaration is read, not only the top-level ones. Keeping a
/// package's annotation constants together on a class — `@Annotations.card` —
/// is ordinary, and the use pattern already accepts that qualified form, so
/// reading only top-level declarations would find the use and never learn the
/// name. A `const` in a place no annotation can name simply never matches.
Set<String> _aliasNamesIn(CompilationUnit unit, Set<String> known) {
  final visitor = _AliasDeclarationVisitor(known);
  unit.accept(visitor);
  return visitor.aliases;
}

/// Collects every `const` or `typedef` declaration that names one of [known].
final class _AliasDeclarationVisitor extends RecursiveAstVisitor<void> {
  _AliasDeclarationVisitor(this.known);

  final Set<String> known;
  final Set<String> aliases = {};

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final list = node.parent;
    final initializer = node.initializer;
    if (list is VariableDeclarationList &&
        list.isConst &&
        initializer != null &&
        _namesKnown(initializer.toSource())) {
      aliases.add(node.name.lexeme);
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitGenericTypeAlias(GenericTypeAlias node) {
    if (_namesKnown(node.type.toSource())) aliases.add(node.name.lexeme);
    super.visitGenericTypeAlias(node);
  }

  bool _namesKnown(String source) =>
      (_leadingIdentifierChain.firstMatch(source)?.group(0) ?? '')
          .split('.')
          .map((segment) => segment.trim())
          .any(known.contains);
}

/// The leading dotted identifier chain of an expression's source.
final RegExp _leadingIdentifierChain = RegExp(
  r'^[A-Za-z_$][\w$]*(?:\s*\.\s*[A-Za-z_$][\w$]*)*',
);

/// Matches a file that uses one of [aliases] as an annotation, or declares a
/// further alias of one.
///
/// Both halves are needed for the fixpoint: the file declaring an alias of an
/// alias spells only the first name, and would otherwise never be selected —
/// so the second alias would never be found and the declaration using it would
/// be dropped, which is the whole shape this pass exists to close. Anchoring
/// on `@` and `=` keeps it far narrower than matching the bare name, which
/// for a customer-chosen identifier could select most of a package.
RegExp _aliasUsePattern(Set<String> aliases) {
  final names = (aliases.toList()..sort()).map(RegExp.escape).join('|');
  // Repeatable, not optional-once: a constant kept on a class and reached
  // through an import prefix is spelled `@p.Annotations.card` — two
  // qualifying segments, and there is no reason to stop at one.
  const qualifiers = r'(?:[A-Za-z_$][\w$]*\s*\.\s*)*';
  return RegExp('[@=]\\s*$qualifiers(?:$names)\\b');
}

/// Each candidate declaring a `part` directive for one of [parts], mapped to
/// every such part it owns — or `null` when some part is left without an
/// owner.
///
/// Reached only when a part declares the library-name form of `part of`, which
/// carries no path. Finding its owner means looking at what every other
/// candidate declares — still only a parse, never a resolution, and only for
/// the files whose text mentions `part` at all.
Future<Map<AssetId, List<AssetId>>?> _ownersDeclaringParts(
  BuildStep buildStep, {
  required List<AssetId> ordered,
  required Set<AssetId> parts,
}) async {
  final owners = <AssetId, List<AssetId>>{};
  final owned = <AssetId>{};
  for (final candidate in ordered) {
    if (owned.length == parts.length) break;
    if (parts.contains(candidate)) continue;
    final text = await _scanText(buildStep, candidate);
    if (!_partDirectiveWord.hasMatch(text)) continue;
    final unit = parseUnresolvedDart(text, path: candidate.path);
    for (final directive in unit.directives.whereType<PartDirective>()) {
      final uri = directive.uri.stringValue;
      if (uri == null) continue;
      final part = _resolveRelative(uri, from: candidate);
      if (part == null || !parts.contains(part)) continue;
      owners.putIfAbsent(candidate, () => []).add(part);
      owned.add(part);
    }
  }
  final orphans = parts.difference(owned);
  if (orphans.isEmpty) return owners;
  log.info(
    'No library in this package declares a `part` directive for '
    '${orphans.map((part) => part.path).join(', ')}, so every Dart library in '
    'this package will be resolved.',
  );
  return null;
}

/// Cheap gate before parsing a candidate for its `part` directives: a file
/// that never writes the word cannot declare one.
final RegExp _partDirectiveWord = RegExp(r'\bpart\b');

/// [candidate]'s text, for scanning only.
///
/// Decoded leniently on purpose. A file that is not valid UTF-8 must still
/// reach the resolver, which reports it by name; `readAsString` would fail the
/// build here with a byte offset and no file, turning a nameable authoring
/// mistake into an unattributed one. A replacement character can neither
/// create nor destroy an ASCII token match or a `part of` directive, so the
/// selection is unaffected.
Future<String> _scanText(BuildStep buildStep, AssetId candidate) async =>
    utf8.decode(await buildStep.readAsBytes(candidate), allowMalformed: true);

/// The asset [uri] names when written in [from], or `null` when [uri] does not
/// name an asset (a `dart:` library, or a malformed URI).
AssetId? _resolveRelative(String uri, {required AssetId from}) {
  try {
    return AssetId.resolve(Uri.parse(uri), from: from);
  } on Object {
    return null;
  }
}

/// A pattern matching any of [names] written as an identifier, or any of their
/// canonical const-instance spellings written as an annotation.
///
/// Both spellings are matched because both are accepted at the annotation
/// lookup seam: `@Screen()` names the class, `@screen` names its lowercase
/// const instance. The trailing `\b` is what keeps a longer identifier out —
/// `HomeScreenController` does not read as `Screen`.
///
/// The class-name half deliberately matches the bare identifier rather than
/// `@Screen`, so a prefixed import — `@rs.ScreenSource(...)`, ordinary Dart —
/// stays selected. Anchoring it on `@` with an optional prefix was measured to
/// be several times slower on real source (it backtracks on every `@override`)
/// while the breadth it would remove is a few percent of files. Measured over
/// this repository: 39.5 ms/pass against 307 ms for the anchored form over
/// 3307 files, for 106 fewer files selected — 3.2%, and 2.3–4.1% in every
/// other tree with any hits at all.
/// The const-instance half is anchored on `@` because those names are ordinary
/// lowercase words.
RegExp _tokenPattern(List<String> names) {
  final identifiers = names.join('|');
  final instances = names.map(constInstanceSpelling).join('|');
  return RegExp('\\b(?:$identifiers)\\b|@\\s*(?:$instances)\\b');
}
