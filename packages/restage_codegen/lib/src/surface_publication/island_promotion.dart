import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/islands/islands.dart';

/// Where a promoted widget's name goes in [IslandPromotion] sources.
const kPromotedNameHole = '{{name}}';

/// How to turn an island into a widget class of the app's own: the source to
/// replace in [file], the class to add after it, and the call that replaces
/// it, both naming the class [kPromotedNameHole].
final class IslandPromotion {
  /// Creates a plan.
  const IslandPromotion({
    required this.file,
    required this.offset,
    required this.original,
    required this.classSource,
    required this.callSource,
  });

  /// The package-relative file the island is written in.
  final String file;

  /// Where the island's source starts in [file].
  final int offset;

  /// The island's source as the build read it.
  final String original;

  /// The widget class.
  final String classSource;

  /// The call that replaces [original].
  final String callSource;

  /// The JSON form.
  Map<String, Object?> toJson() => {
    'file': file,
    'offset': offset,
    'original': original,
    'class': classSource,
    'call': callSource,
  };
}

/// The plan that promotes [island], or the sentence saying why it can't be.
({IslandPromotion? plan, String? refusal}) planIslandPromotion(Island island) {
  final node = island.node;
  final unit = node.root;
  final contents = unit is CompilationUnit
      ? unit.declaredFragment?.source.contents.data
      : null;
  final library = unit is CompilationUnit
      ? unit.declaredFragment?.element.firstFragment
      : null;
  if (contents == null || library == null || node is! Expression) {
    return (
      plan: null,
      refusal: _refusal(island, "Restage can't read its source"),
    );
  }
  for (final name in const [
    'StatelessWidget',
    'Widget',
    'BuildContext',
    'RestageWidget',
  ]) {
    if (library.scope.lookup(name).getter == null) {
      return (
        plan: null,
        refusal: _refusal(island, "${_file(island)} doesn't import `$name`"),
      );
    }
  }
  final collector = _Reads(island, library);
  node.accept(collector);
  if (collector.blocker case final blocker?) {
    return (plan: null, refusal: _refusal(island, blocker));
  }
  final edits = <(int, int, String)>[...collector.edits];
  final fields = <String>[];
  final arguments = <String>[];
  String text(AstNode n) => contents.substring(n.offset, n.end);
  for (final read in collector.reads.values) {
    fields.add('final ${read.type} ${read.name};');
    arguments.add('${read.name}: ${read.source}');
  }
  final named = node is InstanceCreationExpression
      ? node.argumentList.arguments.whereType<NamedArgument>().toList()
      : const <NamedArgument>[];
  for (final slot in island.slots) {
    fields.add('final ${slot.list ? 'List<Widget>' : 'Widget'} ${slot.name};');
    arguments.add('${slot.name}: ${text(slot.node)}');
    edits.add((slot.node.offset, slot.node.end, slot.name));
  }
  for (final property in island.properties) {
    final argument = named
        .where((a) => a.name.lexeme == property.name)
        .firstOrNull;
    final type = switch (argument?.correspondingParameter?.type) {
      final type? => _spell(type, library),
      null => null,
    };
    if (argument == null || type == null) {
      return (
        plan: null,
        refusal: _refusal(
          island,
          "${_file(island)} can't name the type of `${property.name}`",
        ),
      );
    }
    fields.add('final $type ${property.name};');
    arguments.add('${property.name}: ${text(argument.argumentExpression)}');
    edits.add((
      argument.argumentExpression.offset,
      argument.argumentExpression.end,
      property.name,
    ));
  }
  // The key moves to the new widget, so its element keeps its identity.
  final key = named.where((a) => a.name.lexeme == 'key').firstOrNull;
  if (key != null) {
    final index = named.indexOf(key);
    final end = index + 1 < named.length ? named[index + 1].offset : key.end;
    edits.add((key.offset, end, ''));
    arguments.insert(0, 'key: ${text(key.argumentExpression)}');
  }
  edits.sort((a, b) => b.$1.compareTo(a.$1));
  var body = text(node);
  for (final (start, end, replacement) in edits) {
    body = body.replaceRange(
      start - node.offset,
      end - node.offset,
      replacement,
    );
  }
  final parameters = [
    'super.key',
    for (final field in fields)
      'required this.${field.split(' ').last}'.replaceAll(';', ''),
  ];
  final owner = [
    node.thisOrAncestorOfType<ClassDeclaration>()?.namePart.typeName.lexeme,
    node.thisOrAncestorOfType<MethodDeclaration>()?.name.lexeme,
  ].nonNulls.join('.');
  final classSource = [
    '/// The `${island.widget}` moved out of `$owner`. Describe what this '
        'widget shows.',
    '@RestageWidget()',
    'class $kPromotedNameHole extends StatelessWidget {',
    '  const $kPromotedNameHole({${parameters.join(', ')}});',
    for (final field in fields) ...[
      '  /// Describe `${field.split(' ').last.replaceAll(';', '')}`.',
      '  $field',
    ],
    '',
    '  @override',
    '  Widget build(BuildContext context) => $body;',
    '}',
  ].join('\n');
  return (
    plan: IslandPromotion(
      file: island.location.replaceFirst(RegExp(r':\d+:\d+$'), ''),
      offset: node.offset,
      original: text(node),
      classSource: classSource,
      callSource: '$kPromotedNameHole(${arguments.join(', ')})',
    ),
    refusal: null,
  );
}

