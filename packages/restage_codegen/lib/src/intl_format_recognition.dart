import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_codegen/src/const_folding.dart';
import 'package:restage_codegen/src/temporal_expression_lowering.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/installed_native_provenance.dart';
import 'package:restage_shared/restage_shared.dart';

bool _intlMember(Element? element, String owner) =>
    element?.enclosingElement?.name == owner &&
    (element?.library?.identifier.startsWith('package:intl/') ?? false);
bool _dateTimeMember(Element? element) =>
    element?.enclosingElement?.name == 'DateTime' &&
    element?.library?.identifier == 'dart:core';

/// Broad recognition; the lowering below owns exact argument validation.
bool containsIntlFormatting(
  Expression expression, {
  Map<Element, HelperDef> helpers = const {},
}) {
  final visitor = _FormattingVisitor(helpers);
  expression.accept(visitor);
  return visitor.found;
}

/// Detects translation calls before mount-time scalar hoisting can consume them.
bool containsInstalledIntlTranslation(
  Expression expression, {
  Map<Element, HelperDef> helpers = const {},
}) {
  final visitor = _FormattingVisitor(helpers);
  expression.accept(visitor);
  return visitor.installedTranslation;
}

final class _FormattingVisitor extends RecursiveAstVisitor<void> {
  _FormattingVisitor(this.helpers);
  final Map<Element, HelperDef> helpers;
  final Set<Element> active = {};
  bool found = false;
  bool installedTranslation = false;
  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (isTemporalValueExpression(node)) found = true;
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (isTemporalValueExpression(node)) found = true;
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (isTemporalValueExpression(node)) found = true;
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (isTemporalValueExpression(node)) found = true;
    super.visitBinaryExpression(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    if (isInstalledIntlTranslation(node)) installedTranslation = true;
    if (installedIntlLookupFamily(
          installedNativeFixedInvocation(node)?.target,
        ) !=
        null) {
      found = true;
    }
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (isInstalledIntlTranslation(node)) installedTranslation = true;
    if (isTemporalValueExpression(node)) found = true;
    final member = node.methodName.element;
    if (installedIntlLookupFamily(
              installedNativeFixedInvocation(node)?.target,
            ) !=
            null ||
        node.methodName.name == 'format' &&
            (_intlMember(member, 'DateFormat') ||
                _intlMember(member, 'NumberFormat'))) {
      found = true;
    }
    final helper = helpers[member];
    if (helper != null && member != null && active.add(member)) {
      for (final root in helper.roots) root.accept(this);
      active.remove(member);
    }
    super.visitMethodInvocation(node);
  }
}

/// Translation lookup is available only through a fixed installed call site.
/// The compiled call retains all arguments, including extraction metadata and
/// fallback expressions, so native Dart owns their evaluation order and errors.
bool isInstalledIntlTranslation(Expression expression) {
  final invocation = installedNativeFixedInvocation(expression);
  final family = installedIntlLookupFamily(invocation?.target);
  if (invocation == null || family == null) return false;
  return family == 'message' ||
      invocation.arguments.arguments.whereType<NamedArgument>().any((argument) {
        final key = argument.name.lexeme;
        final value = argument.argumentExpression;
        if (key == 'meaning') {
          return installedNativeConstantValue(value)?.isNull != true;
        }
        return const {'name', 'args'}.contains(key) && value is! NullLiteral;
      });
}

/// Validates lookup metadata for already-qualified fixed invocation targets.
Map<Expression, String?> validateInstalledIntlInvocations(
  Iterable<InstalledNativeInvocation> invocations,
) {
  final constantStrings = <Expression, String?>{};
  for (final invocation in invocations) {
    final family = installedIntlLookupFamily(invocation.target);
    if (family != null) {
      _validateInstalledIntlCall(invocation.arguments, family, constantStrings);
    }
  }
  return constantStrings;
}

