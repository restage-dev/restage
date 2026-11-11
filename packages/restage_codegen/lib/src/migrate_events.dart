// Rewrites the removed top-level event helpers to `context.surfaceEvent`.
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// A call the migration left as it was, and how to change it by hand.
final class EventMigrationRefusal {
  /// Creates a refusal at [line]:[column].
  const EventMigrationRefusal(this.line, this.column, this.message);

  /// The 1-based line of the call.
  final int line;

  /// The 1-based column of the call.
  final int column;

  /// The problem and its "Try" fix.
  final String message;
}

/// The result of migrating one Dart source.
final class EventMigration {
  /// Creates a result.
  const EventMigration({
    required this.source,
    required this.rewritten,
    required this.declared,
    required this.refusals,
    this.notes = const [],
  });

  /// The migrated source; the input when nothing changed.
  final String source;

  /// How many calls were rewritten.
  final int rewritten;

  /// The `SurfaceEvent` constants added, as `Class.field`.
  final List<String> declared;

  /// The calls left as they were.
  final List<EventMigrationRefusal> refusals;

  /// Calls rewritten to a context whose events may still refuse, and why.
  final List<EventMigrationRefusal> notes;

  /// Whether the source changed.
  bool get changed => rewritten > 0;
}

const _helpers = {
  'surfaceEvent',
  'onboardingEvent',
  'surfaceEventWithContext',
  'paywallEvent',
};