String _refusal(Island island, String because) =>
    "`restage widget promote` can't move `${island.widget}` "
    '(${island.location}) into a widget class of its own because $because. '
    'Try moving it by hand, or leaving it where it is.';

// The file of [island]'s location, such as lib/promo.dart.
String _file(Island island) =>
    island.location.replaceFirst(RegExp(r':\d+:\d+$'), '');

/// [type] as [library] spells it unprefixed, or null when it can't.
String? _spell(DartType type, LibraryFragment library) {
  final suffix = type.nullabilitySuffix.name == 'question' ? '?' : '';
  switch (type) {
    case InterfaceType(:final element, :final typeArguments):
      if (library.scope.lookup(element.name!).getter != element) return null;
      if (typeArguments.isEmpty) return '${element.name}$suffix';
      final spelled = [for (final t in typeArguments) _spell(t, library)];
      if (spelled.contains(null)) return null;
      return '${element.name}<${spelled.join(', ')}>$suffix';
    case FunctionType() || DynamicType() || VoidType():
      final display = type.getDisplayString();
      // Every name the function type writes must resolve unprefixed.
      final names = RegExp(r'[A-Z]\w*').allMatches(display).map((m) => m[0]!);
      return names.every((n) => library.scope.lookup(n).getter != null)
          ? display
          : null;
    default:
      return null;
  }
}

// The reads an island's code makes of its surface, which become parameters.
final class _Reads extends GeneralizingAstVisitor<void> {
  _Reads(this.island, this.library)
    : skipped = {
        for (final slot in island.slots) slot.node,
        if (island.node case InstanceCreationExpression(:final argumentList))
          for (final argument
              in argumentList.arguments.whereType<NamedArgument>())
            if (argument.name.lexeme == 'key' ||
                island.properties.any((p) => p.name == argument.name.lexeme))
              argument.argumentExpression,
      };

  final Island island;
  final LibraryFragment library;
  final Set<AstNode> skipped;
  final reads = <Element, ({String name, String type, String source})>{};
  final edits = <(int, int, String)>[];
  String? blocker;

  bool get _done => blocker != null;

  bool _inside(Element element) {
    final offset = element.firstFragment.nameOffset;
    final unit = island.node.root;
    return offset != null &&
        unit is CompilationUnit &&
        element.firstFragment.libraryFragment?.source ==
            unit.declaredFragment?.source &&
        offset >= island.node.offset &&
        offset < island.node.end;
  }