/// Closes lookup authority for callers without native input bindings.
Map<Expression, String?> validateInstalledIntlTranslation(
  MethodInvocation expression,
) => validateInstalledIntlInvocations(
  qualifyInstalledNativeCallables(expression, isDeclaredCallable: (_) => false),
);

void _validateInstalledIntlCall(
  ArgumentList arguments,
  String family,
  Map<Expression, String?> constantStrings,
) {
  String? fixed(Expression value, {bool allowNull = true}) {
    final constant = installedNativeConstantValue(value);
    final result = constant?.toStringValue();
    if (result is String) return constantStrings[value] = result;
    if (allowNull && constant?.isNull == true)
      return constantStrings[value] = null;
    throw BuilderLoweringException(
      value,
      'Intl translation lookup requires a fixed constant name',
    );
  }

  String? name;
  Expression? meaning;
  for (final argument in arguments.arguments.whereType<NamedArgument>()) {
    final value = argument.argumentExpression;
    if (argument.name.lexeme == 'name') {
      name = fixed(value);
    }
    if (argument.name.lexeme == 'meaning') meaning = value;
    if (argument.name.lexeme == 'args') {
      var args = value;
      while (args is ParenthesizedExpression) {
        args = args.expression;
      }
      if (installedNativeConstantValue(value)?.isNull == true) {
        constantStrings[value] = null;
      } else if (args is! ListLiteral ||
          args.elements.any((element) => element is! Expression)) {
        throw BuilderLoweringException(
          value,
          'Intl translation arguments require a fixed typed argument list',
        );
      }
    }
  }
  // Intl uses message text plus meaning as its lookup key when name is empty
  // or null. Fix those operands too, closing that payload-selected lookup path.
  if (name == null || name.isEmpty) {
    if (family == 'message') {
      final text = arguments.arguments.firstWhere(
        (argument) => argument is! NamedArgument,
      );
      fixed(text.argumentExpression, allowNull: false);
    }
    if (meaning != null) fixed(meaning);
  }
}

