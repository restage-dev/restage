import 'dart:convert';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_shared/restage_shared.dart';

import 'builder_expression_lowering.dart';
import 'emit_utils.dart';
import 'hoisting.dart';
import 'installed_native_provenance.dart';
import 'intl_format_recognition.dart' show validateInstalledIntlInvocations;
import 'owning_library_namespace.dart';

/// Validation uses the same installed declarations emitted into the mount.
Map<String, ValueOperation> installedNativeCallOperations(
  Iterable<HoistedValue> hoisted,
) => nativeCallOperations(
  SurfaceScreenHostDataSchema({
    for (final value in hoisted)
      if (value.nativeContract case final contract?)
        value.key: SurfaceScreenHostDataNativeBindingShapeV1(contract),
  }),
  kStandardValueOperations,
);

/// An existing lexical cell retained by an installed closure.
final class InstalledNativeCapture {
  const InstalledNativeCapture(this.slot, this.type);
  final String slot;
  final ValueType type;
}

/// A value evaluated before invoking an installed adapter.
final class InstalledNativeInput {
  const InstalledNativeInput(this.node, this.type);
  final int node;
  final ValueType type;
}

/// Compiled Dart and its closed evaluator declaration.
final class InstalledNativeCallPlan {
  InstalledNativeCallPlan._(
    this.source,
    this.resultDartType,
    this.resultType,
    this.inputs,
    this.captures,
    this._inputTypes,
    this._captureTypes,
    this._prefix,
    this.emissionLibraryIdentity,
    List<String> symbols,
  ) {
    final identity = crypto.sha256
        .convert(
          utf8.encode(
            jsonEncode({
              // Comments and layout do not change what the call is.
              'source': canonicalHoistSource(source),
              'result': resultDartType,
              'inputs': _inputTypes,
              'captures': _captureTypes,
              'symbols': symbols,
              'signature': {
                'inputs': inputs.map((input) => input.type.toJson()).toList(),
                'captures': captures.map(
                  (name, capture) => MapEntry(name, capture.type.toJson()),
                ),
                'result': resultType.toJson(),
              },
            }),
          ),
        )
        .toString();
    contract = NativeBindingContract(
      type: 'installed.call',
      call: NativeCallContract(
        inputs: inputs.map((input) => input.type).toList(),
        captures: captures.map((name, capture) => MapEntry(name, capture.type)),
        result: resultType,
        implementation: identity,
      ),
    );
    key = '_h${identity.substring(0, 10)}';
  }

  final String source;
  final String emissionLibraryIdentity;
  final String _prefix;
  final String resultDartType;
  final ValueType resultType;
  final List<InstalledNativeInput> inputs;
  final Map<String, InstalledNativeCapture> captures;
  final List<String> _inputTypes;
  final Map<String, String> _captureTypes;
  late final NativeBindingContract contract;
  late final String key;

  ValueNode get node => ValueNode(
    'native.call',
    resultType,
    inputs: inputs.map((input) => input.node).toList(),
    value: {
      'binding': key,
      'contract': contract.toJson(),
      'captures': captures.map((name, capture) => MapEntry(name, capture.slot)),
    },
  );

