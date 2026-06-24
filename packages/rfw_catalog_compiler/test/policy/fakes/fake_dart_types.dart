import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

class _FakeInterfaceType implements InterfaceType {
  _FakeInterfaceType(
    this._name, {
    bool isNullable = false,
    String libraryIdentifier = 'package:test/types.dart',
    List<DartType> typeArguments = const [],
    DartType? aliasTarget,
    InterfaceElement? element,
  })  : _nullable = isNullable,
        _typeArguments = typeArguments,
        _element = element ?? _FakeInterfaceElement(_name, libraryIdentifier),
        _alias = aliasTarget == null ? null : _FakeAlias(aliasTarget);

  final String _name;
  final bool _nullable;
  final List<DartType> _typeArguments;
  final InterfaceElement _element;
  final InstantiatedTypeAliasElement? _alias;

  @override
  InstantiatedTypeAliasElement? get alias => _alias;

  @override
  InterfaceElement get element => _element;

  @override
  List<DartType> get typeArguments => _typeArguments;

  @override
  String getDisplayString({bool withNullability = true}) =>
      '${_displayName(_name, _typeArguments)}'
      '${withNullability && _nullable ? '?' : ''}';

  @override
  NullabilitySuffix get nullabilitySuffix =>
      _nullable ? NullabilitySuffix.question : NullabilitySuffix.none;

  // The rest of DartType's surface is unused by the filter. Throw on
  // access so an accidental dependency on these members fails loudly
  // during a test run rather than silently returning bogus defaults.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Fake DartType: ${invocation.memberName}');
}

class _FakeFunctionType implements FunctionType {
  _FakeFunctionType({
    required this.returnType,
    List<DartType> parameterTypes = const [],
  }) : formalParameters = [
          for (var i = 0; i < parameterTypes.length; i += 1)
            _FakeFormalParameter('p$i', parameterTypes[i]),
        ];

  @override
  final DartType returnType;

  @override
  final List<FormalParameterElement> formalParameters;

  @override
  InstantiatedTypeAliasElement? get alias => null;

  @override
  Null get element => null;

  @override
  String getDisplayString({bool withNullability = true}) {
    final params = formalParameters.map((p) => p.type.getDisplayString());
    return '${returnType.getDisplayString()} Function(${params.join(', ')})';
  }

  @override
  NullabilitySuffix get nullabilitySuffix => NullabilitySuffix.none;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Fake FunctionType: ${invocation.memberName}');
}

class _FakeRecordType implements RecordType {
  _FakeRecordType({
    List<DartType> positional = const [],
    Map<String, DartType> named = const {},
  })  : positionalFields = [
          for (final type in positional) _FakeRecordPositionalField(type),
        ],
        namedFields = [
          for (final entry in named.entries)
            _FakeRecordNamedField(entry.key, entry.value),
        ];

  @override
  InstantiatedTypeAliasElement? get alias => null;

  @override
  Null get element => null;

  @override
  final List<RecordTypeNamedField> namedFields;

  @override
  NullabilitySuffix get nullabilitySuffix => NullabilitySuffix.none;

  @override
  final List<RecordTypePositionalField> positionalFields;

  @override
  String getDisplayString({bool withNullability = true}) => '(...)';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Fake RecordType: ${invocation.memberName}');
}

class _FakeTypeParameterType implements TypeParameterType {
  _FakeTypeParameterType(String name, this.bound)
      : element = _FakeTypeParameterElement(name);

  @override
  InstantiatedTypeAliasElement? get alias => null;

  @override
  final DartType bound;

  @override
  final TypeParameterElement element;

  @override
  String getDisplayString({bool withNullability = true}) =>
      element.name ?? '<unnamed>';

  @override
  NullabilitySuffix get nullabilitySuffix => NullabilitySuffix.none;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'Fake TypeParameterType: ${invocation.memberName}',
      );
}

class _FakeDynamicType implements DynamicType {
  @override
  InstantiatedTypeAliasElement? get alias => null;

