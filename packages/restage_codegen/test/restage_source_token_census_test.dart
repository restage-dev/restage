// The raw-source filter must stay a superset of what discovery looks for.
//
// The filter decides which files get resolved. Every annotation name the
// discovery seam accepts therefore has to be a name the filter matches — and
// unlike a lookup, which simply fails to match when its name set is
// incomplete, an incomplete filter removes the file from the walk entirely and
// the surface vanishes from a green build.
//
// Nothing links the filter's token list to the name sets discovery actually
// passes, so this census reads them out of the package's own source. A new
// annotation name added anywhere — including in a file that does not exist
// yet — fails here.
//
// A census is only worth what it can see, so a name argument this file cannot
// read is a **failure**, not a skip: silently skipping would let the next
// call-site shape reopen the hole this test exists to close. Names reach a
// lookup through four shapes, and all four are traced:
//
//   1. written at the call site        `…Any(el, const {'Screen'}, …)`
//   2. a top-level const               `…Any(el, _flowNames, …)`
//   3. a parameter of a wrapper        `_catalogAnnotation(el, name)` — the
//      wrapper becomes a lookup in its own right and its callers are traced
//   4. a loop variable over a const    `for (final e in _kinds.entries) …
//                                       …Any(cls, {e.key}, …)`
//
// A fifth shape reaches no lookup at all: code that identifies an annotation
// by comparing its resolved class name to a literal — `owner.name == 'Config'`
// — which the trace above cannot see. Those are censused separately, by the
// second test below, and held to the same bar. Anything that identifies an
// annotation by neither route is out of this file's reach; if such a shape is
// ever introduced, it is the filter's superset claim that quietly stops being
// provable, which is the reason both censuses fail loudly rather than skip.

import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/dart_source_parsing.dart';
import 'package:restage_codegen/src/restage_source_prefilter.dart';
import 'package:test/test.dart';

/// The discovery lookups, and which argument carries the names they accept.
///
/// `firstAnnotationFromOriginAny` takes a set of names; `firstAnnotation`
/// takes one name. Wrappers that forward a name are discovered from here.
const Map<String, int> _seedLookups = {
  'firstAnnotationFromOriginAny': 1,
  'firstAnnotation': 1,
  // The catalog compiler's own lookup. `@RestageLibrary` is discovered there
  // and nowhere in this package, so a census that read only this package would
  // pass while that half of the widget vocabulary went unguarded.
  '_firstAnnotationNamed': 1,
};

/// The trees this census reads, resolved once so the guards below and the
/// census itself cannot disagree about what was measured.
///
/// Discovery spans two packages: this one, and the catalog compiler that walks
/// a customer library for `@RestageLibrary`. Reading only the first would
/// leave the filter's claim — that it is a superset of everything discovery
/// accepts — true of half the vocabulary.
final List<Directory> _censusDirectories = [
  Directory(p.join(Directory.current.path, 'lib')),
  Directory(
    p.join(Directory.current.parent.path, 'rfw_catalog_compiler', 'lib'),
  ),
];

