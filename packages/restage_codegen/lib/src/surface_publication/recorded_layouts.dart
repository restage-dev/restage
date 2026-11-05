import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/surface_publication/plain_condition.dart';
import 'package:restage_shared/restage_shared.dart';

/// What a recorded record writes.
enum RecordedSiteKind {
  /// A value, a condition included.
  value,

  /// The items of a list a loop walks.
  items,

  /// A native object.
  native,

  /// An app widget the design places.
  island,
}

/// One record the recorded build writes, at the node of the app's code it
/// wraps.
final class RecordedSite {
  /// Creates a site.
  const RecordedSite({
    required this.kind,
    required this.key,
    required this.node,
    this.calls = const [],
  });

  /// What the record writes.
  final RecordedSiteKind kind;

  /// The context key; for an island, its qualified name.
  final String key;

  /// The node of the build, or of a helper it calls, the record wraps.
  final AstNode node;

  /// The helper calls in the build that lead to [node], outermost first;
  /// empty when [node] is in the build itself.
  final List<AstNode> calls;
}

/// A return of the build, which records [index] under [key] once it returns.
final class RecordedReturn {
  /// Creates a return.
  const RecordedReturn({
    required this.key,
    required this.index,
    required this.node,
  });

  /// The key the return index is recorded under.
  final String key;

  /// The index the return records.
  final int index;

  /// The expression the build returns, or a root switch arm's expression.
  final AstNode node;
}

/// The records a mount's recorded build writes, on the app's own build.
final class RecordedBuild {
  /// Creates the facts of one recorded build.
  const RecordedBuild({
    required this.body,
    this.sites = const [],
    this.returns = const [],
    this.splits = const {},
    this.placesAppWidgets = false,
    this.locate,
  });

  /// Where [node] is written, `lib/offer.dart:12:9`; by default its
  /// library's path and position.
  final String Function(AstNode node)? locate;

  /// The body of the build the mount records.
  final FunctionBody body;

  /// Every record of a value or an island.
  final List<RecordedSite> sites;

  /// Every recorded return; empty when the build has a single one.
  final List<RecordedReturn> returns;

  /// The split widgets the build places through their wrappers, by catalog
  /// name.
  final Set<String> splits;

  /// Whether the build places an app widget the design builds, keyed as the
  /// design keys it.
  final bool placesAppWidgets;
}

/// Where [build] produces each value and island it records; empty when the
/// mount doesn't record.
SurfaceLayoutsV1 recordedLayoutsOf(RecordedBuild? build) {
  if (build == null) return SurfaceLayoutsV1.empty;
  final body = build.body;
  final returns = <String, List<RecordedReturn>>{};
  for (final recorded in build.returns) {
    (returns[recorded.key] ??= []).add(recorded);
  }
  final domains = <String, Set<Object>>{
    for (final MapEntry(:key, :value) in returns.entries)
      key: {for (final recorded in value) recorded.index},
  };
  final conditions = Map<AstNode, String>.identity();
  for (final site in build.sites) {
    if (site.kind == RecordedSiteKind.value) conditions[site.node] = site.key;
  }
  final returnNodes = [for (final recorded in build.returns) recorded.node];
  final tests = <String, Expression>{};

  // What must hold for [site] to run.
  Map<String, Set<Object>> conditionOf(RecordedSite site) {
    final condition = <String, Set<Object>>{};
    void need(String key, Set<Object> values) {
      condition[key] = condition[key]?.intersection(values) ?? values;
    }

    // From the site out to its helper's declaration, then from each call
    // out to the next, the last one out to the build's body.
    final starts = [site.node, ...site.calls.reversed];
    for (final (index, start) in starts.indexed) {
      final inBuild = index == starts.length - 1;
      var child = start;
      for (
        var node = start.parent;
        node != null && !identical(node, body);
        node = node.parent
      ) {
        if (!inBuild &&
            (node is FunctionDeclaration || node is MethodDeclaration)) {
          break;
        }
        if (_testOf(node, child) case (final test, final held)) {
          for (final part in _parts(test, held ? '&&' : '||')) {
            if (conditions[part] case final key?) {
              need(key, {held});
              domains[key] = {false, true};
              tests[key] ??= part;
            }
          }
        }
        child = node;
      }
    }
    // A return's index is recorded once it returns, so the build takes only
    // a return that can still run after [site].
    final later = _runsAfter(
      site.calls.firstOrNull ?? site.node,
      body,
      returnNodes,
    );
    for (final MapEntry(:key, :value) in returns.entries) {
      final reachable = <Object>{
        for (final recorded in value)
          if (later.contains(recorded.node)) recorded.index,
      };
      if (reachable.isNotEmpty && reachable.length < domains[key]!.length) {
        need(key, reachable);
      }
    }
    return condition;
  }

  // A key recorded at several sites needs only what each of them needs.
  final values = <String, Map<String, Set<Object>>>{};
  final islands = <String, Map<String, Set<Object>>>{};
  for (final site in build.sites) {
    final into = site.kind == RecordedSiteKind.island ? islands : values;
    final condition = conditionOf(site);
    final prior = into[site.key];
    into[site.key] = prior == null
        ? condition
        : {
            for (final MapEntry(key: discriminator, :value) in prior.entries)
              if (condition[discriminator] case final other?)
                discriminator: value.union(other),
          };
  }
  Map<String, Map<String, Set<Object>>> conditional(
    Map<String, Map<String, Set<Object>>> all,
  ) => {
    for (final MapEntry(:key, :value) in all.entries)
      if (value.isNotEmpty && !returns.containsKey(key)) key: value,
  };
  final locate = build.locate ?? _location;
  SurfaceLayoutWhenV1 text(String source, String plain, AstNode at) =>
      SurfaceLayoutWhenV1(source: source, plain: plain, location: locate(at));
  return SurfaceLayoutsV1(
    domains: domains,
    values: conditional(values),
    islands: conditional(islands),
    build: _buildName(body),
    when: {
      for (final MapEntry(:key, value: test) in tests.entries)
        key: {
          for (final held in const [true, false])
            held: text(
              conditionSource(test, held: held),
              plainCondition(test, held: held),
              test,
            ),
        },
      for (final MapEntry(:key, value: recorded) in returns.entries)
        key: {
          for (final r in recorded)
            if (_guardOf(r.node, body) case (
              final source,
              final plain,
              final at,
            ))
              r.index: text(source, plain, at),
        },
    },
  );
}