  @override
  Null get element => null;

  @override
  String getDisplayString({bool withNullability = true}) => 'dynamic';

  @override
  NullabilitySuffix get nullabilitySuffix => NullabilitySuffix.none;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Fake DynamicType: ${invocation.memberName}');
}

class _FakeVoidType implements VoidType {
  @override
  InstantiatedTypeAliasElement? get alias => null;

  @override
  Null get element => null;

  @override
  String getDisplayString({bool withNullability = true}) => 'void';

  @override
  NullabilitySuffix get nullabilitySuffix => NullabilitySuffix.none;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Fake VoidType: ${invocation.memberName}');
}

class _FakeNeverType implements NeverType {
  @override
  InstantiatedTypeAliasElement? get alias => null;

  @override
  Null get element => null;

  @override
  String getDisplayString({bool withNullability = true}) => 'Never';

  @override
  NullabilitySuffix get nullabilitySuffix => NullabilitySuffix.none;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Fake NeverType: ${invocation.memberName}');
}

class _FakeInterfaceElement implements InterfaceElement {
  _FakeInterfaceElement(this.name, String libraryIdentifier)
      : library = _FakeLibraryElement(libraryIdentifier);

  @override
  final LibraryElement library;

  @override
  final String name;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'Fake InterfaceElement: ${invocation.memberName}',
      );
}

class _FakeClassElement implements ClassElement {
  _FakeClassElement(
    this.name, {
    required String libraryIdentifier,
    this.fields = const [],
    this.constructors = const [],
    this.methods = const [],
    this.getters = const [],
    this.documentationComment,
    this.isAbstract = false,
    this.allSupertypes = const [],
  }) : library = _FakeLibraryElement(libraryIdentifier) {
    thisType = _FakeInterfaceType(
      name,
      libraryIdentifier: libraryIdentifier,
      element: this,
    );
  }

  @override
  final LibraryElement library;

  @override
  final String name;

  @override
  final List<FieldElement> fields;

  @override
  final List<ConstructorElement> constructors;

  @override
  final List<MethodElement> methods;

  @override
  final List<GetterElement> getters;

  @override
  final bool isAbstract;

  @override
  final List<InterfaceType> allSupertypes;

  @override
  late final InterfaceType thisType;

  @override
  final String? documentationComment;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'Fake ClassElement: ${invocation.memberName}',
      );
}

class _FakeEnumElement implements EnumElement {
  _FakeEnumElement(this.name, String libraryIdentifier)
      : library = _FakeLibraryElement(libraryIdentifier);

  @override
  final LibraryElement library;

  @override
  final String name;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'Fake EnumElement: ${invocation.memberName}',
      );
}

class _FakeFieldElement implements FieldElement {
  _FakeFieldElement(
    this.name,
    this.type, {
    this.isStatic = false,
    this.isConst = false,
    this.isOriginGetterSetter = false,
    bool? isPublic,
    this.documentationComment,
  }) : isPublic = isPublic ?? !name.startsWith('_');

  @override
  final String name;

  @override
  final DartType type;

  @override
  final bool isStatic;

  @override
  final bool isConst;

  @override
  final bool isOriginGetterSetter;

  @override
  final bool isPublic;

  @override
  bool get isPrivate => !isPublic;

  @override
  final String? documentationComment;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'Fake FieldElement: ${invocation.memberName}',
      );
}

class _FakeConstructorElement implements ConstructorElement {
  _FakeConstructorElement(
    this.name, {
    required this.returnType,
    this.formalParameters = const [],
    this.isRedirecting = false,
    this.isFactory = false,
    bool? isPublic,
    this.documentationComment,
  }) : isPublic = isPublic ?? !(name ?? '').startsWith('_');

  @override
  final String? name;

  @override
  final InterfaceType returnType;

  @override
  final List<FormalParameterElement> formalParameters;

  final bool isRedirecting;

  @override
  final bool isFactory;