  void _block(AstNode node, String what) {
    if (_done) return;
    final unit = node.root;
    final at = unit is CompilationUnit
        ? unit.lineInfo.getLocation(node.offset)
        : null;
    final file = _file(island);
    blocker = at == null
        ? what
        : '$what ($file:${at.lineNumber}:${at.columnNumber})';
  }

  void _read(
    AstNode node,
    Element element,
    String name,
    DartType? type,
    String source,
  ) {
    if (type != null &&
        type.element?.name == 'BuildContext' &&
        type.element?.library?.identifier ==
            'package:flutter/src/widgets/framework.dart') {
      if (source != 'context') edits.add((node.offset, node.end, 'context'));
      return;
    }
    final spelled = type == null ? null : _spell(type, library);
    if (spelled == null) {
      _block(node, "${_file(island)} can't name the type of `$source`");
      return;
    }
    final read = reads[element] ??= (
      name: _parameterName(name),
      type: spelled,
      source: source,
    );
    if (read.name != source) edits.add((node.offset, node.end, read.name));
  }

  String _parameterName(String name) {
    var base = name.replaceFirst(RegExp('^_+'), '');
    if (base.isEmpty || base == 'key' || base == 'context') base = 'value';
    final taken = {
      for (final read in reads.values) read.name,
      for (final slot in island.slots) slot.name,
      for (final property in island.properties) property.name,
    };
    var candidate = base;
    for (var i = 2; taken.contains(candidate); i++) {
      candidate = '$base$i';
    }
    return candidate;
  }

  @override
  void visitNode(AstNode node) {
    if (_done || skipped.contains(node)) return;
    switch (node) {
      case ThisExpression():
        _block(node, 'it uses `this`');
      case SuperExpression():
        _block(node, 'it uses `super`');
      case AssignmentExpression(:final writeElement?)
          when isInstanceMember(writeElement) || !_inside(writeElement):
        _block(node, 'it assigns `${node.toSource()}`');
      case MethodInvocation(target: null, :final methodName)
          when methodName.element != null &&
              isInstanceMember(methodName.element!):
        _block(node, 'it calls `${methodName.name}`');
      case PrefixedIdentifier(:final prefix, :final identifier)
          when prefix.name == 'widget' && _isStateWidget(prefix.element):
        // `widget.x` of a `State` reads the widget's field.
        if (identifier.element case final field?) {
          _read(node, field, identifier.name, node.staticType, node.toSource());
        } else {
          _block(node, 'it reads `${node.toSource()}`');
        }
      case SimpleIdentifier():
        _identifier(node);
      default:
        node.visitChildren(this);
    }
  }

  void _identifier(SimpleIdentifier node) {
    if (node.inDeclarationContext() || _selector(node)) return;
    final raw = node.element;
    if (raw == null) return;
    final element = raw is PropertyAccessorElement ? raw.variable : raw;
    if (_inside(element)) return;
    switch (element) {
      case LocalVariableElement(:final type) ||
          FormalParameterElement(:final type):
        _read(node, element, node.name, type, node.name);
      case _ when node.name == 'widget' && _isStateWidget(raw):
        _block(node, 'it reads `widget`');
      case _ when isInstanceMember(element):
        _read(node, element, node.name, node.staticType, node.name);
      default:
        break;
    }
  }
}

bool _isStateWidget(Element? element) =>
    element is PropertyAccessorElement &&
    element.name == 'widget' &&
    element.enclosingElement is ClassElement &&
    element.enclosingElement.name == 'State';

bool _selector(SimpleIdentifier identifier) => switch (identifier.parent) {
  ConstructorName(:final name) when identical(name, identifier) => true,
  MethodInvocation(:final methodName, :final target)
      when identical(methodName, identifier) && target != null =>
    true,
  PrefixedIdentifier(identifier: final selector)
      when identical(selector, identifier) =>
    true,
  PropertyAccess(:final propertyName)
      when identical(propertyName, identifier) =>
    true,
  Label() => true,
  _ => false,
};