void main() {
  // Lazy, so a wrong working directory fails one named test with an
  // explanation rather than crashing the whole file at load time.
  late final census = _censusAnnotationNames();

  test('reads every tree discovery spans', () {
    // A missing tree must fail rather than silently shrink the census — the
    // whole instrument is an argument about completeness.
    for (final directory in _censusDirectories) {
      expect(
        directory.existsSync(),
        isTrue,
        reason: 'this census reads its trees relative to the working '
            'directory, so it must run from the package root (`dart test` '
            'from packages/restage_codegen), and the catalog compiler must be '
            'its sibling. Missing: ${directory.path}',
      );
    }
  });

  test('every annotation name discovery accepts is readable by this census',
      () {
    expect(
      census.names,
      isNotEmpty,
      reason: 'the census found no discovery call sites at all, which means '
          'it stopped measuring the thing it is here to measure',
    );

    expect(
      census.unreadable,
      isEmpty,
      reason: 'these discovery call sites pass a name argument this census '
          'cannot read, so the filter is no longer provably a superset of '
          'what discovery accepts. Teach the census the shape, or name the '
          'constant so it can be resolved: ${census.unreadable.join('; ')}',
    );
  });

  test('every annotation name discovery accepts is matched by the filter', () {
    final unmatched = [
      for (final entry in census.names.entries)
        if (!_qualifierAnnotations.contains(entry.key) &&
            !_matchedByFilter(entry.key))
          '${entry.key} (${entry.value})',
    ]..sort();

    expect(
      unmatched,
      isEmpty,
      reason: 'these annotation names are accepted by discovery but are not '
          'matched by restageWidgetSourceTokens or '
          'restageSurfaceSourceTokens, so a file declaring one would not be '
          'resolved: ${unmatched.join('; ')}',
    );
  });

  test('every annotation identified by class name is matched by the filter',
      () {
    final identified = _annotationNamesIdentifiedByClassName();

    expect(
      identified,
      isNotEmpty,
      reason: 'this census found no annotation identified by class name at '
          'all. That shape exists in this package, so finding none means the '
          'reader stopped measuring rather than that the shape went away',
    );

    final unmatched = [
      for (final entry in identified.entries)
        if (!_qualifierAnnotations.contains(entry.key) &&
            !_matchedByFilter(entry.key))
          '${entry.key} (${entry.value})',
    ]..sort();

    expect(
      unmatched,
      isEmpty,
      reason: 'these annotation names are identified by comparing a resolved '
          'annotation class name to a literal, and are not matched by '
          'restageWidgetSourceTokens or restageSurfaceSourceTokens. Either '
          'the filter must select a file spelling one, or the name qualifies '
          'a declaration that some other annotation already admitted and '
          'belongs in _qualifierAnnotations with that argument written down: '
          '${unmatched.join('; ')}',
    );
  });

  // The census is an argument about completeness, so the reader that makes it
  // gets the same treatment it gives discovery: every shape it cannot read has
  // to be named. These run it over a synthetic tree, because the shapes below
  // are ones this package does not happen to contain today — which is exactly
  // why the reader could stop seeing them without anything going red.
  group('the census reader', () {
    test('reads a const set composed from other const sets', () {
      final census = _censusOf({
        'names.dart': '''
const _canonicalGhosts = {'GhostSurfaceCanonical'};
const _legacyGhosts = {'GhostSurfaceLegacy'};
const _allGhosts = {..._canonicalGhosts, ..._legacyGhosts};
Object? ghosts(Object el) =>
    firstAnnotationFromOriginAny(el, _allGhosts, 'package:restage');
''',
      });

      expect(census.unreadable, isEmpty);
      expect(
        census.names.keys,
        containsAll(['GhostSurfaceCanonical', 'GhostSurfaceLegacy']),
      );
    });

    test('reads a const set composed across files, in either order', () {
      final census = _censusOf({
        // Alphabetically first, so the composing file is parsed before the
        // file that declares the piece it spreads.
        'a_composed.dart': '''
const _allGhosts = {..._pieceGhosts, 'GhostInline'};
Object? ghosts(Object el) =>
    firstAnnotationFromOriginAny(el, _allGhosts, 'package:restage');
''',
        'z_piece.dart': "const _pieceGhosts = {'GhostFromLaterFile'};",
      });

      expect(census.unreadable, isEmpty);
      expect(
        census.names.keys,
        containsAll(['GhostInline', 'GhostFromLaterFile']),
      );
    });

    test('names a const set it can only read part of', () {
      final census = _censusOf({
        'names.dart': '''
const _partial = {'GhostReadable', ...somethingElse};
Object? ghosts(Object el) =>
    firstAnnotationFromOriginAny(el, _partial, 'package:restage');
''',
      });

      // The readable half must not be reported as if it were the whole set.
      expect(census.unreadable, isNotEmpty);
      expect(census.unreadable.single, contains('_partial'));
    });

    test('reads a class name compared, negated, or switched on', () {
      // Four ways to identify an annotation by its class name, none of which
      // passes a name to a lookup. Written out here because this package does
      // not contain all four today, so a reader that stopped recognising one
      // would go on reporting a full-looking census.
      final identified = _annotationNamesIdentifiedByClassName([
        _syntheticTree({
          'shapes.dart': '''
bool byLocal(ElementAnnotation a) {
  final owner = resolvedAnnotationClass(a);
  return owner.name == 'GhostByLocal';
}

bool byEnclosing(ElementAnnotation a) {
  final owner = a.element.enclosingElement;
  return owner.name != 'GhostByEnclosing';
}

bool byCall(ElementAnnotation a) =>
    resolvedAnnotationClass(a)?.name == 'GhostByCall';

int bySwitch(ElementAnnotation a) => switch (resolvedAnnotationClass(a).name) {
      'GhostBySwitch' => 1,
      _ => 0,
    };
''',
        }),
      ]);

      expect(
        identified.keys,
        containsAll([
          'GhostByLocal',
          'GhostByEnclosing',
          'GhostByCall',
          'GhostBySwitch',
        ]),
      );
    });

    test('does not read a constructor or argument name as an annotation', () {
      // `Config.usage` is a named constructor and `usage:` is its argument
      // label. Neither is an annotation name, and reading them as one would
      // put unmatched names in front of the filter guard for nothing.
      final identified = _annotationNamesIdentifiedByClassName([
        _syntheticTree({
          'shapes.dart': '''
bool writesUsage(ElementAnnotation a) {
  final element = a.element;
  if (element.name == 'GhostConstructorName') return true;
  return a.arguments.first.name.label.name == 'GhostArgumentLabel';
}
''',
        }),
      ]);

      expect(identified, isEmpty);
    });

    test('names a call that omits the argument carrying the names', () {
      final census = _censusOf({
        'names.dart': '''
Object? kindAnnotation(Object el, [String name = 'GhostDefaulted']) =>
    firstAnnotation(el, name);
Object? user(Object el) => kindAnnotation(el);
''',
      });

      expect(census.unreadable, isNotEmpty);
      expect(census.unreadable.single, contains('kindAnnotation(el)'));
    });
  });
}

