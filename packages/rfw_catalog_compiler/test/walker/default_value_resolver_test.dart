import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

// kBuiltInThemeBindingSeeds and ThemeBindingSeeds are imported via the
// rfw_catalog_compiler barrel (policy exports).

// ---------------------------------------------------------------------------
// Fake DartObject — implements only the surface used by literalFromDartObject.
// All other members throw so an unintended dependency fails loudly.
//
// NOTE: `_FakeDartObject` deliberately does NOT model the real analyzer's
// coupling between `isNull` and the primitive accessors (a genuine null
// `DartObject` reports `isNull == true` AND returns `null` from every
// `toXxxValue()`). The fake lets each field be set independently, which is
// fine for the literal-classification unit tests but is not authoritative
// for `isNull`/accessor behaviour. The real-analyzer fixtures in the
// `resolveParameterDefault — identifiers` group are the authority for that.
// ---------------------------------------------------------------------------

class _FakeDartObject extends Fake implements DartObject {
  _FakeDartObject({
    this.stringValue,
    this.boolValue,
    this.intValue,
    this.doubleValue,
    this.listValue,
    this.nullObject = false,
  });

  final String? stringValue;
  final bool? boolValue;
  final int? intValue;
  final double? doubleValue;
  final List<DartObject>? listValue;
  final bool nullObject;

  @override
  bool get isNull => nullObject;

  @override
  String? toStringValue() => stringValue;

  @override
  bool? toBoolValue() => boolValue;

  @override
  int? toIntValue() => intValue;

  @override
  double? toDoubleValue() => doubleValue;

  @override
  List<DartObject>? toListValue() => listValue;

  // type is only accessed by the non-literal fallback path (enum/ctor), which
  // is not exercised in these unit tests.
  @override
  DartType? get type => null;
}

_FakeDartObject _str(String v) => _FakeDartObject(stringValue: v);
_FakeDartObject _bool(bool v) => _FakeDartObject(boolValue: v);
_FakeDartObject _int(int v) => _FakeDartObject(intValue: v);
_FakeDartObject _double(double v) => _FakeDartObject(doubleValue: v);
_FakeDartObject _list(List<DartObject> items) =>
    _FakeDartObject(listValue: items);