  /// Creates only the adapter; its body executes at the expression node.
  /// [declaration] names an already-declared contract to share.
  String adapterSource({
    required String core,
    required String shared,
    String? declaration,
  }) {
    declaration ??= nativeContractSource(contract, shared);
    final buffer = StringBuffer(
      '${core}NativeCallAdapter($declaration, '
      '(${_prefix}Inputs, ${_prefix}Cells) {',
    );
    if (inputs.isNotEmpty || source.contains('${_prefix}As<')) {
      buffer.write('T ${_prefix}As<T>(Object? value) => value as T;');
    }
    for (var i = 0; i < inputs.length; i++) {
      final type = inputs[i].type;
      final read = type.kind == 'native'
          ? '(${_prefix}Inputs[$i] as ${shared}ValueNative).value'
          : '${_prefix}Inputs[$i]';
      final nullableRead = type.kind == 'native' && type.nullable
          ? '(${_prefix}Inputs[$i] == null ? null : $read)'
          : read;
      buffer.write(
        'final ${_inputTypes[i]} ${_prefix}Input$i = ${_prefix}As<${_inputTypes[i]}>($nullableRead);',
      );
    }
    for (final capture in captures.keys) {
      buffer.write(
        'final $capture = ${_prefix}Cells[${_dartJson(capture)}]!'
        '.cast<${_captureTypes[capture]}>();',
      );
    }
    buffer.write('final $resultDartType ${_prefix}Result = $source;');
    if (resultType.kind == 'native') {
      if (resultType.nullable)
        buffer.write('if (${_prefix}Result == null) return null;');
      buffer.write(
        'return ${core}NativeBinding<$resultDartType>('
        'contract: ${shared}NativeBindingContract('
        'type: ${_dartJson(resultType.nativeType)}, nullable: ${resultType.nullable}), '
        'value: ${_prefix}Result);',
      );
    } else {
      buffer.write('return ${_prefix}Result;');
    }
    return '$buffer})';
  }

  /// The value this plan installs, first written at [location].
  HoistedValue bindingAt(String? location) => HoistedValue(
    key: key,
    label: source,
    kind: HoistValueKind.nativeBinding,
    shape: SurfaceScreenHostDataNativeBindingShapeV1(contract),
    template: '',
    nativeContract: contract,
    nativeCall: this,
    location: location,
  );
}

/// Serializes declarations into ordinary generated Dart using visible prefixes.
String nativeContractSource(NativeBindingContract contract, String prefix) =>
    contract.call == null
    ? '${prefix}NativeBindingContract(type: ${dartStringLiteral(contract.type)}, nullable: ${contract.nullable})'
    : '${prefix}NativeBindingContract.fromJson(${_dartJson(contract.toJson())})';

/// The nominal result of constructors admitted by the native value boundary.
String? installedNativeConstructorType(Expression expression) {
  if (expression is! InstanceCreationExpression) return null;
  return _installedNativeConstructorType(
    expression.constructorName.element?.enclosingElement,
  );
}

/// The installed constructor family of a resolved canonical constant.
String? installedNativeConstantType(Expression expression) {
  final type = installedNativeConstantValue(expression)?.type;
  return type is InterfaceType
      ? _installedNativeConstructorType(type.element)
      : null;
}

String? _installedNativeConstructorType(InterfaceElement? owner) {
  if (owner == null) return null;
  return switch ((owner.library.identifier, owner.name)) {
    (
      'package:flutter/src/material/colors.dart',
      'MaterialColor' || 'MaterialAccentColor',
    ) =>
      'flutter.Color',
    ('package:flutter/src/widgets/framework.dart', 'ObjectKey') =>
      'flutter.Key',
    _ => null,
  };
}

/// Whether resolved source denotes a compiled constant or static tearoff.
bool isInstalledNativeConstant(Expression expression) =>
    installedNativeConstantValue(expression) != null;

/// Proves that eager input borrowing cannot change selection observables.
bool isInertNativeSelection(
  Expression expression, {
  required bool Function(Expression) isBorrowedRead,
}) {
  bool inert(Expression value) {
    if (value is ParenthesizedExpression) return inert(value.expression);
    if (value is FunctionExpression) return false;
    if (isInstalledNativeConstant(value) || isBorrowedRead(value)) return true;
    bool boolean(Expression operand) =>
        operand.staticType?.isDartCoreBool == true &&
        operand.staticType?.nullabilitySuffix == NullabilitySuffix.none &&
        inert(operand);
    if (value is ConditionalExpression) {
      return boolean(value.condition) &&
          inert(value.thenExpression) &&
          inert(value.elseExpression);
    }
    if (value is BinaryExpression) {
      return switch (value.operator.lexeme) {
        '??' => inert(value.leftOperand) && inert(value.rightOperand),
        '&&' ||
        '||' => boolean(value.leftOperand) && boolean(value.rightOperand),
        '==' || '!=' =>
          value.leftOperand is NullLiteral && inert(value.rightOperand) ||
              value.rightOperand is NullLiteral && inert(value.leftOperand),
        _ => false,
      };
    }
    if (value is PrefixExpression && value.operator.lexeme == '!') {
      return boolean(value.operand);
    }
    if (value is AsExpression) {
      final source = value.expression.staticType;
      final target = value.type.type;
      final library = (value.root as CompilationUnit).declaredFragment?.element;
      return source != null &&
          target != null &&
          source is! DynamicType &&
          target is! DynamicType &&
          source is! InvalidType &&
          target is! InvalidType &&
          library?.typeSystem.isSubtypeOf(source, target) == true &&
          inert(value.expression);
    }
    return false;
  }

  return inert(expression);
}