/// Annotation names identified by reading a resolved annotation class's name,
/// mapped to the file that does it.
///
/// This is the one discovery shape the lookup census cannot see: no name is
/// ever passed to a lookup, so nothing links the identifier to the filter.
///
/// What makes a name an *annotation* name here is the receiver, not the
/// enclosing function: only `.name` read from the annotation's own class —
/// `resolvedAnnotationClass(...)`, or a local bound from that or from
/// `…enclosingElement` — counts. A constructor's name or a constructor
/// argument's label is not an annotation name and is deliberately not read.
/// Every way of using that name is: `==`, `!=`, and a `switch` over it.
Map<String, String> _annotationNamesIdentifiedByClassName([
  List<Directory>? directories,
]) {
  final found = <String, String>{};
  for (final entry in _censusUnits(directories).entries) {
    final visitor = _AnnotationClassNameVisitor();
    entry.value.accept(visitor);
    for (final name in visitor.found) {
      found.putIfAbsent(name, () => entry.key);
    }
  }
  return found;
}

/// Reads every annotation name identified by class name in one unit.
///
/// One traversal: the locals bound to an annotation class and the reads of
/// `.name` are collected together, then intersected, because a local can be
/// bound after the line that reads it in source order.
final class _AnnotationClassNameVisitor extends RecursiveAstVisitor<void> {
  /// Locals bound to the annotation's own class declaration.
  final Set<String> _classLocals = {};

  /// Every `<receiver>.name` read, paired with the literals it is measured
  /// against.
  final List<({String receiver, List<String> literals})> _reads = [];

  List<String> get found => [
        for (final read in _reads)
          if (_isAnnotationClass(read.receiver)) ...read.literals,
      ];