/// Extends the shared typed expression lowerer with resolved native operations.
int? lowerIntlValue(
  Expression expression,
  BuilderExpressionLowering lowerer, {
  Expression Function(Expression)? resolve,
}) {
  final temporal = lowerTemporalValue(expression, lowerer);
  if (temporal != null) return temporal;
  final e = expression;
  int literal(Object? value, ValueType type) =>
      lowerer.add(ValueNode('literal', type, value: value));
  int add(String op, ValueType type, List<int> inputs, [Object? options]) =>
      lowerer.add(ValueNode(op, type, inputs: inputs, value: options));
  Never refuse(AstNode node, String reason) =>
      throw BuilderLoweringException(node, reason);
  // Native operations consume formal positions after lexical argument evaluation.
  int afterArguments(List<int> eager, int result) {
    for (final node in eager.reversed) {
      result = add('let', lowerer.nodes[result].type, [node, result]);
    }
    return result;
  }

  List<(String, Expression)> namedArguments(
    ArgumentList arguments,
    List<String> positionalNames,
    Set<String> namedNames,
  ) {
    final result = <(String, Expression)>[];
    var position = 0;
    for (final argument in arguments.arguments) {
      if (argument is NamedArgument) {
        final name = argument.name.lexeme;
        if (!namedNames.contains(name))
          refuse(argument, 'Unsupported native intl argument $name');
        result.add((name, argument.argumentExpression));
      } else {
        if (position >= positionalNames.length)
          refuse(argument, 'Too many native intl arguments');
        result.add((positionalNames[position++], argument.argumentExpression));
      }
    }
    return result;
  }

  int dateMethod(MethodInvocation call, int target) {
    final name = call.methodName.name;
    if (name == 'addPattern') {
      final args = call.argumentList.arguments;
      if (args.isEmpty ||
          args.length > 2 ||
          args.any((a) => a is NamedArgument)) {
        refuse(call, 'Unsupported DateFormat.addPattern arguments');
      }
      return add('intl.date.add', dateFormatterValueType, [
        target,
        lowerer.lower(args[0].argumentExpression),
        args.length == 2
            ? lowerer.lower(args[1].argumentExpression)
            : literal(' ', ValueType.string),
      ]);
    }
    if (name.startsWith('add_') &&
        dateFormatSkeletons.contains(name.substring(4)) &&
        call.argumentList.arguments.isEmpty) {
      return add('intl.date.add', dateFormatterValueType, [
        target,
        literal(name.substring(4), ValueType.string),
        literal(' ', ValueType.string),
      ]);
    }
    return refuse(call, 'Unsupported DateFormat mutation');
  }

  int numberMethod(MethodInvocation call, int target) {
    if (call.methodName.name == 'turnOffGrouping' &&
        call.argumentList.arguments.isEmpty) {
      return add('intl.number.noGrouping', numberFormatterValueType, [target]);
    }
    return refuse(call, 'Unsupported NumberFormat mutation');
  }

  if (e is StringInterpolation &&
      e.elements.whereType<InterpolationExpression>().any(
        (part) => _enumIdentity(part.expression.staticType) != null,
      )) {
    final parts = <int>[];
    for (final part in e.elements) {
      if (part is InterpolationString) {
        parts.add(literal(part.value, ValueType.string));
      } else if (part is InterpolationExpression) {
        final type = part.expression.staticType;
        final identity = _enumIdentity(type);
        if (identity != null && _customEnumString(type)) {
          refuse(
            part,
            'A custom enum String conversion requires a native binding',
          );
        }
        final input = lowerer.lower(part.expression);
        final string = add('string', ValueType.string, [input]);
        if (identity == null) {
          parts.add(string);
        } else {
          final formatted = add('concat', ValueType.string, [
            literal('${identity.split('#').last}.', ValueType.string),
            string,
          ]);
          if (lowerer.nodes[input].type.nullable) {
            final absent = add('==', ValueType.boolean, [
              input,
              literal(null, ValueType.nullType),
            ]);
            parts.add(
              add('conditional', ValueType.string, [
                absent,
                literal('null', ValueType.string),
                formatted,
              ]),
            );
          } else {
            parts.add(formatted);
          }
        }
      }
    }
    return add('concat', ValueType.string, parts);
  }
  if (e is InstanceCreationExpression) {
    final ctor = e.constructorName.element;
    final spelling = e.constructorName.name?.name ?? '';
    final name = spelling == 'new' ? '' : spelling;
    if (_intlMember(ctor, 'DateFormat')) {
      if (name.isNotEmpty && !dateFormatSkeletons.contains(name))
        refuse(e, 'Unsupported DateFormat constructor');
      final args = namedArguments(
        e.argumentList,
        name.isEmpty ? ['pattern', 'locale'] : ['locale'],
        {},
      );
      return add(
        'intl.date.new',
        dateFormatterValueType,
        [
          if (name.isNotEmpty) literal(name, ValueType.string),
          for (final (_, arg) in args) lowerer.lower(arg),
        ],
        {
          'arguments': [
            if (name.isNotEmpty) 'pattern',
            for (final (key, _) in args) key,
          ],
        },
      );
    }
    if (_intlMember(ctor, 'NumberFormat')) {
      final types = numberFormatArguments[name];
      if (types == null) refuse(e, 'Unsupported NumberFormat constructor');
      final positional = switch (name) {
        '' => ['pattern', 'locale'],
        'decimalPattern' ||
        'percentPattern' ||
        'scientificPattern' => ['locale'],
        'currencyPattern' => ['locale', 'name'],
        _ => <String>[],
      };
      final args = namedArguments(
        e.argumentList,
        positional,
        positional.isEmpty ? types.keys.toSet() : {},
      );
      return add(
        'intl.number.new',
        numberFormatterValueType,
        [for (final (_, arg) in args) lowerer.lower(arg)],
        {
          'constructor': name,
          'arguments': [for (final (key, _) in args) key],
        },
      );
    }
    if (_dateTimeMember(ctor)) {
      if (name == 'now') return null;
      if (!const {
        '',
        'utc',
        'fromMillisecondsSinceEpoch',
        'fromMicrosecondsSinceEpoch',
      }.contains(name)) {
        return refuse(e, 'Unsupported native DateTime constructor');
      }
      final positional = switch (name) {
        '' || 'utc' => [
          'year',
          'month',
          'day',
          'hour',
          'minute',
          'second',
          'millisecond',
          'microsecond',
        ],
        _ => ['epoch'],
      };
      final args = namedArguments(
        e.argumentList,
        positional,
        name.startsWith('from') ? {'isUtc'} : {},
      );
      if (name.startsWith('from')) {
        final eager = <int>[];
        final bound = <String, int>{};
        for (final (key, argument) in args) {
          final node = lowerer.lower(argument);
          eager.add(node);
          bound[key] = node;
        }
        final epoch = bound['epoch'];
        if (epoch == null) refuse(e, 'DateTime epoch requires its value');
        return afterArguments(
          eager,
          add(
            'intl.datetime.new',
            dateTimeValueType,
            [
              epoch,
              if (bound['isUtc'] case final node?) node,
            ],
            {
              'constructor': name,
              'arguments': [if (bound.containsKey('isUtc')) 'isUtc'],
            },
          ),
        );
      }
      return add(
        'intl.datetime.new',
        dateTimeValueType,
        [for (final (_, arg) in args) lowerer.lower(arg)],
        {
          'constructor': name,
          'arguments': <String>[],
        },
      );
    }
  }
  if (e is CascadeExpression) {
    final staticType = e.target.staticType;
    final type = staticType is InterfaceType ? staticType.element : null;
    final date =
        type != null &&
        type.name == 'DateFormat' &&
        type.library.identifier.startsWith('package:intl/');
    final number =
        type != null &&
        type.name == 'NumberFormat' &&
        type.library.identifier.startsWith('package:intl/');
    if (!date && !number) return null;
    if (!_nonescapingFormatter(e.target))
      refuse(e, 'Formatter mutation requires a nonescaping constructor recipe');
    var target = lowerer.lower(e.target);
    for (final section in e.cascadeSections) {
      if (section is MethodInvocation) {
        final native = _intlMember(
          section.methodName.element,
          date ? 'DateFormat' : 'NumberFormat',
        );
        if (!native) refuse(section, 'Unsupported formatter cascade call');
        target = date
            ? dateMethod(section, target)
            : numberMethod(section, target);
      } else if (section is AssignmentExpression &&
          section.operator.lexeme == '=') {
        final left = section.leftHandSide;
        if (left is! PropertyAccess)
          refuse(section, 'Unsupported formatter assignment');
        final name = left.propertyName.name;
        if (!_intlMember(
          section.writeElement,
          date ? 'DateFormat' : 'NumberFormat',
        )) {
          refuse(section, 'Unsupported formatter assignment');
        }
        if (date && name == 'useNativeDigits') {
          target = add('intl.date.digits', dateFormatterValueType, [
            target,
            lowerer.lower(section.rightHandSide),
          ]);
        } else if (number && numberFormatSetters.containsKey(name)) {
          target = add(
            'intl.number.set',
            numberFormatterValueType,
            [target, lowerer.lower(section.rightHandSide)],
            {'setter': name},
          );
        } else {
          refuse(section, 'Unsupported formatter assignment $name');
        }
      } else {
        refuse(section, 'Unsupported formatter cascade');
      }
    }
    return target;
  }
  if (e is! MethodInvocation) return null;
  final member = e.methodName.element;
  final name = e.methodName.name;
  if ((_intlMember(member, 'DateFormat') ||
          _intlMember(member, 'NumberFormat')) &&
      e.target != null) {
    final date = _intlMember(member, 'DateFormat');
    final target = lowerer.lower(e.target!);
    if (name == 'format' &&
        e.argumentList.arguments.length == 1 &&
        e.argumentList.arguments.single is! NamedArgument) {
      return add(
        date ? 'intl.date.format' : 'intl.number.format',
        ValueType.string,
        [
          target,
          lowerer.lower(e.argumentList.arguments.single.argumentExpression),
        ],
      );
    }
    if (!_nonescapingFormatter(e.target!))
      refuse(e, 'Formatter mutation requires a nonescaping constructor recipe');
    return date ? dateMethod(e, target) : numberMethod(e, target);
  }
  if (_dateTimeMember(member) &&
      name == 'parse' &&
      member is MethodElement &&
      member.isStatic) {
    final args = namedArguments(e.argumentList, ['source'], {});
    if (args.length != 1) refuse(e, 'Unsupported DateTime.parse arguments');
    return add(
      'intl.datetime.new',
      dateTimeValueType,
      [lowerer.lower(args.single.$2)],
      {'constructor': 'parse', 'arguments': <String>[]},
    );
  }
  if (_dateTimeMember(member) &&
      const {'toUtc', 'toLocal'}.contains(name) &&
      e.target != null &&
      e.argumentList.arguments.isEmpty) {
    return add(
      'intl.datetime.zone',
      dateTimeValueType,
      [lowerer.lower(e.target!)],
      {'utc': name == 'toUtc'},
    );
  }
  if (!_intlMember(member, 'Intl') ||
      !const {'plural', 'gender', 'select'}.contains(name))
    return null;
  final arguments = e.argumentList.arguments;
  final positional = arguments.where((a) => a is! NamedArgument).toList();
  if (positional.length != (name == 'select' ? 2 : 1))
    refuse(e, 'Unsupported Intl.$name arguments');
  final eager = <int>[];
  int stage(Expression argument) {
    final node = lowerer.lower(argument);
    eager.add(node);
    return node;
  }

  int? choice;
  final keys = <Object>[];
  final casesInputs = <int>[];
  final named = <String>[];
  final namedInputs = <int>[];
  for (final argument in arguments) {
    if (argument is NamedArgument) {
      final key = argument.name.lexeme;
      final value = argument.argumentExpression;
      if (key == 'name' || key == 'args') {
        if (value is! NullLiteral)
          refuse(
            argument,
            'Named translated messages require a declared native binding',
          );
        continue;
      }
      if (const {'desc', 'examples', 'skip'}.contains(key)) {
        if (!_inertMetadata(value))
          refuse(argument, 'Intl extraction metadata must be inert');
        continue;
      }
      if (key == 'meaning') {
        if (installedNativeConstantValue(value)?.isNull != true) {
          refuse(
            value,
            'Translated Intl meaning requires a declared native binding',
          );
        }
        final node = literal(null, ValueType.nullType);
        eager.add(node);
        named.add(key);
        namedInputs.add(node);
        continue;
      }
      named.add(key);
      namedInputs.add(stage(value));
    } else if (identical(argument, positional.first)) {
      choice = stage(argument.argumentExpression);
    } else {
      final rawCases = argument.argumentExpression;
      final cases = resolve?.call(rawCases) ?? rawCases;
      if (cases is! SetOrMapLiteral || !cases.isMap)
        refuse(cases, 'Intl.select requires an enumerable cases map');
      for (final element in cases.elements) {
        if (element is! MapLiteralEntry)
          refuse(element, 'Unsupported Intl.select cases collection');
        final key = tryFoldConstant(element.key) ?? _enumKey(element.key);
        if (!isIntlSelectKey(key))
          refuse(element.key, 'Intl.select requires constant scalar keys');
        keys.add(key!);
        casesInputs.add(stage(element.value));
      }
      if (!keys.contains('other'))
        refuse(cases, 'Intl.select requires an other case');
    }
  }
  final choiceType = positional.first.argumentExpression.staticType;
  if (name == 'select' && _customEnumString(choiceType)) {
    refuse(
      e,
      'An enum with a custom toString requires a native message binding',
    );
  }
  final choiceEnum = _enumIdentity(choiceType);
  return afterArguments(
    eager,
    add(
      'intl.$name',
      ValueType.string,
      [choice!, ...casesInputs, ...namedInputs],
      {
        'arguments': named,
        if (name == 'select') 'keys': keys,
        if (name == 'select' && choiceEnum != null) 'choiceEnum': choiceEnum,
      },
    ),
  );
}

bool _inertMetadata(Expression value) {
  if (value is NullLiteral || tryFoldConstant(value) != null) return true;
  if (value is ListLiteral)
    return value.elements.every((e) => e is Expression && _inertMetadata(e));
  if (value is SetOrMapLiteral && value.isMap) {
    return value.elements.every(
      (e) =>
          e is MapLiteralEntry &&
          _inertMetadata(e.key) &&
          _inertMetadata(e.value),
    );
  }
  return false;
}

String? _enumIdentity(DartType? type) =>
    type is InterfaceType && type.element is EnumElement
    ? '${type.element.library.identifier}#${type.element.name}'
    : null;

Map<String, Object?>? _enumKey(Expression expression) {
  Element? element = switch (expression) {
    SimpleIdentifier() => expression.element,
    PrefixedIdentifier() => expression.identifier.element,
    PropertyAccess() => expression.propertyName.element,
    _ => null,
  };
  if (element is PropertyAccessorElement) element = element.variable;
  if (element is! FieldElement || !element.isEnumConstant) return null;
  final identity = _enumIdentity(expression.staticType);
  return identity == null ? null : {'enum': identity, 'name': element.name};
}

/// Resolved native values are composable; strict admission stays in lowering.
bool isIntlValueExpression(Expression expression) {
  if (isTemporalValueExpression(expression)) return true;
  if (expression is InstanceCreationExpression) {
    final element = expression.constructorName.element;
    return _intlMember(element, 'DateFormat') ||
        _intlMember(element, 'NumberFormat') ||
        _dateTimeMember(element) &&
            expression.constructorName.name?.name != 'now';
  }
  if (expression is MethodInvocation) {
    final element = expression.methodName.element;
    return _intlMember(element, 'DateFormat') ||
        _intlMember(element, 'NumberFormat') ||
        _intlMember(element, 'Intl') &&
            const {
              'message',
              'plural',
              'gender',
              'select',
            }.contains(expression.methodName.name) ||
        _dateTimeMember(element) &&
            const {
              'parse',
              'toUtc',
              'toLocal',
            }.contains(expression.methodName.name);
  }
  return expression is CascadeExpression &&
      isIntlValueExpression(expression.target);
}

bool _nonescapingFormatter(Expression value) => switch (value) {
  ParenthesizedExpression() => _nonescapingFormatter(value.expression),
  InstanceCreationExpression() =>
    _intlMember(value.constructorName.element, 'DateFormat') ||
        _intlMember(value.constructorName.element, 'NumberFormat'),
  CascadeExpression() => _nonescapingFormatter(value.target),
  MethodInvocation(:final target?) => _nonescapingFormatter(target),
  _ => false,
};

/// Whether a resolved value holds native formatter state.
bool isNativeIntlFormatterType(DartType? type) =>
    type is InterfaceType &&
    const {'DateFormat', 'NumberFormat'}.contains(type.element.name) &&
    type.element.library.identifier.startsWith('package:intl/');

bool _customEnumString(DartType? type) {
  if (type is! InterfaceType || type.element is! EnumElement) return false;
  final method = type.element.lookUpMethod(
    name: 'toString',
    library: type.element.library,
  );
  return method != null &&
      method.isOriginDeclaration &&
      method.library.identifier != 'dart:core';
}