// The nearest condition the build tests before it takes the return at
// [node]: its source, plain words and node.
(String, String, AstNode)? _guardOf(AstNode node, AstNode body) {
  var child = node;
  for (
    var parent = node.parent;
    parent != null && !identical(parent, body);
    parent = parent.parent
  ) {
    switch (parent) {
      case IfStatement(
            :final expression,
            :final caseClause,
            :final thenStatement,
          )
          when caseClause != null && identical(child, thenStatement):
        final pattern = caseClause.guardedPattern.pattern;
        return (
          '${expression.toSource()} case ${pattern.toSource()}',
          plainCase(expression, pattern),
          expression,
        );
      case IfStatement(
            :final expression,
            :final thenStatement,
            :final elseStatement,
            caseClause: null,
          )
          when identical(child, thenStatement) ||
              identical(child, elseStatement):
        final held = identical(child, thenStatement);
        return (
          conditionSource(expression, held: held),
          plainCondition(expression, held: held),
          expression,
        );
      case ConditionalExpression(
            :final condition,
            :final thenExpression,
            :final elseExpression,
          )
          when identical(child, thenExpression) ||
              identical(child, elseExpression):
        final held = identical(child, thenExpression);
        return (
          conditionSource(condition, held: held),
          plainCondition(condition, held: held),
          condition,
        );
      case SwitchPatternCase(:final guardedPattern):
        if (parent.parent case SwitchStatement(:final expression)) {
          return _caseGuard(expression, guardedPattern.pattern);
        }
      case SwitchExpressionCase(:final guardedPattern):
        if (parent.parent case SwitchExpression(:final expression)) {
          return _caseGuard(expression, guardedPattern.pattern);
        }
      case Block(:final statements):
        // An earlier `if` that always exits was false to reach [child].
        final index = statements.indexWhere((s) => identical(s, child));
        for (final statement in statements.take(index).toList().reversed) {
          if (statement case IfStatement(
            :final expression,
            :final thenStatement,
            elseStatement: null,
            caseClause: null,
          ) when _exits(thenStatement)) {
            return (
              conditionSource(expression, held: false),
              plainCondition(expression, held: false),
              expression,
            );
          }
        }
    }
    child = parent;
  }
  return null;
}

(String, String, AstNode) _caseGuard(Expression subject, DartPattern pattern) =>
    (
      '${subject.toSource()} case ${pattern.toSource()}',
      plainCase(subject, pattern),
      pattern,
    );

// The build [body] belongs to, `PlanPicker.build`.
String? _buildName(AstNode body) {
  final method = body.thisOrAncestorOfType<MethodDeclaration>();
  final owner = method?.thisOrAncestorOfType<ClassDeclaration>();
  return method == null || owner == null
      ? null
      : '${owner.namePart.typeName.lexeme}.${method.name.lexeme}';
}