/// Migrates the removed `surfaceEvent`, `onboardingEvent`,
/// `surfaceEventWithContext` and `paywallEvent` calls in [source] to
/// `context.surfaceEvent(...)`. A source that doesn't import
/// `package:restage` is returned unchanged; a second run changes nothing.
EventMigration migrateEvents(String source) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final unchanged = EventMigration(
    source: source,
    rewritten: 0,
    declared: const [],
    refusals: const [],
  );
  final importsRestage = unit.directives.whereType<ImportDirective>().any(
    (directive) =>
        directive.uri.stringValue?.startsWith('package:restage/') ?? false,
  );
  if (!importsRestage) return unchanged;

  // A function of the app's own with a helper's name is the app's.
  final declaredNames = _DeclaredFunctions();
  unit.accept(declaredNames);
  final calls = _HelperCalls(shadowed: declaredNames.names);
  unit.accept(calls);
  if (calls.found.isEmpty) return unchanged;

  final lines = unit.lineInfo;
  final edits = <({int offset, int end, String text})>[];
  final refusals = <EventMigrationRefusal>[];
  final notes = <EventMigrationRefusal>[];
  // Fields each class gains, in the order its calls first need them.
  final added = <ClassDeclaration, Map<String, ({String id, bool map})>>{};
  var rewritten = 0;

  void refuse(AstNode node, String message, {bool note = false}) {
    final at = lines.getLocation(node.offset);
    (note ? notes : refusals).add(
      EventMigrationRefusal(at.lineNumber, at.columnNumber, message),
    );
  }

  for (final call in calls.found) {
    final name = call.methodName.name;
    final arguments = call.argumentList.arguments;
    final typeArguments = call.typeArguments?.toSource() ?? '';

    if (name == 'surfaceEventWithContext') {
      if (arguments.length < 2 || arguments.first is NamedArgument) {
        refuse(
          call,
          '`surfaceEventWithContext` needs a context and an event. Try '
          'writing `context.surfaceEvent(event)` with the build context.',
        );
        continue;
      }
      final receiver = arguments.first.toSource();
      edits.add((
        offset: call.offset,
        end: arguments[1].offset,
        text: '$receiver.surfaceEvent$typeArguments(',
      ));
      rewritten++;
      continue;
    }

    final String context;
    switch (_contextFor(call)) {
      case _NoContext():
        refuse(
          call,
          '`$name(...)` is called where no BuildContext is in scope. Try '
          'passing the BuildContext of the widget that builds the button '
          'into this code and calling `context.surfaceEvent(...)` on it.',
        );
        continue;
      case _UnnamedContext():
        refuse(
          call,
          '`$name(...)` is inside a builder whose context parameter is `_`, '
          "which the call can't use. Try naming it, for example "
          '`(context) => ...`, and running the migration again.',
        );
        continue;
      case _StaticMethod(:final method):
        refuse(
          call,
          '`$name(...)` is in the static method `$method`, which has no '
          '`context`. Try passing the BuildContext of the widget that builds '
          'the button into `$method` and running the migration again.',
        );
        continue;
      case _Context(:final name, :final route):
        context = name;
        if (route) {
          refuse(
            call,
            '`$name.surfaceEvent(...)` uses the context of a route builder. '
            'A pushed route is built outside the surface that pushes it, so '
            "its events refuse. Try wrapping the route's content in "
            '`InheritedTheme.capture(from: context, to: '
            'Navigator.of(context).context).wrap(...)`, with the context '
            'that pushes it.',
            note: true,
          );
        }
    }

    if (name != 'paywallEvent') {
      edits.add((
        offset: call.offset,
        end: call.methodName.end,
        text: '$context.surfaceEvent',
      ));
      rewritten++;
      continue;
    }

    // `paywallEvent('name'[, args: map])` fires a typed event the enclosing
    // class declares.
    final eventName = arguments.firstOrNull is NamedArgument
        ? null
        : switch (arguments.firstOrNull) {
            SimpleStringLiteral(:final value) => value,
            _ => null,
          };
    if (eventName == null) {
      refuse(
        call,
        '`paywallEvent` names its event with something other than a string '
        "literal, so the migration can't declare it. Try declaring "
        "`static const myEvent = SurfaceEvent<void>('my_event');` and "
        'calling `context.surfaceEvent(myEvent)`.',
      );
      continue;
    }
    final enclosing = call.thisOrAncestorOfType<ClassDeclaration>();
    // A State's events belong to its widget, which declares them.
    final owner = enclosing == null ? null : _widgetOf(enclosing, unit);
    if (owner == null) {
      refuse(
        call,
        "`paywallEvent('$eventName')` is called outside a class, so the "
        'migration has nowhere to declare the event. Try declaring '
        "`static const myEvent = SurfaceEvent<void>('$eventName');` on the "
        'surface class and calling `context.surfaceEvent(Surface.myEvent)`.',
      );
      continue;
    }
    final mapArgument = arguments
        .whereType<NamedArgument>()
        .where((argument) => argument.name.lexeme == 'args')
        .firstOrNull;
    final fields = added.putIfAbsent(owner, () => {});
    final field = _fieldFor(owner, eventName, fields);
    // One name fired with and without a map carries a map.
    fields[field] = (
      id: eventName,
      map: mapArgument != null || (fields[field]?.map ?? false),
    );
    final className = owner.namePart.typeName.lexeme;
    final firstArgument = arguments.first;
    edits.add((
      offset: call.offset,
      end: firstArgument.end,
      text: '$context.surfaceEvent($className.$field',
    ));
    if (mapArgument != null) {
      edits.add((
        offset: mapArgument.offset,
        end: mapArgument.argumentExpression.offset,
        text: '',
      ));
    }
    rewritten++;
  }

  final declared = <String>[];
  for (final MapEntry(key: owner, value: fields) in added.entries) {
    if (fields.isEmpty) continue;
    final className = owner.namePart.typeName.lexeme;
    final text = StringBuffer();
    for (final MapEntry(key: field, value: (:id, :map)) in fields.entries) {
      final type = map ? 'Map<String, Object?>' : 'void';
      text.write("\n  static const $field = SurfaceEvent<$type>('$id');");
      declared.add('$className.$field');
    }
    switch (owner.body) {
      case final BlockClassBody body:
        if (body.members.isNotEmpty) text.write('\n');
        edits.add((
          offset: body.leftBracket.end,
          end: body.leftBracket.end,
          text: text.toString(),
        ));
      case final body:
        // A body written as `;` becomes a block.
        edits.add((offset: body.offset, end: body.end, text: ' {$text\n}'));
    }
  }

  edits.sort((left, right) => right.offset.compareTo(left.offset));
  var migrated = source;
  for (final edit in edits) {
    migrated = migrated.replaceRange(edit.offset, edit.end, edit.text);
  }
  return EventMigration(
    source: rewritten == 0 ? source : migrated,
    rewritten: rewritten,
    declared: declared,
    refusals: refusals,
    notes: notes,
  );
}

// The class whose static fields name [cls]'s events: [cls], or the widget
// it is the State of when [unit] declares that widget.
ClassDeclaration _widgetOf(ClassDeclaration cls, CompilationUnit unit) {
  final superclass = cls.extendsClause?.superclass;
  if (superclass?.name.lexeme != 'State') return cls;
  final widget = superclass!.typeArguments?.arguments.firstOrNull;
  if (widget is! NamedType) return cls;
  return unit.declarations.whereType<ClassDeclaration>().firstWhere(
    (declaration) => declaration.namePart.typeName.lexeme == widget.name.lexeme,
    orElse: () => cls,
  );
}

sealed class _ContextOutcome {
  const _ContextOutcome();
}

// A BuildContext named [name]; [route] when it is a route builder's.
final class _Context extends _ContextOutcome {
  const _Context(this.name, {this.route = false});
  final String name;
  final bool route;
}

final class _NoContext extends _ContextOutcome {
  const _NoContext();
}

// A builder's context parameter named `_`.
final class _UnnamedContext extends _ContextOutcome {
  const _UnnamedContext();
}

// A static method of a State, which has no `context`.
final class _StaticMethod extends _ContextOutcome {
  const _StaticMethod(this.method);
  final String method;
}