  @override
  ConstructorElement? get redirectedConstructor => isRedirecting ? this : null;

  @override
  final bool isPublic;

  @override
  bool get isPrivate => !isPublic;

  @override
  final String? documentationComment;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'Fake ConstructorElement: ${invocation.memberName}',
      );
}

class _FakeMethodElement implements MethodElement {
  _FakeMethodElement(
    this.name, {
    required this.returnType,
    this.formalParameters = const [],
    this.isStatic = true,
    bool? isPublic,
    this.documentationComment,
  }) : isPublic = isPublic ?? !name.startsWith('_');

  @override
  final String name;

  @override
  final DartType returnType;

  @override
  final List<FormalParameterElement> formalParameters;

  @override
  final bool isStatic;

  @override
  final bool isPublic;

  @override
  bool get isPrivate => !isPublic;

  @override
  final String? documentationComment;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'Fake MethodElement: ${invocation.memberName}',
      );
}

class _FakeGetterElement implements GetterElement {
  _FakeGetterElement(
    this.name, {
    required this.returnType,
    this.isStatic = true,
    bool? isPublic,
    this.documentationComment,
  }) : isPublic = isPublic ?? !name.startsWith('_');

  @override
  final String name;

  @override
  final DartType returnType;

  @override
  final bool isStatic;

  @override
  final bool isPublic;

  @override
  bool get isPrivate => !isPublic;

  @override
  final String? documentationComment;

  @override
  List<FormalParameterElement> get formalParameters => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Fake GetterElement: ${invocation.memberName}');
}

class _FakeLibraryElement implements LibraryElement {
  _FakeLibraryElement(this.identifier);

  @override
  final String identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Fake LibraryElement: ${invocation.memberName}');
}

class _FakeAlias implements InstantiatedTypeAliasElement {
  _FakeAlias(DartType target) : element = _FakeTypeAliasElement(target);

  @override
  final TypeAliasElement element;

  @override
  List<DartType> get typeArguments => const [];
}

class _FakeTypeAliasElement implements TypeAliasElement {
  _FakeTypeAliasElement(this.aliasedType);

  @override
  final DartType aliasedType;

  @override
  DartType instantiate({
    required List<DartType> typeArguments,
    required NullabilitySuffix nullabilitySuffix,
  }) =>
      aliasedType;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'Fake TypeAliasElement: ${invocation.memberName}',
      );
}

class _FakeFormalParameter implements FormalParameterElement {
  _FakeFormalParameter(this.name, this.type);

  @override
  final String name;

  @override
  final DartType type;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'Fake FormalParameterElement: ${invocation.memberName}',
      );
}

class _FakeRecordPositionalField implements RecordTypePositionalField {
  _FakeRecordPositionalField(this.type);

  @override
  final DartType type;
}

class _FakeRecordNamedField implements RecordTypeNamedField {
  _FakeRecordNamedField(this.name, this.type);

  @override
  final String name;

  @override
  final DartType type;
}

class _FakeTypeParameterElement implements TypeParameterElement {
  _FakeTypeParameterElement(this.name);

  @override
  final String name;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'Fake TypeParameterElement: ${invocation.memberName}',
      );
}

DartType fakeInterfaceType(
  String name, {
  bool isNullable = false,
  String libraryIdentifier = 'package:test/types.dart',
  List<DartType> typeArguments = const [],
  DartType? aliasTarget,
}) =>
    _FakeInterfaceType(
      name,
      isNullable: isNullable,
      libraryIdentifier: libraryIdentifier,
      typeArguments: typeArguments,
      aliasTarget: aliasTarget,
    );

InterfaceType fakeInterfaceTypeForElement(
  InterfaceElement element, {
  bool isNullable = false,
  List<DartType> typeArguments = const [],
}) =>
    _FakeInterfaceType(
      element.name ?? '<unnamed>',
      isNullable: isNullable,
      libraryIdentifier: element.library.identifier,
      typeArguments: typeArguments,
      element: element,
    );