// Where [node] is written in its library: `lib/offer.dart:12:9`.
String _location(AstNode node) {
  final unit = node.root;
  if (unit is! CompilationUnit) return '${node.offset}';
  final at = unit.lineInfo.getLocation(node.offset);
  final uri = unit.declaredFragment?.source.uri;
  final path = uri == null
      ? ''
      : uri.isScheme('package')
      ? 'lib/${uri.pathSegments.skip(1).join('/')}'
      : uri.path;
  return '$path:${at.lineNumber}:${at.columnNumber}';
}

// The test that guards [child] under [node], and the outcome [child] runs
// on: a branch of an `if` or `?:`, or the right operand of `&&` or `||`.
(Expression, bool)? _testOf(AstNode node, AstNode child) => switch (node) {
  BinaryExpression(:final leftOperand, :final rightOperand)
      when identical(child, rightOperand) &&
          (node.operator.lexeme == '&&' || node.operator.lexeme == '||') =>
    (leftOperand, node.operator.lexeme == '&&'),
  IfElement(:final expression, :final thenElement, :final elseElement)
      when identical(child, thenElement) || identical(child, elseElement) =>
    (expression, identical(child, thenElement)),
  IfStatement(:final expression, :final thenStatement, :final elseStatement)
      when identical(child, thenStatement) || identical(child, elseStatement) =>
    (expression, identical(child, thenStatement)),
  ConditionalExpression(
    :final condition,
    :final thenExpression,
    :final elseExpression,
  )
      when identical(child, thenExpression) ||
          identical(child, elseExpression) =>
    (condition, identical(child, thenExpression)),
  _ => null,
};

// [test] and every part it joins with [operator], each of which holds as
// the whole does.
Iterable<Expression> _parts(Expression test, String operator) sync* {
  yield test;
  switch (test) {
    case ParenthesizedExpression(:final expression):
      yield* _parts(expression, operator);
    case BinaryExpression(:final leftOperand, :final rightOperand)
        when test.operator.lexeme == operator:
      yield* _parts(leftOperand, operator);
      yield* _parts(rightOperand, operator);
  }
}

// The [returns] that can still run once [site] has run inside [body]: what
// follows it in each enclosing node, skipping branches it excludes and code
// after a return, and everything in a loop or closure around it.
Set<AstNode> _runsAfter(AstNode site, AstNode body, List<AstNode> returns) {
  final found = Set<AstNode>.identity();
  void within(AstNode? region, {int? from}) {
    if (region == null) return;
    for (final node in returns) {
      if (node.offset >= (from ?? region.offset) && node.end <= region.end) {
        found.add(node);
      }
    }
  }

  // The statements after [child] up to one that always exits; whether one
  // did.
  bool rest(List<Statement> statements, AstNode child) {
    final index = statements.indexWhere((s) => identical(s, child));
    for (final statement in statements.skip(index + 1)) {
      within(statement);
      if (_exits(statement)) return true;
    }
    return false;
  }

  if (returns.any((node) => identical(node, site))) found.add(site);
  var child = site;
  var returning = false;
  for (
    var node = site.parent;
    node != null && !identical(node, body);
    node = node.parent
  ) {
    if (returns.any((r) => identical(r, node))) found.add(node);
    if (node is TryStatement) {
      if (identical(child, node.body)) node.catchClauses.forEach(within);
      within(node.finallyBlock);
    } else if (node is FunctionExpression) {
      // A closure may run any number of times, at any later point.
      returning = false;
      within(node);
    } else if (returning) {
      // Nothing else in the function runs after a return.
    } else {
      switch (node) {
        case ReturnStatement() || ThrowExpression():
          returning = true;
        case Block(:final statements):
          returning = rest(statements, child);
        case SwitchMember(:final statements):
          returning = rest(statements, child);
        case IfStatement(:final thenStatement, :final elseStatement)
            when identical(child, thenStatement) ||
                identical(child, elseStatement):
        case IfElement(:final thenElement, :final elseElement)
            when identical(child, thenElement) || identical(child, elseElement):
        case ConditionalExpression(:final thenExpression, :final elseExpression)
            when identical(child, thenExpression) ||
                identical(child, elseExpression):
        case SwitchStatement() when child is SwitchMember:
        case SwitchExpression() when child is SwitchExpressionCase:
          // The other branches don't run.
          break;
        case ForStatement() ||
            WhileStatement() ||
            DoStatement() ||
            ForElement():
          within(node);
        default:
          within(node, from: child.end);
      }
    }
    child = node;
  }
  return found;
}

// Whether [statement] never completes normally.
bool _exits(Statement statement) => switch (statement) {
  ReturnStatement() => true,
  ExpressionStatement(expression: ThrowExpression()) => true,
  Block(:final statements) => statements.any(_exits),
  IfStatement(:final thenStatement, :final elseStatement?) =>
    _exits(thenStatement) && _exits(elseStatement),
  _ => false,
};