/// Retains the compiled canonical value of a constant expression.
HoistedValue installedNativeConstant(
  Expression expression, {
  required String type,
  LibraryElement? emissionLibrary,
  String? location,
}) {
  final constant = installedNativeConstantValue(expression);
  if (constant == null) {
    throw BuilderLoweringException(
      expression,
      'Native constant requires const source',
    );
  }
  final nullable =
      constant.isNull ||
      expression.staticType?.nullabilitySuffix == NullabilitySuffix.question;
  final plan = planInstalledNativeCall(
    installedNativeConstantExpression(expression),
    resultType: ValueType.native(type, nullable: nullable),
    emissionLibrary: emissionLibrary,
    captureFor: (_) => null,
    inputFor: (_) => null,
  );
  final source = plan.source;
  final contract = NativeBindingContract(type: type, nullable: nullable);
  final identity = crypto.sha256.convert(utf8.encode('constant:${plan.key}'));
  return HoistedValue(
    key: '_h${identity.toString().substring(0, 10)}',
    label: source,
    kind: HoistValueKind.nativeBinding,
    shape: SurfaceScreenHostDataNativeBindingShapeV1(contract),
    template: source,
    nativeContract: contract,
    nativeConstant: plan,
    location: location,
  );
}

String _dartJson(Object? value) => switch (value) {
  Map() =>
    '<String, Object?>{${value.entries.map((entry) => '${_dartJson(entry.key)}: ${_dartJson(entry.value)}').join(', ')}}',
  List() => '<Object?>[${value.map(_dartJson).join(', ')}]',
  String() => jsonEncode(value).replaceAll(r'$', r'\$'),
  _ => '$value',
};

/// Plans one explicitly admitted native expression in its owning library.
InstalledNativeCallPlan planInstalledNativeCall(
  Expression expression, {
  required ValueType resultType,
  required InstalledNativeCapture? Function(Element) captureFor,
  required InstalledNativeInput? Function(SimpleIdentifier) inputFor,
  InstalledNativeInput? Function(SimpleIdentifier)? borrowFor,
  bool Function(Expression)? isDeclaredCallable,
  Map<Expression, String?> constantStrings = const {},
  LibraryElement? emissionLibrary,
}) {
  final invocations = qualifyInstalledNativeCallables(
    expression,
    isDeclaredCallable: isDeclaredCallable ?? (_) => false,
  );
  final fixedStrings = validateInstalledIntlInvocations(invocations);
  for (final entry in constantStrings.entries) {
    if (fixedStrings.containsKey(entry.key) &&
        fixedStrings[entry.key] != entry.value) {
      throw BuilderLoweringException(
        entry.key,
        'Native constant replacement conflicts with fixed lookup metadata',
      );
    }
    fixedStrings[entry.key] = entry.value;
  }
  final unit = expression.root;
  final fragment = unit is CompilationUnit ? unit.declaredFragment : null;
  final contents = fragment?.source.contents.data;
  if (fragment == null ||
      contents == null ||
      expression.end > contents.length) {
    throw BuilderLoweringException(
      expression,
      'Native call requires resolved source',
    );
  }
  final namespace = OwningLibraryNamespace(emissionLibrary ?? fragment.element);
  final result = expression.staticType;
  final resultCode = result == null ? null : namespace.typeCode(result);
  if (resultCode == null) {
    throw BuilderLoweringException(
      expression,
      'Native result type is not visible',
    );
  }
  var prefix = '_restage';
  final original = contents.substring(expression.offset, expression.end);
  final visible = _NativeSpellings(namespace);
  expression.accept(visible);
  while (original.contains(prefix) ||
      [
        ...visible.spellings,
        resultCode,
      ].any((spelling) => spelling.contains(prefix))) {
    prefix = '${prefix}_';
  }
  final visitor = _NativeCallWriter(
    expression,
    namespace,
    captureFor,
    inputFor,
    borrowFor,
    prefix,
    fixedStrings,
  );
  expression.accept(visitor);
  var source = contents.substring(expression.offset, expression.end);
  for (final edit in visitor.edits..sort((a, b) => b.$1.compareTo(a.$1))) {
    source = source.replaceRange(
      edit.$1 - expression.offset,
      edit.$2 - expression.offset,
      edit.$3,
    );
  }
  if (expression is InstanceCreationExpression && expression.isConst) {
    if (visitor.inputs.isNotEmpty || visitor.captures.isNotEmpty) {
      throw BuilderLoweringException(
        expression,
        'Native constants require their compiled constant declaration',
      );
    }
    if (expression.keyword?.lexeme != 'const') source = 'const $source';
  }
  return InstalledNativeCallPlan._(
    source,
    resultCode,
    resultType,
    visitor.inputs,
    visitor.captures,
    visitor.inputTypes,
    visitor.captureTypes,
    prefix,
    namespace.library.identifier,
    nativeExpressionProvenance(expression),
  );
}