ClassElement fakeClassElement(
  String name, {
  String libraryIdentifier = 'package:test/types.dart',
  List<FieldElement> fields = const [],
  List<ConstructorElement> constructors = const [],
  List<MethodElement> methods = const [],
  List<GetterElement> getters = const [],
  String? documentationComment,
  bool isAbstract = false,
  List<InterfaceType> allSupertypes = const [],
}) =>
    _FakeClassElement(
      name,
      libraryIdentifier: libraryIdentifier,
      fields: fields,
      constructors: constructors,
      methods: methods,
      getters: getters,
      documentationComment: documentationComment,
      isAbstract: isAbstract,
      allSupertypes: allSupertypes,
    );

EnumElement fakeEnumElement(
  String name, {
  String libraryIdentifier = 'package:test/types.dart',
}) =>
    _FakeEnumElement(name, libraryIdentifier);

FieldElement fakeFieldElement(
  String name,
  DartType type, {
  bool isStatic = false,
  bool isConst = false,
  bool isOriginGetterSetter = false,
  bool? isPublic,
  String? documentationComment,
}) =>
    _FakeFieldElement(
      name,
      type,
      isStatic: isStatic,
      isConst: isConst,
      isOriginGetterSetter: isOriginGetterSetter,
      isPublic: isPublic,
      documentationComment: documentationComment,
    );

FieldElement fakeStaticConstField(
  String name,
  DartType type, {
  String? documentationComment,
}) =>
    _FakeFieldElement(
      name,
      type,
      isStatic: true,
      isConst: true,
      documentationComment: documentationComment,
    );

ConstructorElement fakeConstructorElement(
  String? name, {
  required InterfaceType returnType,
  List<FormalParameterElement> parameters = const [],
  bool isRedirecting = false,
  bool isFactory = false,
  bool? isPublic,
  String? documentationComment,
}) =>
    _FakeConstructorElement(
      name,
      returnType: returnType,
      formalParameters: parameters,
      isRedirecting: isRedirecting,
      isFactory: isFactory,
      isPublic: isPublic,
      documentationComment: documentationComment,
    );

MethodElement fakeMethodElement(
  String name, {
  required DartType returnType,
  List<FormalParameterElement> parameters = const [],
  bool isStatic = true,
  bool? isPublic,
  String? documentationComment,
}) =>
    _FakeMethodElement(
      name,
      returnType: returnType,
      formalParameters: parameters,
      isStatic: isStatic,
      isPublic: isPublic,
      documentationComment: documentationComment,
    );

GetterElement fakePropertyAccessorElement(
  String name, {
  required DartType returnType,
  bool isStatic = true,
  bool? isPublic,
  String? documentationComment,
}) =>
    _FakeGetterElement(
      name,
      returnType: returnType,
      isStatic: isStatic,
      isPublic: isPublic,
      documentationComment: documentationComment,
    );

FormalParameterElement fakeFormalParameterElement(
  String name,
  DartType type,
) =>
    _FakeFormalParameter(name, type);

DartType fakeFunctionType({
  required DartType returnType,
  List<DartType> parameterTypes = const [],
}) =>
    _FakeFunctionType(
      returnType: returnType,
      parameterTypes: parameterTypes,
    );

DartType fakeRecordType({
  List<DartType> positional = const [],
  Map<String, DartType> named = const {},
}) =>
    _FakeRecordType(positional: positional, named: named);

DartType fakeTypeParameterType(String name, DartType bound) =>
    _FakeTypeParameterType(name, bound);

DartType fakeDynamicType() => _FakeDynamicType();

DartType fakeVoidType() => _FakeVoidType();

DartType fakeNeverType() => _FakeNeverType();

String _displayName(String name, List<DartType> typeArguments) {
  if (typeArguments.isEmpty) return name;
  final args = typeArguments.map((t) => t.getDisplayString()).join(', ');
  return '$name<$args>';
}