const _routes = {
  'MaterialPageRoute',
  'CupertinoPageRoute',
  'PageRouteBuilder',
  'DialogRoute',
  'RawDialogRoute',
  'CupertinoDialogRoute',
  'CupertinoModalPopupRoute',
  'ModalBottomSheetRoute',
};

// The BuildContext in scope at [call].
_ContextOutcome _contextFor(MethodInvocation call) {
  for (var node = call.parent; node != null; node = node.parent) {
    final parameters = switch (node) {
      FunctionExpression(:final parameters) => parameters,
      MethodDeclaration(:final parameters) => parameters,
      ConstructorDeclaration(:final parameters) => parameters,
      _ => null,
    };
    for (final parameter in parameters?.parameters ?? <FormalParameter>[]) {
      final name = parameter.name?.lexeme;
      if (name == null) continue;
      final declared = parameter is RegularFormalParameter
          ? parameter.type
          : null;
      final isContext =
          declared is NamedType && declared.name.lexeme == 'BuildContext' ||
          // An untyped first parameter of a builder closure is its context.
          declared == null &&
              node is FunctionExpression &&
              identical(parameter, parameters!.parameters.first) &&
              _isBuilderArgument(node);
      if (!isContext) continue;
      if (name == '_') return const _UnnamedContext();
      return _Context(
        name,
        route: node is FunctionExpression && _isRouteBuilder(node),
      );
    }
    if (node is MethodDeclaration && node.isStatic) {
      return _StaticMethod(node.name.lexeme);
    }
    if (node is ClassDeclaration) {
      // A State has its own `context`.
      final superclass = node.extendsClause?.superclass.name.lexeme;
      return superclass == 'State'
          ? const _Context('context')
          : const _NoContext();
    }
  }
  return const _NoContext();
}

// Whether [closure] builds a route's content.
bool _isRouteBuilder(FunctionExpression closure) {
  final route = closure.parent?.parent?.parent;
  final name = switch (route) {
    MethodInvocation(:final methodName) => methodName.name,
    InstanceCreationExpression(:final constructorName) =>
      constructorName.type.name.lexeme,
    _ => null,
  };
  return _routes.contains(name);
}

// Whether [closure] is passed as a `builder`-style named argument.
bool _isBuilderArgument(FunctionExpression closure) {
  final parent = closure.parent;
  return parent is NamedArgument &&
      parent.name.lexeme.toLowerCase().endsWith('builder');
}

// A field name for [eventName] on [owner] that names no other member.
String _fieldFor(
  ClassDeclaration owner,
  String eventName,
  Map<String, ({String id, bool map})> added,
) {
  final words = eventName.split(RegExp('[^A-Za-z0-9]+'))
    ..removeWhere((word) => word.isEmpty);
  var field = [
    if (words.isNotEmpty)
      words.first[0].toLowerCase() + words.first.substring(1),
    for (final word in words.skip(1)) word[0].toUpperCase() + word.substring(1),
  ].join();
  if (field.isEmpty || RegExp('^[0-9]').hasMatch(field)) field = 'event$field';
  if (_reservedWords.contains(field)) field = '${field}Event';
  final members = _memberNames(owner);
  // The same event again reuses its field.
  bool taken(String name) =>
      members.contains(name) ||
      added.containsKey(name) && added[name]!.id != eventName;
  var suffixes = 0;
  while (taken('$field${'Event' * suffixes}')) {
    suffixes++;
  }
  return '$field${'Event' * suffixes}';
}

Set<String> _memberNames(ClassDeclaration owner) => {
  if (owner.body case final BlockClassBody body)
    for (final member in body.members)
      ...switch (member) {
        FieldDeclaration(:final fields) => [
          for (final variable in fields.variables) variable.name.lexeme,
        ],
        MethodDeclaration(:final name) => [name.lexeme],
        _ => const <String>[],
      },
};

const _reservedWords = {
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', //
  'default', 'do', 'else', 'enum', 'extends', 'false', 'final', 'finally',
  'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return', 'super',
  'switch', 'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with',
};

// The removed helpers, called without a receiver, except a name the app
// declares itself.
final class _HelperCalls extends RecursiveAstVisitor<void> {
  _HelperCalls({required this.shadowed});

  final Set<String> shadowed;
  final List<MethodInvocation> found = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (node.target == null &&
        _helpers.contains(name) &&
        !shadowed.contains(name)) {
      found.add(node);
    }
    super.visitMethodInvocation(node);
  }
}

// The names of the functions and methods a library declares.
final class _DeclaredFunctions extends RecursiveAstVisitor<void> {
  final Set<String> names = {};

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    names.add(node.name.lexeme);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    names.add(node.name.lexeme);
    super.visitMethodDeclaration(node);
  }
}