final class _NativeCallWriter extends GeneralizingAstVisitor<void> {
  _NativeCallWriter(
    this.root,
    this.namespace,
    this.captureFor,
    this.inputFor,
    this.borrowFor,
    this.prefix,
    this.constantStrings,
  ) {
    final locals = _LocalNames();
    root.accept(locals);
    localNames.addAll(locals.names);
    for (final entry in constantStrings.entries) {
      if (entry.key.offset < root.offset ||
          entry.key.end > root.end ||
          !identical(entry.key.root, root.root)) {
        refuse(
          entry.key,
          'Native constant replacement is outside its expression',
        );
      }
      final value = installedNativeConstantValue(entry.key);
      if (value == null ||
          (value.isNull
              ? entry.value != null
              : value.toStringValue() == null ||
                    value.toStringValue() != entry.value)) {
        refuse(
          entry.key,
          'Native constant replacement does not match resolved source',
        );
      }
    }
  }
  final Expression root;
  final String prefix;
  final OwningLibraryNamespace namespace;
  final InstalledNativeCapture? Function(Element) captureFor;
  final InstalledNativeInput? Function(SimpleIdentifier) inputFor;
  final InstalledNativeInput? Function(SimpleIdentifier)? borrowFor;
  final Map<Expression, String?> constantStrings;
  final localNames = <String>{};
  final edits = <(int, int, String)>[];
  final inputs = <InstalledNativeInput>[];
  final captures = <String, InstalledNativeCapture>{};
  final inputTypes = <String>[];
  final captureTypes = <String, String>{};
  final names = <Element, String>{};

  Never refuse(AstNode node, String reason) =>
      throw BuilderLoweringException(node, reason);

  void edit(AstNode node, String replacement) {
    final parent = node.parent;
    if (parent is InterpolationExpression &&
        parent.leftBracket.lexeme == r'$') {
      edits.add((parent.offset, parent.end, r'${' + replacement + '}'));
    } else {
      edits.add((node.offset, node.end, replacement));
    }
  }

  String visible(Element element) {
    final spelling = element.enclosingElement is InstanceElement
        ? namespace.staticMemberName(element)
        : namespace.elementName(element);
    if (spelling == null || localNames.contains(spelling.split('.').first)) {
      refuse(
        root,
        'Native declaration is unavailable or shadowed in the emission library',
      );
    }
    return spelling;
  }

  bool replaceConstant(AstNode node) {
    if (!constantStrings.containsKey(node)) return false;
    edit(node, _dartJson(constantStrings[node]));
    return true;
  }