  bool _isAnnotationClass(String receiver) =>
      _classLocals.contains(receiver) ||
      receiver.contains('resolvedAnnotationClass(');

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final initializer = node.initializer?.toSource() ?? '';
    if (initializer.contains('resolvedAnnotationClass(') ||
        initializer.endsWith('.enclosingElement')) {
      _classLocals.add(node.name.lexeme);
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (node.operator.lexeme == '==' || node.operator.lexeme == '!=') {
      _readComparison(node.leftOperand, node.rightOperand);
      _readComparison(node.rightOperand, node.leftOperand);
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitSwitchExpression(SwitchExpression node) {
    _readSwitch(node.expression, [
      for (final entry in node.cases) entry.guardedPattern.pattern,
    ]);
    super.visitSwitchExpression(node);
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    _readSwitch(node.expression, [
      for (final member in node.members)
        if (member case SwitchPatternCase(guardedPattern: final guarded))
          guarded.pattern,
    ]);
    super.visitSwitchStatement(node);
  }

  void _readComparison(Expression read, Expression literal) {
    if (literal is! SimpleStringLiteral) return;
    final receiver = _nameReadReceiver(read);
    if (receiver != null) {
      _reads.add((receiver: receiver, literals: [literal.value]));
    }
  }

  void _readSwitch(Expression read, List<DartPattern> patterns) {
    final receiver = _nameReadReceiver(read);
    if (receiver == null) return;
    final literals = <String>[];
    for (final pattern in patterns) {
      if (pattern
          case ConstantPattern(expression: SimpleStringLiteral(:final value))) {
        literals.add(value);
      }
    }
    _reads.add((receiver: receiver, literals: literals));
  }

  /// The receiver of [expression] when it reads a `.name`, else `null`.
  static String? _nameReadReceiver(Expression expression) =>
      switch (expression) {
        PrefixedIdentifier(
          prefix: SimpleIdentifier(name: final target),
          identifier: SimpleIdentifier(name: 'name'),
        ) =>
          target,
        PropertyAccess(
          target: final target?,
          propertyName: SimpleIdentifier(name: 'name')
        ) =>
          target.toSource(),
        _ => null,
      };
}

/// Runs the census over a synthetic tree of [files] (name to source).
AnnotationCensus _censusOf(Map<String, String> files) =>
    _censusAnnotationNames([_syntheticTree(files)]);

/// A throwaway directory holding [files], removed when the test ends.
Directory _syntheticTree(Map<String, String> files) {
  final directory = Directory.systemTemp.createTempSync('census_reader');
  addTearDown(() => directory.deleteSync(recursive: true));
  files.forEach((name, source) {
    File(p.join(directory.path, name)).writeAsStringSync(source);
  });
  return directory;
}

/// Annotation names that qualify a declaration rather than introducing one.
///
/// `RestageProperty` and `Ignore` annotate a constructor input or field of a
/// class that must already carry `@RestageWidget` to be looked at: the visitor
/// builds its class list from `@RestageWidget` first and only then reads
/// these, and the constructor facts call `@RestageProperty` "an overlay, not
/// an admission".
///
/// `Config` is the same in a different place: it is read only from a class the
/// caller already resolved and admitted — every call site reaches it from a
/// class the widget walk selected, or from a screen class the surface
/// annotation admitted. It is identified by class name rather than through a
/// lookup, so only the second census sees it.
///
/// A file spelling only one of these therefore contributes no declaration and
/// does not need to be resolved. They are deliberately kept OUT of the filter
/// — `@ignore` is Dart's own idiom, and matching `Ignore` would select a large
/// fraction of an ordinary codebase for nothing; `Config` is a common enough
/// word that matching it would do the same. A name added here needs the same
/// argument made for it: name the annotation that admitted the declaration
/// first.
const Set<String> _qualifierAnnotations = {
  'RestageProperty',
  'Ignore',
  'Config',
};

/// Whether a file spelling [name] as an annotation is selected by either
/// filter.
bool _matchedByFilter(String name) =>
    restageWidgetSourceTokens.wouldSelectAnnotation(name) ||
    restageSurfaceSourceTokens.wouldSelectAnnotation(name);

/// What the census read, and what it could not.
typedef AnnotationCensus = ({
  Map<String, String> names,
  List<String> unreadable,
});

/// A function argument position that carries annotation names.
typedef NamePosition = ({String function, int index});

/// Every Dart file of the censused trees, parsed, keyed by a readable path.
///
/// Both censuses read the same parse of the same trees, so they cannot come to
/// disagree about what was measured.
Map<String, CompilationUnit> _censusUnits([List<Directory>? directories]) {
  final files = [
    for (final directory in directories ?? _censusDirectories)
      ...directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
  ]..sort((left, right) => left.path.compareTo(right.path));

  return {
    for (final file in files)
      p.relative(file.path):
          parseUnresolvedDart(file.readAsStringSync(), path: file.path),
  };
}

/// Every annotation name reaching a discovery lookup anywhere under `lib/`.
///
/// [directories] defaults to the trees discovery actually spans; the tests
/// below pass a synthetic tree so the reader itself can be exercised on a
/// call-site shape that does not exist in this package yet.
AnnotationCensus _censusAnnotationNames([List<Directory>? directories]) {
  final constInitializers = <String, Expression>{};
  final units = _censusUnits(directories);

  for (final unit in units.values) {
    for (final declaration in unit.declarations) {
      if (declaration is! TopLevelVariableDeclaration) continue;
      for (final variable in declaration.variables.variables) {
        final initializer = variable.initializer;
        if (initializer is SetOrMapLiteral || initializer is StringLiteral) {
          constInitializers[variable.name.lexeme] = initializer!;
        }
      }
    }
  }

  // A const name set can be composed from other const name sets — the
  // `{..._canonical, ..._legacy}` shape — and the file declaring a piece may
  // be read after the file that spreads it, so resolution runs to a fixpoint
  // over every initializer rather than in declaration order.
  //
  // Only a constant that resolves WHOLE is published here. A half-read set
  // would resolve at its use site and quietly census fewer names than
  // discovery accepts, which is the one outcome this file exists to prevent;
  // left out, it reaches `_Unreadable` at that use site and gets named.
  final constNames = <String, List<String>>{};
  for (var pending = constInitializers; pending.isNotEmpty;) {
    final unresolved = <String, Expression>{};
    for (final entry in pending.entries) {
      if (_resolve(entry.value, constNames) case _Names(:final values)) {
        constNames[entry.key] = values;
      } else {
        unresolved[entry.key] = entry.value;
      }
    }
    if (unresolved.length == pending.length) break;
    pending = unresolved;
  }

  final names = <String, String>{};
  final unreadable = <String>[];
  final pending = <NamePosition>[
    for (final entry in _seedLookups.entries)
      (function: entry.key, index: entry.value),
  ];
  final visited = <NamePosition>{};

  while (pending.isNotEmpty) {
    final position = pending.removeLast();
    if (!visited.add(position)) continue;

    for (final entry in units.entries) {
      final visitor = _CallArgumentVisitor(position);
      entry.value.accept(visitor);
      for (final call in visitor.tooShort) {
        unreadable.add(
          '${entry.key}: `$call` passes no argument at position '
          '${position.index}',
        );
      }
      for (final argument in visitor.arguments) {
        switch (_resolve(argument, constNames)) {
          case _Names(:final values):
            for (final name in values) {
              names.putIfAbsent(name, () => entry.key);
            }
          case _Forwarded(:final position):
            pending.add(position);
          case _Unreadable():
            unreadable.add('${entry.key}: ${argument.toSource()}');
        }
      }
    }
  }
  // A lookup reached through anything other than a direct call — a tear-off,
  // a local alias — carries its names somewhere this census cannot follow.
  // That has to be a failure like any other unreadable shape: a silent skip
  // is exactly the hole this file exists to close.
  final tracked = {for (final position in visited) position.function};
  for (final entry in units.entries) {
    final references = _IndirectReferenceVisitor(tracked);
    // Declarations only: an `export … show firstAnnotation` names the function
    // without reaching any annotation name, and this census reads only this
    // package's own `lib/` anyway.
    for (final declaration in entry.value.declarations) {
      declaration.accept(references);
    }
    for (final reference in references.found) {
      unreadable.add('${entry.key}: `$reference` used other than as a call');
    }
  }

  return (names: names, unreadable: unreadable);
}

sealed class _Resolution {
  const _Resolution();
}

final class _Names extends _Resolution {
  const _Names(this.values);
  final List<String> values;
}

/// The argument is a parameter, so the enclosing function is itself a lookup
/// wrapper and its own callers carry the names.
final class _Forwarded extends _Resolution {
  const _Forwarded(this.position);
  final NamePosition position;
}

final class _Unreadable extends _Resolution {
  const _Unreadable();
}

/// What names [argument] denotes.
_Resolution _resolve(
  Expression argument,
  Map<String, List<String>> constNames,
) {
  switch (argument) {
    case final SimpleStringLiteral string:
      return _Names([string.value]);
    case final SimpleIdentifier identifier:
      return _resolveIdentifier(identifier, constNames);
    case final SetOrMapLiteral literal:
      final names = <String>[];
      for (final element in literal.elements) {
        switch (element) {
          case final SimpleStringLiteral string:
            names.add(string.value);
          case MapLiteralEntry(key: SimpleStringLiteral(value: final key)):
            names.add(key);
          case final SimpleIdentifier identifier:
            final resolved = _resolveIdentifier(identifier, constNames);
            if (resolved case _Names(:final values)) {
              names.addAll(values);
            } else {
              return resolved;
            }
          case SpreadElement(expression: final SimpleIdentifier spread):
            final spreadNames = constNames[spread.name];
            if (spreadNames == null) return const _Unreadable();
            names.addAll(spreadNames);
          case _:
            return const _Unreadable();
        }
      }
      return _Names(names);
    case _:
      return const _Unreadable();
  }
}

/// Resolves a bare identifier through a top-level const, an enclosing
/// function's parameter list, or a loop over a top-level const.
_Resolution _resolveIdentifier(
  SimpleIdentifier identifier,
  Map<String, List<String>> constNames,
) {
  final constant = constNames[identifier.name];
  if (constant != null) return _Names(constant);

  final owner = _enclosingCallable(identifier);
  if (owner == null) return const _Unreadable();

  final parameters = owner.parameters?.parameters ?? const <FormalParameter>[];
  final index = parameters.indexWhere(
    (parameter) => parameter.name?.lexeme == identifier.name,
  );
  if (index >= 0 && owner.name != null) {
    return _Forwarded((function: owner.name!, index: index));
  }

  final iterated = _iteratedConstantFor(identifier, owner.body, constNames);
  if (iterated != null) return _Names(iterated);

  return const _Unreadable();
}

/// The names of the top-level const collection [identifier] is bound from
/// inside [body], if it is a loop variable's key or value.
///
/// A name can be bound more than once in one function body, and a loop
/// variable name can be reused by an unrelated loop, so every candidate is
/// considered and the first that lands on a top-level const wins.
List<String>? _iteratedConstantFor(
  SimpleIdentifier identifier,
  AstNode? body,
  Map<String, List<String>> constNames,
) {
  if (body == null) return null;
  final locals = _LocalBindingVisitor(identifier.name);
  body.accept(locals);

  for (final source in locals.boundFrom) {
    final loops = _ForEachVisitor(source);
    body.accept(loops);
    for (final iterable in loops.iterables) {
      final names = constNames[iterable];
      if (names != null) return names;
    }
  }
  return null;
}

/// The function or method declaration [node] sits in.
({String? name, FormalParameterList? parameters, AstNode? body})?
    _enclosingCallable(AstNode node) {
  for (AstNode? current = node; current != null; current = current.parent) {
    if (current case final FunctionDeclaration declaration) {
      return (
        name: declaration.name.lexeme,
        parameters: declaration.functionExpression.parameters,
        body: declaration.functionExpression.body,
      );
    }
    if (current case final MethodDeclaration declaration) {
      return (
        name: declaration.name.lexeme,
        parameters: declaration.parameters,
        body: declaration.body,
      );
    }
  }
  return null;
}

/// Finds every reference to one of [tracked] that is not the target of a call.
final class _IndirectReferenceVisitor extends RecursiveAstVisitor<void> {
  _IndirectReferenceVisitor(this.tracked);

  final Set<String> tracked;
  final List<String> found = [];

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (tracked.contains(node.name) && !_isCallTarget(node)) {
      found.add(node.name);
    }
    super.visitSimpleIdentifier(node);
  }

  static bool _isCallTarget(SimpleIdentifier node) {
    final parent = node.parent;
    return parent is MethodInvocation && identical(parent.methodName, node);
  }
}

/// Collects the argument at one position of every call to one function.
final class _CallArgumentVisitor extends RecursiveAstVisitor<void> {
  _CallArgumentVisitor(this.position);

