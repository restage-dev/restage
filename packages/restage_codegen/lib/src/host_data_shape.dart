import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/theme_recognition.dart';

/// The closed run-time representation of one host-supplied value.
@immutable
sealed class HostDataShape {
  const HostDataShape(this.type);

  /// The exact analyzer type represented by this shape.
  final DartType type;

  /// Whether the generated mount must convert this value before publication.
  bool get requiresEncoding;
}

/// A scalar value accepted directly by the run-time data decoder.
@immutable
final class HostDataScalarShape extends HostDataShape {
  /// Creates a scalar shape for [kind].
  const HostDataScalarShape(super.type, this.kind);

  /// The scalar decoder family.
  final HostDataScalarKind kind;

  @override
  bool get requiresEncoding => false;
}

/// Scalar decoder families supported by host data.
enum HostDataScalarKind {
  /// Nullable `Object`.
  object,

  /// `bool`.
  boolean,

  /// `int`.
  integer,

  /// `double`.
  doubleValue,

  /// `num`.
  number,

  /// `String`.
  string
}

/// A recursively shaped core List.
@immutable
final class HostDataListShape extends HostDataShape {
  /// Creates a list shape with [elementShape].
  const HostDataListShape(super.type, this.elementShape);

  /// The exact shape of every list element.
  final HostDataShape elementShape;

  @override
  bool get requiresEncoding => elementShape.requiresEncoding;
}

/// A recursively shaped core Map with String keys.
@immutable
final class HostDataMapShape extends HostDataShape {
  /// Creates a string-keyed map shape with [valueShape].
  const HostDataMapShape(super.type, this.valueShape);

  /// The exact shape of every map value.
  final HostDataShape valueShape;

  @override
  bool get requiresEncoding => valueShape.requiresEncoding;
}

/// One stored field of a plain host-data object.
@immutable
final class HostDataObjectField {
  /// Creates an exact field descriptor.
  const HostDataObjectField({
    required this.element,
    required this.wireKey,
    required this.shape,
  });

  /// The exact declared field identity.
  final FieldElement element;

  /// The serialized map key.
  final String wireKey;

  /// The field's recursive value shape.
  final HostDataShape shape;
}

/// A plain object encoded as an ordered string-keyed map.
@immutable
final class HostDataObjectShape extends HostDataShape {
  /// Creates a plain object shape with fields in declaration order.
  HostDataObjectShape(
    super.type, {
    required this.element,
    required List<HostDataObjectField> fields,
  }) : fields = List.unmodifiable(fields);

  /// The exact class declaration represented by this object.
  final ClassElement element;

  /// Declared fields in analyzer declaration order.
  final List<HostDataObjectField> fields;

  /// Returns the descriptor for [element], using exact field identity.
  HostDataObjectField? fieldFor(Element? element) {
    final field = switch (element) {
      PropertyAccessorElement(:final variable) => variable,
      FieldElement() => element,
      _ => null,
    };
    if (field is! FieldElement) return null;
    for (final candidate in fields) {
      if (identical(candidate.element.baseElement, field.baseElement)) {
        return candidate;
      }
    }
    return null;
  }

  @override
  bool get requiresEncoding => true;
}

/// Why a Dart type has no host-data shape.
@immutable
final class HostDataShapeProblem {
  /// Creates a refusal at [path].
  const HostDataShapeProblem({required this.path, required this.detail});

  /// The root/member path at which derivation failed.
  final String path;

  /// The structural reason the value is not admissible.
  final String detail;
}

/// The result of deriving the closed host-data shape.
@immutable
final class HostDataShapeFact {
  const HostDataShapeFact._({this.shape, this.problem});

  /// Creates one admitted shape.
  const HostDataShapeFact.admitted(HostDataShape value) : this._(shape: value);

  /// Creates one refused shape.
  const HostDataShapeFact.refused(HostDataShapeProblem value)
      : this._(problem: value);

  /// The admitted shape, when derivation succeeded.
  final HostDataShape? shape;

  /// The first structural refusal, when derivation failed.
  final HostDataShapeProblem? problem;
}

/// Derives the one recursive shape used by all host-data consumers.
HostDataShapeFact deriveHostDataShape(DartType type, {required String root}) =>
    _HostDataShapeDeriver().derive(type, root);

final class _HostDataShapeDeriver {
  final Set<ClassElement> _activeClasses = Set.identity();