  @override
  void visitNode(AstNode node) {
    if (replaceConstant(node)) return;
    final sourceLibrary =
        (root.root as CompilationUnit).declaredFragment!.element;
    if (sourceLibrary != namespace.library) {
      final element = switch (node) {
        BinaryExpression() => node.element,
        PrefixExpression() => node.element,
        PostfixExpression() => node.element,
        AssignmentExpression() => node.element,
        IndexExpression() => node.element,
        MethodInvocation() => node.methodName.element,
        PropertyAccess() => node.propertyName.element,
        PrefixedIdentifier() => node.identifier.element,
        _ => null,
      };
      if (element?.enclosingElement is ExtensionElement ||
          node is ExtensionOverride) {
        refuse(
          node,
          'Native extension dispatch requires its original library scope',
        );
      }
    }
    if (node is DotShorthandInvocation ||
        node is DotShorthandPropertyAccess ||
        node is DotShorthandConstructorInvocation) {
      refuse(node, 'Native shorthand requires an explicit resolved owner');
    }
    if (node is NamedType && node.type is TypeParameterType) {
      final declaration =
          (node.type as TypeParameterType).element.firstFragment.nameOffset;
      if (declaration == null ||
          declaration < root.offset ||
          declaration >= root.end) {
        refuse(node, 'Native types require a retained lexical type parameter');
      }
    }
    super.visitNode(node);
  }

  @override
  void visitThisExpression(ThisExpression node) =>
      refuse(node, 'Native calls cannot retain the source instance');

  @override
  void visitSuperExpression(SuperExpression node) =>
      refuse(node, 'Native calls cannot retain the source instance');

  @override
  void visitPatternAssignment(PatternAssignment node) =>
      refuse(node, 'Native capture pattern assignment is unsupported');