_FakeDartObject _null() => _FakeDartObject(nullObject: true);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // resolveDefaultFromConstant — no-claim paths
  // -------------------------------------------------------------------------

  group('resolveDefaultFromConstant — no claim', () {
    test('returns null when the parameter has no default', () {
      expect(
        resolveDefaultFromConstant(hasDefault: false, value: null),
        isNull,
      );
    });

    test('returns null when hasDefault is false even if a value is supplied',
        () {
      // Shouldn't normally happen, but the contract says hasDefault=false wins.
      expect(
        resolveDefaultFromConstant(hasDefault: false, value: _str('hello')),
        isNull,
      );
    });

    test('returns null when value is null (parameter default is `null`)', () {
      expect(
        resolveDefaultFromConstant(hasDefault: true, value: null),
        isNull,
      );
    });

    test('returns null when the DartObject itself represents null', () {
      expect(
        resolveDefaultFromConstant(hasDefault: true, value: _null()),
        isNull,
      );
    });
  });

  // -------------------------------------------------------------------------
  // resolveDefaultFromConstant — literal promotion
  // -------------------------------------------------------------------------

  group('resolveDefaultFromConstant — literal promotion', () {
    test('promotes a string constant to LiteralDefault', () {
      final result =
          resolveDefaultFromConstant(hasDefault: true, value: _str('hello'));
      expect(result, isA<LiteralDefault>());
      expect((result! as LiteralDefault).value, 'hello');
    });

    test('promotes a bool constant to LiteralDefault', () {
      final result =
          resolveDefaultFromConstant(hasDefault: true, value: _bool(true));
      expect(result, isA<LiteralDefault>());
      expect((result! as LiteralDefault).value, true);
    });

    test('promotes an int constant to LiteralDefault', () {
      final result =
          resolveDefaultFromConstant(hasDefault: true, value: _int(42));
      expect(result, isA<LiteralDefault>());
      expect((result! as LiteralDefault).value, 42);
    });

    test('promotes a finite double constant to LiteralDefault', () {
      final result =
          resolveDefaultFromConstant(hasDefault: true, value: _double(1.5));
      expect(result, isA<LiteralDefault>());
      expect((result! as LiteralDefault).value, 1.5);
    });

    test('promotes a list of literals to LiteralDefault', () {
      final result = resolveDefaultFromConstant(
        hasDefault: true,
        value: _list([_int(1), _int(2), _int(3)]),
      );
      expect(result, isA<LiteralDefault>());
      expect((result! as LiteralDefault).value, [1, 2, 3]);
    });
  });

  // -------------------------------------------------------------------------
  // resolveDefaultFromConstant — non-bakeable default makes no claim
  // -------------------------------------------------------------------------

  group('resolveDefaultFromConstant — non-bakeable default', () {
    test(
        'returns null when the default is non-literal '
        '(e.g. an opaque DartObject with no primitive accessors)', () {
      // An object that returns null for every value accessor — simulates a
      // const constructor invocation that isn't a bakeable literal. The
      // mechanical resolver makes no claim; it must not synthesize a
      // FlutterCtorDefault (that records curator intent where none was
      // authored).
      final opaque = _FakeDartObject();
      final result =
          resolveDefaultFromConstant(hasDefault: true, value: opaque);
      expect(result, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // literalFromDartObject — exhaustive literal branches
  // -------------------------------------------------------------------------

  group('literalFromDartObject', () {
    test('classifies a String', () {
      expect(literalFromDartObject(_str('world')), 'world');
    });

    test('classifies a bool (true)', () {
      expect(literalFromDartObject(_bool(true)), true);
    });

    test('classifies a bool (false)', () {
      expect(literalFromDartObject(_bool(false)), false);
    });

    test('classifies an int', () {
      expect(literalFromDartObject(_int(7)), 7);
    });

    test('classifies a finite double', () {
      expect(literalFromDartObject(_double(3.14)), 3.14);
    });

    test('drops a non-finite double (infinity)', () {
      expect(literalFromDartObject(_double(double.infinity)), isNull);
    });

    test('drops a non-finite double (negative infinity)', () {
      expect(literalFromDartObject(_double(double.negativeInfinity)), isNull);
    });

    test('drops a non-finite double (NaN)', () {
      expect(literalFromDartObject(_double(double.nan)), isNull);
    });

    test('classifies a list of mixed literals', () {
      final result =
          literalFromDartObject(_list([_str('a'), _bool(false), _int(3)]));
      expect(result, ['a', false, 3]);
    });

    test('classifies a nested list', () {
      final result = literalFromDartObject(
        _list([
          _list([_int(1), _int(2)]),
          _int(3),
        ]),
      );
      expect(result, [
        [1, 2],
        3,
      ]);
    });

    test('returns null for an opaque (non-literal) DartObject', () {
      expect(literalFromDartObject(_FakeDartObject()), isNull);
    });

    test('a non-literal list element becomes a null hole', () {
      // Mirrors legacy `_decodePrimitive`: a nested element that is not a
      // bakeable literal is preserved positionally as `null` rather than
      // dropping it or failing the whole list.
      final result = literalFromDartObject(
        _list([_int(1), _FakeDartObject(), _int(3)]),
      );
      expect(result, [1, null, 3]);
    });
  });

  // -------------------------------------------------------------------------
  // resolveParameterDefault — identifier resolution (real analyzer fixtures)
  // -------------------------------------------------------------------------

  group('resolveParameterDefault — identifiers', () {
    test('resolves a true-enum default to LiteralDefault(memberName)',
        () async {
      final params = await _resolveCtorParams('''
        enum E { a, b }
        class W {
          const W({this.x = E.b});
          final E x;
        }
      ''');
      // A true Dart enum resolves regardless of targetType.
      final result = resolveParameterDefault(
        params['x']!,
        targetType: PropertyType.enumValue,
      );
      expect(result, const LiteralDefault('b'));
    });

    test('resolves a class-static-const default for an alignment-typed param',
        () async {
      // `C` is a regular class with static-const fields (not a Dart enum),
      // mirroring `AlignmentDirectional`. The class-static-const recovery
      // path is gated to PropertyType.alignment — the catalog stores the
      // member name as a string and codegen renders the qualified member.
      final params = await _resolveCtorParams('''
        class C {
          final double a;
          final double b;
          const C._(this.a, this.b);
          static const C topStart = C._(-1, -1);
          static const C bottomEnd = C._(1, 1);
        }
        class W {
          const W({this.y = C.topStart});
          final C y;
        }
      ''');
      final result = resolveParameterDefault(
        params['y']!,
        targetType: PropertyType.alignment,
      );
      expect(result, const LiteralDefault('topStart'));
    });

    test('resolves a class-static-const default for a curve-typed param',
        () async {
      final params = await _resolveCtorParams('''
        class Curve {
          final int id;
          const Curve._(this.id);
          static const Curve linear = Curve._(0);
          static const Curve easeIn = Curve._(1);
        }
        class W {
          const W({this.curve = Curve.linear});
          final Curve curve;
        }
      ''');
      final result = resolveParameterDefault(
        params['curve']!,
        targetType: PropertyType.curve,
      );
      expect(result, const LiteralDefault('linear'));
    });

    test(
        'makes no claim for a class-static-const default on a non-alignment '
        'typed param', () async {
      // The same class-static-const shape, but the property is NOT typed
      // alignment. Recovering the member NAME ('zero') for an `EdgeInsets`
      // / `Duration` / `Color`-style const would produce a type-wrong
      // LiteralDefault, so the resolver makes no claim (returns null).
      final params = await _resolveCtorParams('''
        class C {
          final double a;
          final double b;
          const C._(this.a, this.b);
          static const C topStart = C._(-1, -1);
          static const C bottomEnd = C._(1, 1);
        }
        class W {
          const W({this.y = C.topStart});
          final C y;
        }
      ''');
      final result = resolveParameterDefault(
        params['y']!,
        targetType: PropertyType.real,
      );
      expect(result, isNull);
    });

    test('returns null for a parameter with no default', () async {
      final params = await _resolveCtorParams('''
        class W {
          const W({this.q});
          final int? q;
        }
      ''');
      expect(
        resolveParameterDefault(
          params['q']!,
          targetType: PropertyType.integer,
        ),
        isNull,
      );
    });

    test('returns null for a parameter whose default evaluates to null',
        () async {
      final params = await _resolveCtorParams('''
        class W {
          const W({this.q = null});
          final int? q;
        }
      ''');
      expect(
        resolveParameterDefault(
          params['q']!,
          targetType: PropertyType.integer,
        ),
        isNull,
      );
    });

    test('promotes a plain literal default to LiteralDefault', () async {
      final params = await _resolveCtorParams('''
        class W {
          const W({this.z = 'hi'});
          final String z;
        }
      ''');
      expect(
        resolveParameterDefault(
          params['z']!,
          targetType: PropertyType.string,
        ),
        const LiteralDefault('hi'),
      );
    });

    test(
        'makes no claim for an ambiguous static-const default '
        '(structurally-identical const family)', () async {
      // `D` is a fieldless const family: `alpha` and `beta` are structurally
      // identical, so the value cannot be attributed to one member. The
      // resolver must not silently bake the wrong name — an ambiguous match
      // falls through to "no claim" (null).
      final params = await _resolveCtorParams('''
        class D {
          const D._();
          static const D alpha = D._();
          static const D beta = D._();
        }
        class W {
          const W({this.d = D.alpha});
          final D d;
        }
      ''');
      expect(
        resolveParameterDefault(
          params['d']!,
          targetType: PropertyType.alignment,
        ),
        isNull,
      );
    });

    test('returns null for a non-finite double default (infinity)', () async {
      // `double.infinity` is not a bakeable catalog literal. The resolver
      // must not mis-recover it as a `double` static-const member name
      // (`infinity`) via the static-const fallback — it makes no claim.
      final params = await _resolveCtorParams('''
        class W {
          const W({this.x = double.infinity});
          final double x;
        }
      ''');
      expect(
        resolveParameterDefault(
          params['x']!,
          targetType: PropertyType.real,
        ),
        isNull,
      );
    });

    test('returns null for a non-finite double default (NaN)', () async {
      final params = await _resolveCtorParams('''
        class W {
          const W({this.x = double.nan});
          final double x;
        }
      ''');
      expect(
        resolveParameterDefault(
          params['x']!,
          targetType: PropertyType.real,
        ),
        isNull,
      );
    });

    test('makes no claim for a non-bakeable structured const default',
        () async {
      // A const constructor invocation that is neither a literal nor an
      // enum / static-const identifier — the catalog cannot bake it, so the
      // mechanical resolver makes no claim. It must NOT synthesize a
      // FlutterCtorDefault (that is an explicit curator delegation signal).
      final params = await _resolveCtorParams('''
        class Box {
          final double size;
          const Box(this.size);
        }
        class W {
          const W({this.b = const Box(4)});
          final Box b;
        }
      ''');
      expect(
        resolveParameterDefault(
          params['b']!,
          targetType: PropertyType.real,
        ),
        isNull,
      );
    });
  });

  // -------------------------------------------------------------------------
  // resolveThemeBindingDefault — seed-table lookup
  // -------------------------------------------------------------------------

  group('resolveThemeBindingDefault', () {
    test('emits ThemeBindingDefault for a seeded (widget, property)', () {
      const seeds = ThemeBindingSeeds(namePatterns: kBuiltInThemeBindingSeeds);
      expect(
        resolveThemeBindingDefault(
          widgetName: 'Icon',
          propertyName: 'color',
          seeds: seeds,
        ),
        const ThemeBindingDefault(ThemeBindingPath.path('iconTheme.color')),
      );
    });

    test('returns null for an unseeded (widget, property)', () {
      const seeds = ThemeBindingSeeds(namePatterns: kBuiltInThemeBindingSeeds);
      expect(
        resolveThemeBindingDefault(
          widgetName: 'Container',
          propertyName: 'width',
          seeds: seeds,
        ),
        isNull,
      );
    });
  });

  // -------------------------------------------------------------------------
  // literalFromDartObject — enum-aware list recursion
  // -------------------------------------------------------------------------

  group('literalFromDartObject — enum awareness', () {
    test('decodes a top-level enum member to its member name', () async {
      final value = await _resolveConstField('''
        enum E { a, b }
        const E kValue = E.b;
      ''');
      expect(literalFromDartObject(value), 'b');
    });

    test('decodes a list of enum members to a list of member names', () async {
      // The legacy `_decodePrimitive` decodes `const [E.a]` to `['a']`; the
      // list recursion in `literalFromDartObject` must match — without an
      // enum branch a nested enum becomes a null hole.
      final value = await _resolveConstField('''
        enum E { a, b }
        const List<E> kValue = [E.a, E.b];
      ''');
      expect(literalFromDartObject(value), ['a', 'b']);
    });
  });
}

// ---------------------------------------------------------------------------
// Real-analyzer harness — resolves the `W` constructor's named parameters
// from an in-memory source string, keyed by parameter name. Drives a real
// `package:analyzer` analysis over a temp file so the element-model paths
// (enum `_name`, class static-const fields) exercise the genuine API.
// ---------------------------------------------------------------------------

Future<Map<String, FormalParameterElement>> _resolveCtorParams(
  String source,
) async {
  final dir = Directory.systemTemp.createTempSync('rfw_catalog_compiler_test');
  try {
    final file = File('${dir.path}/fixture.dart')..writeAsStringSync(source);
    final collection = AnalysisContextCollection(includedPaths: [file.path]);
    final context = collection.contextFor(file.path);
    final resolved = await context.currentSession.getResolvedLibrary(file.path);
    resolved as ResolvedLibraryResult;
    final widget = resolved.element.classes.firstWhere((c) => c.name == 'W');
    final ctor = widget.constructors.first;
    return {
      for (final param in ctor.formalParameters)
        if (param.name case final String name) name: param,
    };
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// Resolves the top-level const variable `kValue` declared in [source] and
/// returns its computed [DartObject]. Drives a real `package:analyzer`
/// analysis so enum / list constants exercise the genuine element model.
Future<DartObject> _resolveConstField(String source) async {
  final dir = Directory.systemTemp.createTempSync('rfw_catalog_compiler_test');
  try {
    final file = File('${dir.path}/fixture.dart')..writeAsStringSync(source);
    final collection = AnalysisContextCollection(includedPaths: [file.path]);
    final context = collection.contextFor(file.path);
    final resolved = await context.currentSession.getResolvedLibrary(file.path);
    resolved as ResolvedLibraryResult;
    final variable = resolved.element.topLevelVariables
        .firstWhere((v) => v.name == 'kValue');
    final value = variable.computeConstantValue();
    if (value == null) {
      throw StateError('kValue did not const-evaluate.');
    }
    return value;
  } finally {
    dir.deleteSync(recursive: true);
  }
}