  HostDataShapeFact derive(DartType type, String path) {
    if (type is! InterfaceType) {
      return _refused(path, 'the type is not a supported interface value');
    }
    final arguments = type.typeArguments;
    if (arguments.isEmpty) {
      if (type.isDartCoreObject) {
        return type.nullabilitySuffix == NullabilitySuffix.question
            ? HostDataShapeFact.admitted(
                HostDataScalarShape(type, HostDataScalarKind.object),
              )
            : _refused(path, 'non-nullable Object is not supported');
      }
      final scalar = switch (type) {
        _ when type.isDartCoreBool => HostDataScalarKind.boolean,
        _ when type.isDartCoreInt => HostDataScalarKind.integer,
        _ when type.isDartCoreDouble => HostDataScalarKind.doubleValue,
        _ when type.isDartCoreNum => HostDataScalarKind.number,
        _ when type.isDartCoreString => HostDataScalarKind.string,
        _ => null,
      };
      if (scalar != null) {
        return HostDataShapeFact.admitted(HostDataScalarShape(type, scalar));
      }
    }
    if (type.isDartCoreList && arguments.length == 1) {
      // The render-context channel cannot represent a null element: publishing
      // one drops it and shifts every later index.
      if (arguments.single.isDartCoreObject) {
        return _refused(
          '$path[]',
          'a list element cannot be Object or Object?; declare a concrete '
              'non-nullable element type',
        );
      }
      if (arguments.single.nullabilitySuffix == NullabilitySuffix.question) {
        return _refused(
          '$path[]',
          'a list element cannot be nullable, because an absent element would '
              'shift every later index; declare the element type without "?"',
        );
      }
      final element = derive(arguments.single, '$path[]');
      final shape = element.shape;
      return shape == null
          ? element
          : HostDataShapeFact.admitted(HostDataListShape(type, shape));
    }
    if (type.isDartCoreMap && arguments.length == 2) {
      final key = arguments.first;
      if (!key.isDartCoreString ||
          key.nullabilitySuffix != NullabilitySuffix.none) {
        return _refused('$path{key}', 'map keys must be non-nullable String');
      }
      final value = derive(arguments.last, '$path{}');
      final shape = value.shape;
      return shape == null
          ? value
          : HostDataShapeFact.admitted(HostDataMapShape(type, shape));
    }
    final element = type.element;
    if (element is! ClassElement) {
      return _refused(path, 'the declaration is not a plain class');
    }
    return _plainObject(type, element, path);
  }

  HostDataShapeFact _plainObject(
    InterfaceType type,
    ClassElement element,
    String path,
  ) {
    if (isFrameworkValueTypeLibrary(element)) {
      return _refused(path, 'framework value types are not supported');
    }
    if (element.isAbstract ||
        !element.isConstructable ||
        element.isMixinApplication ||
        element.typeParameters.isNotEmpty) {
      return _refused(path, 'the class must be concrete and non-generic');
    }
    if (element.supertype case final supertype?
        when !supertype.isDartCoreObject) {
      return _refused(path, 'inherited field sets are not supported');
    }
    if (element.mixins.isNotEmpty) {
      return _refused(
        path,
        'inherited or mixed-in field sets are not supported',
      );
    }
    final constructor = element.unnamedConstructor;
    if (constructor == null ||
        !constructor.isConst ||
        !constructor.isGenerative ||
        constructor.isFactory) {
      return _refused(
        path,
        'the unnamed constructor must be const and generative',
      );
    }
    if (element.methods.isNotEmpty) {
      return _refused(path, 'plain host-data classes cannot declare methods');
    }
    if (!_activeClasses.add(element)) {
      return _refused(path, 'recursive class graphs are not supported');
    }
    final fields = <HostDataObjectField>[];
    try {
      for (final field in element.fields) {
        final name = field.name;
        if (!field.isOriginDeclaration ||
            name == null ||
            name.startsWith('_') ||
            field.isStatic ||
            !field.isFinal ||
            field.isLate ||
            field.isAbstract ||
            field.isExternal) {
          return _refused(
            name == null ? path : '$path.$name',
            'fields must be public final stored declarations',
          );
        }
        final nested = derive(field.type, '$path.$name');
        final shape = nested.shape;
        if (shape == null) return nested;
        fields.add(
          HostDataObjectField(
            element: field,
            wireKey: name,
            shape: shape,
          ),
        );
      }
    } finally {
      _activeClasses.remove(element);
    }
    if (fields.isEmpty) {
      return _refused(
        path,
        'plain host-data classes must declare a stored field',
      );
    }
    return HostDataShapeFact.admitted(
      HostDataObjectShape(type, element: element, fields: fields),
    );
  }

  HostDataShapeFact _refused(String path, String detail) =>
      HostDataShapeFact.refused(
        HostDataShapeProblem(path: path, detail: detail),
      );
}