  @override
  void visitNamedType(NamedType node) {
    final type = node.type;
    if (type is TypeParameterType) {
      super.visitNamedType(node);
      return;
    }
    if (type == null && node.element != null) {
      final spelling = visible(node.element!);
      edits.add((node.offset, node.name.end, spelling));
      node.typeArguments?.accept(this);
      return;
    }
    final spelling = type == null ? null : namespace.typeCode(type);
    if (spelling == null ||
        spelling != node.toSource() &&
            localNames.contains(
              spelling.split(RegExp(r'[< ?(]')).first.split('.').first,
            ) ||
        namespace.prefixNames.any(
          (name) => localNames.contains(name) && spelling.contains('$name.'),
        ))
      refuse(
        node,
        'Native type is unavailable or shadowed in the emission library',
      );
    edit(node, spelling);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (replaceConstant(node)) return;
    final element = node.identifier.element;
    if (element != null &&
        (element.enclosingElement is LibraryElement ||
            element is PropertyAccessorElement && element.isStatic ||
            element is MethodElement && element.isStatic)) {
      edit(node, visible(element));
      return;
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (replaceConstant(node)) return;
    final element = node.methodName.element;
    if (node.methodName.name == 'call' &&
        node.target?.staticType is FunctionType) {
      node.target!.accept(this);
      node.typeArguments?.accept(this);
      node.argumentList.accept(this);
      return;
    }
    if (element is TopLevelFunctionElement ||
        element is MethodElement && element.isStatic) {
      final spelling = visible(element!);
      edits.add((node.offset, node.methodName.end, spelling));
      node.typeArguments?.accept(this);
      node.argumentList.accept(this);
      return;
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (replaceConstant(node)) return;
    final element = node.propertyName.element;
    if (element != null &&
        (element is PropertyAccessorElement && element.isStatic ||
            element is MethodElement && element.isStatic)) {
      edit(node, visible(element));
      return;
    }
    if (node.target is ThisExpression && element is PropertyAccessorElement) {
      _borrowMember(node.propertyName, node, element);
      return;
    }
    super.visitPropertyAccess(node);
  }

  void _borrowMember(
    SimpleIdentifier identifier,
    AstNode range,
    PropertyAccessorElement element,
  ) {
    final existing = names[element];
    if (existing != null && !identifier.inSetterContext()) {
      edit(range, existing);
      return;
    }
    final input = borrowFor?.call(identifier);
    final code = namespace.typeCode(element.returnType);
    if (input == null || code == null || identifier.inSetterContext()) {
      refuse(
        identifier,
        'Native calls require a proven borrowed constructor input',
      );
    }
    final name = names.putIfAbsent(element, () {
      final name = '${prefix}Input${inputs.length}';
      inputs.add(input);
      inputTypes.add(code);
      return name;
    });
    edit(range, name);
    return;
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (replaceConstant(node)) return;
    final element = node.element;
    if (element == null)
      refuse(node, 'Native calls require resolved identifiers');
    if (element.isPrivate &&
        element.library != namespace.library &&
        (element.enclosingElement is LibraryElement ||
            element.enclosingElement is InstanceElement)) {
      refuse(
        node,
        'Native private declaration is unavailable in the emission library',
      );
    }
    final parent = node.parent;
    final selector =
        parent is ConstructorName && parent.name == node ||
        parent is PropertyAccess && parent.propertyName == node ||
        parent is PrefixedIdentifier && parent.identifier == node ||
        parent is MethodInvocation &&
            parent.methodName == node &&
            parent.target != null;
    if (selector) return;
    final isStatic = switch (element) {
      ExecutableElement() => element.isStatic,
      VariableElement() => element.isStatic,
      _ => false,
    };
    if (isStatic && element.enclosingElement is InstanceElement) {
      edit(node, visible(element));
      return;
    }
    final declaration = element.firstFragment.nameOffset;
    final declaredInside =
        declaration != null &&
        declaration >= root.offset &&
        declaration < root.end;
    if (element is LocalFunctionElement && !declaredInside) {
      refuse(
        node,
        'A local function requires an explicit native lexical value',
      );
    }
    if (element is PropertyAccessorElement &&
        !element.isStatic &&
        element.enclosingElement is InstanceElement) {
      _borrowMember(node, node, element);
      return;
    }
    if (element is MethodElement && !element.isStatic) {
      refuse(node, 'Native calls require an explicit native receiver');
    }
    if (element is! LocalVariableElement &&
        element is! FormalParameterElement) {
      if (element is PrefixElement) return;
      if (element.enclosingElement is LibraryElement)
        edit(node, visible(element));
      return;
    }
    if (declaredInside) return;
    for (
      var ancestor = node.parent;
      ancestor != null && ancestor != root;
      ancestor = ancestor.parent
    ) {
      if (ancestor is FormalParameterDefaultClause ||
          ancestor is VariableDeclarationList && ancestor.isConst ||
          ancestor is InstanceCreationExpression && ancestor.isConst ||
          ancestor is TypedLiteral && ancestor.isConst) {
        refuse(node, 'Native constant contexts require compiled constants');
      }
    }
    final type = (element as VariableElement).type;
    final typeCode = namespace.typeCode(type);
    if (typeCode == null) refuse(node, 'Native capture type is not visible');
    var name = names[element];
    if (name == null) {
      final cell = captureFor(element);
      if (cell != null) {
        if (!const {
          'int',
          'double',
          'num',
          'bool',
          'String',
          'Null',
          'native',
        }.contains(cell.type.kind)) {
          refuse(
            node,
            'Native captures require original values, not data projections',
          );
        }
        if (cell.type.kind != 'native' && !_nativeScalar(type)) {
          refuse(
            node,
            'Native captures cannot use a projected scalar identity',
          );
        }
        name = '${prefix}Capture${captures.length}';
        captures[name] = cell;
        captureTypes[name] = typeCode;
      } else {
        final input = inputFor(node);
        if (input == null)
          refuse(node, 'Native call capture has no lexical value');
        if (input.type.kind != 'native' && !_nativeScalar(type)) {
          refuse(node, 'Native inputs cannot use a projected scalar identity');
        }
        name = '${prefix}Input${inputs.length}';
        inputs.add(input);
        inputTypes.add(typeCode);
      }
      names[element] = name;
    }
    if (!captures.containsKey(name) && node.inSetterContext()) {
      refuse(node, 'Native writes require an existing mutable lexical cell');
    }
    var replacement = captures.containsKey(name) ? '$name.value' : name;
    final promoted = node.staticType;
    if (node.inGetterContext() &&
        !node.inSetterContext() &&
        promoted != null &&
        promoted != type) {
      final promotedCode = namespace.typeCode(promoted);
      if (promotedCode == null)
        refuse(node, 'Promoted native capture type is not visible');
      replacement = '${prefix}As<$promotedCode>($replacement)';
    }
    edit(node, replacement);
  }
}

bool _nativeScalar(DartType type) =>
    type is InterfaceType &&
    type.element.library.identifier == 'dart:core' &&
    const {
      'int',
      'double',
      'num',
      'bool',
      'String',
      'Null',
    }.contains(type.element.name);

/// Stable nominal spelling; generated Dart uses the owning namespace separately.
String installedNativeTypeId(DartType type) => switch (type) {
  InterfaceType() =>
    '${type.element.library.identifier}#${type.element.name}'
        '${type.typeArguments.isEmpty ? '' : '<${type.typeArguments.map(installedNativeTypeId).join(',')}>'}'
        '${type.nullabilitySuffix.name == 'question' ? '?' : ''}',
  FunctionType() =>
    '(${type.formalParameters.map((p) => '${p.isRequiredNamed
            ? 'required '
            : p.isOptionalPositional
            ? 'optional '
            : ''}${p.isNamed ? '${p.name}:' : ''}${installedNativeTypeId(p.type)}').join(',')})->${installedNativeTypeId(type.returnType)}'
        '${type.nullabilitySuffix.name == 'question' ? '?' : ''}',
  VoidType() => 'void',
  _ => throw ArgumentError('Unsupported nominal native type $type'),
};

/// The id of callback [type] without the slot's own nullability, or null when
/// it is not a function type every part of which has a nominal id.
String? callbackTypeId(DartType type) {
  if (type is! FunctionType || !_hasNominalId(type)) return null;
  final id = installedNativeTypeId(type);
  return type.nullabilitySuffix == NullabilitySuffix.question
      ? id.substring(0, id.length - 1)
      : id;
}

bool _hasNominalId(DartType type) => switch (type) {
  InterfaceType() => type.typeArguments.every(_hasNominalId),
  FunctionType() =>
    _hasNominalId(type.returnType) &&
        type.formalParameters.every((p) => _hasNominalId(p.type)),
  VoidType() => true,
  _ => false,
};

final class _LocalNames extends GeneralizingAstVisitor<void> {
  final names = <String>{};
  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.inDeclarationContext()) names.add(node.name);
  }