  final NamePosition position;
  final List<Expression> arguments = [];

  /// Calls that supply nothing at the tracked position — the names travel by
  /// a default value or a named argument this census cannot follow, so the
  /// call is recorded rather than dropped.
  final List<String> tooShort = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == position.function) {
      final actual = node.argumentList.arguments;
      if (actual.length > position.index) {
        arguments.add(actual[position.index]);
      } else {
        tooShort.add(node.toSource());
      }
    }
    super.visitMethodInvocation(node);
  }
}

/// Finds `final <name> = <source>.key;` (or `.value`) and reports every
/// `<source>` seen — one name can be bound in more than one place.
final class _LocalBindingVisitor extends RecursiveAstVisitor<void> {
  _LocalBindingVisitor(this.name);

  final String name;
  final List<String> boundFrom = [];

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.name.lexeme == name) {
      final initializer = node.initializer;
      if (initializer
          case PrefixedIdentifier(
            prefix: SimpleIdentifier(name: final prefix),
            identifier: SimpleIdentifier(name: final property),
          ) when property == 'key' || property == 'value') {
        boundFrom.add(prefix);
      }
    }
    super.visitVariableDeclaration(node);
  }
}

/// Finds `for (final <variable> in <iterable>…)` and reports every
/// `<iterable>` seen — an unrelated loop may reuse the variable name.
final class _ForEachVisitor extends RecursiveAstVisitor<void> {
  _ForEachVisitor(this.variable);

  final String variable;
  final List<String> iterables = [];

  @override
  void visitForEachPartsWithDeclaration(ForEachPartsWithDeclaration node) {
    if (node.loopVariable.name.lexeme == variable) {
      switch (node.iterable) {
        case PrefixedIdentifier(prefix: SimpleIdentifier(name: final prefix)):
          iterables.add(prefix);
        case final SimpleIdentifier identifier:
          iterables.add(identifier.name);
        case _:
          break;
      }
    }
    super.visitForEachPartsWithDeclaration(node);
  }
}