  @override
  void visitNode(AstNode node) {
    if (node is FormalParameter) {
      final name = node.declaredFragment?.element.name;
      if (name != null) names.add(name);
    }
    if (node is FunctionDeclaration) names.add(node.name.lexeme);
    if (node is VariableDeclaration) names.add(node.name.lexeme);
    if (node is DeclaredVariablePattern) names.add(node.name.lexeme);
    if (node is TypeParameter) names.add(node.name.lexeme);
    super.visitNode(node);
  }
}

/// Collects destination spellings before allocating any generated locals.
final class _NativeSpellings extends GeneralizingAstVisitor<void> {
  _NativeSpellings(this.namespace);
  final OwningLibraryNamespace namespace;
  final spellings = <String>{};
  void type(DartType? value) {
    if (value == null) return;
    final spelling = namespace.typeCode(value);
    if (spelling != null) spellings.add(spelling);
  }

  @override
  void visitNode(AstNode node) {
    if (node is Expression) type(node.staticType);
    if (node is NamedType) {
      type(node.type);
      if (node.element case final element?) {
        final spelling = namespace.elementName(element);
        if (spelling != null) spellings.add(spelling);
      }
    }
    if (node is SimpleIdentifier) {
      final element = node.element;
      if (element is VariableElement) type(element.type);
      if (element is PropertyAccessorElement) type(element.returnType);
      if (element != null) {
        final spelling = element.enclosingElement is InstanceElement
            ? namespace.staticMemberName(element)
            : namespace.elementName(element);
        if (spelling != null) spellings.add(spelling);
      }
    }
    super.visitNode(node);
  }
}
