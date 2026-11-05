// Direct-throw arguments leave the adapter return unreachable.
// ignore_for_file: dead_code
part of 'intl_translation_source.dart';

const intlMessageBinding = "_h07adf40312";
r.NativeCallAdapter intlMessageAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{"kind": "String"},
              <String, Object?>{
                "kind": "native",
                "nativeType": "dart.DateTime"
              },
              <String, Object?>{
                "kind": "native",
                "nativeType": "translation.Token"
              }
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "07adf403123c3b737b093e5722e0986d95b4a44a605cdd452461f19eb7251a45"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final String _restageInput0 = _restageAs<String>(_restageInputs[0]);
      final DateTime _restageInput1 =
          _restageAs<DateTime>((_restageInputs[1] as s.ValueNative).value);
      final TranslationToken _restageInput2 = _restageAs<TranslationToken>(
          (_restageInputs[2] as s.ValueNative).value);
      final String _restageResult = i.Intl.message('Hello ${_restageInput0}',
          name: "welcome",
          args: [_restageInput0, _restageInput1, _restageInput2]);
      return _restageResult;
    });
s.ValueProgram intlMessageProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"String\"},\"name\":\"user\"},{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"dart.DateTime\"},\"name\":\"date\"},{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"translation.Token\"},\"name\":\"token\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"inputs\":[0,1,2],\"value\":{\"binding\":\"_h07adf40312\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"String\"},{\"kind\":\"native\",\"nativeType\":\"dart.DateTime\"},{\"kind\":\"native\",\"nativeType\":\"translation.Token\"}],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"07adf403123c3b737b093e5722e0986d95b4a44a605cdd452461f19eb7251a45\"}},\"captures\":{}}}],\"root\":3,\"captures\":{},\"parameters\":{\"user\":{\"kind\":\"String\"},\"date\":{\"kind\":\"native\",\"nativeType\":\"dart.DateTime\"},\"token\":{\"kind\":\"native\",\"nativeType\":\"translation.Token\"}}}",
        operations: operations,
        context: context);
const intlPluralBinding = "_h4ea31cc227";
r.NativeCallAdapter intlPluralAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{"kind": "int"}
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "4ea31cc227423aeb0daa5110aded7b3ba4838735c3b4a97f87e710773a25bc53"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final int _restageInput0 = _restageAs<int>(_restageInputs[0]);
      final String _restageResult = i.Intl.plural(_restageInput0,
          one: 'one item',
          other: '${_restageInput0} items',
          name: "items",
          args: [_restageInput0]);
      return _restageResult;
    });
s.ValueProgram intlPluralProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"int\"},\"name\":\"count\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"inputs\":[0],\"value\":{\"binding\":\"_h4ea31cc227\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"int\"}],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"4ea31cc227423aeb0daa5110aded7b3ba4838735c3b4a97f87e710773a25bc53\"}},\"captures\":{}}}],\"root\":1,\"captures\":{},\"parameters\":{\"count\":{\"kind\":\"int\"}}}",
        operations: operations,
        context: context);
const intlGenderBinding = "_h68971ef119";
r.NativeCallAdapter intlGenderAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{"kind": "String"}
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "68971ef119468b4f33369ac4df0197a3d6d87256d8e181d2aa0239ebffb10193"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final String _restageInput0 = _restageAs<String>(_restageInputs[0]);
      final String _restageResult = i.Intl.gender(_restageInput0,
          male: 'he',
          female: 'she',
          other: 'they',
          name: "person",
          args: [_restageInput0]);
      return _restageResult;
    });
s.ValueProgram intlGenderProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"String\"},\"name\":\"gender\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"inputs\":[0],\"value\":{\"binding\":\"_h68971ef119\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"String\"}],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"68971ef119468b4f33369ac4df0197a3d6d87256d8e181d2aa0239ebffb10193\"}},\"captures\":{}}}],\"root\":1,\"captures\":{},\"parameters\":{\"gender\":{\"kind\":\"String\"}}}",
        operations: operations,
        context: context);
const intlSelectBinding = "_hf18f93cf93";
r.NativeCallAdapter intlSelectAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{
                "kind": "native",
                "nativeType": "translation.Status"
              },
              <String, Object?>{
                "kind": "native",
                "nativeType": "translation.Token"
              }
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "f18f93cf93863d5406daf3ee9d7eb3fd3d75973f8eb44f950e0a537d70dd5fed"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final TranslationStatus _restageInput0 = _restageAs<TranslationStatus>(
          (_restageInputs[0] as s.ValueNative).value);
      final TranslationToken _restageInput1 = _restageAs<TranslationToken>(
          (_restageInputs[1] as s.ValueNative).value);
      final String _restageResult = i.Intl.select(
          _restageInput0, {'active': 'Active', 'other': 'Other'},
          name: "status",
          args: [_restageInput0, _restageInput0, _restageInput1]);
      return _restageResult;
    });
s.ValueProgram intlSelectProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"translation.Status\"},\"name\":\"choice\"},{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"translation.Token\"},\"name\":\"token\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"inputs\":[0,1],\"value\":{\"binding\":\"_hf18f93cf93\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"native\",\"nativeType\":\"translation.Status\"},{\"kind\":\"native\",\"nativeType\":\"translation.Token\"}],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"f18f93cf93863d5406daf3ee9d7eb3fd3d75973f8eb44f950e0a537d70dd5fed\"}},\"captures\":{}}}],\"root\":2,\"captures\":{},\"parameters\":{\"choice\":{\"kind\":\"native\",\"nativeType\":\"translation.Status\"},\"token\":{\"kind\":\"native\",\"nativeType\":\"translation.Token\"}}}",
        operations: operations,
        context: context);
const intlAbsentArgsBinding = "_h6022d9044f";
r.NativeCallAdapter intlAbsentArgsAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "6022d9044fad26fdd0b4d195ce7b84cc3f040932bd59110304e25d75266214c9"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.message('fallback', name: "noArgs");
      return _restageResult;
    });
s.ValueProgram intlAbsentArgsProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h6022d9044f\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"6022d9044fad26fdd0b4d195ce7b84cc3f040932bd59110304e25d75266214c9\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlNullArgsBinding = "_h2c89e3d656";
r.NativeCallAdapter intlNullArgsAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "2c89e3d6564d544db18b8f4a2414eb4f08416eb5c0e6c3dd917410bb8317faac"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.message('fallback', name: "noArgs", args: null);
      return _restageResult;
    });
s.ValueProgram intlNullArgsProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h2c89e3d656\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"2c89e3d6564d544db18b8f4a2414eb4f08416eb5c0e6c3dd917410bb8317faac\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlEmptyArgsBinding = "_h59e1a1eaf5";
r.NativeCallAdapter intlEmptyArgsAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "59e1a1eaf5caf8b38a4c9a0a63afe66a1c7576cf63cd540006710b3014e68637"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.message('fallback', name: "noArgs", args: []);
      return _restageResult;
    });
s.ValueProgram intlEmptyArgsProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h59e1a1eaf5\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"59e1a1eaf5caf8b38a4c9a0a63afe66a1c7576cf63cd540006710b3014e68637\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlMissingBinding = "_hce4cb96598";
r.NativeCallAdapter intlMissingAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "ce4cb9659828198d5300e32fe076de37e727db0652f84ef2c7b468f688cef505"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.message('untranslated', name: "absent", args: []);
      return _restageResult;
    });
s.ValueProgram intlMissingProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hce4cb96598\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"ce4cb9659828198d5300e32fe076de37e727db0652f84ef2c7b468f688cef505\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlNullNameBinding = "_h0aebcf2133";
r.NativeCallAdapter intlNullNameAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "0aebcf2133d80385ea5bded2d5c1d025156eea1267e350399c04cf133cc54565"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.message("unnamed", name: null, args: [1]);
      return _restageResult;
    });
s.ValueProgram intlNullNameProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h0aebcf2133\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"0aebcf2133d80385ea5bded2d5c1d025156eea1267e350399c04cf133cc54565\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlImplicitNameBinding = "_hc12a5e4892";
r.NativeCallAdapter intlImplicitNameAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "c12a5e4892b2b23e8c005e6accc72857fba0a06b93644d91ae0d1463998a78a8"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.message("implicit");
      return _restageResult;
    });
s.ValueProgram intlImplicitNameProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hc12a5e4892\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"c12a5e4892b2b23e8c005e6accc72857fba0a06b93644d91ae0d1463998a78a8\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlEmptyNameBinding = "_hcc72f24945";
r.NativeCallAdapter intlEmptyNameAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "cc72f249456e267fd62a0242eb81226d0f465fb90fda51719799f79277d100d7"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.message("implicit", name: "");
      return _restageResult;
    });
s.ValueProgram intlEmptyNameProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hcc72f24945\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"cc72f249456e267fd62a0242eb81226d0f465fb90fda51719799f79277d100d7\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlMeaningBinding = "_hbc27a51652";
r.NativeCallAdapter intlMeaningAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "bc27a516522cdce56926af9eef85c2fa7d06ccd30ffb1c57d01ef88108abd265"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.message("implicit", meaning: "context");
      return _restageResult;
    });
s.ValueProgram intlMeaningProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hbc27a51652\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"bc27a516522cdce56926af9eef85c2fa7d06ccd30ffb1c57d01ef88108abd265\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlWrongArityBinding = "_h61ccdb631b";
r.NativeCallAdapter intlWrongArityAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "61ccdb631b57988180dbcc47fb05c5b28155654543ed70c1c28f60ce1580d1cc"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.message('fallback', name: "wrongArity", args: [1]);
      return _restageResult;
    });
s.ValueProgram intlWrongArityProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h61ccdb631b\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"61ccdb631b57988180dbcc47fb05c5b28155654543ed70c1c28f60ce1580d1cc\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlWrongTypeBinding = "_h9fe10cb80e";
r.NativeCallAdapter intlWrongTypeAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "9fe10cb80ebdc057dd0ae54c64aa6fadf806f571e3fca4e89f2931d9ec51a800"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.message('fallback', name: "wrongType", args: ['bad']);
      return _restageResult;
    });
s.ValueProgram intlWrongTypeProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h9fe10cb80e\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"9fe10cb80ebdc057dd0ae54c64aa6fadf806f571e3fca4e89f2931d9ec51a800\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlOrderedBinding = "_hada4a16e18";
r.NativeCallAdapter intlOrderedAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "ada4a16e188e2640e27315a41540043761c9902e96ebc13a06189b1c1db1a20f"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.plural(
          other: translationMark('other', 'fallback'),
          translationMark('count', 1),
          name: "items",
          args: [translationMark('args', 1)],
          locale: translationMark('locale', 'fr'),
          desc: translationMark('desc', 'description'),
          examples: translationMark('examples', <String, Object>{'count': 1}),
          skip: translationMark('skip', false));
      return _restageResult;
    });
s.ValueProgram intlOrderedProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hada4a16e18\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"ada4a16e188e2640e27315a41540043761c9902e96ebc13a06189b1c1db1a20f\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlUnusedFallbackBinding = "_h00b3e68ab7";
r.NativeCallAdapter intlUnusedFallbackAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "00b3e68ab780815e2e04cf3e2e54a5eeab496bd354734614cc9e7fd492f36a3b"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.plural(1,
          name: "items", args: [1], other: throw StateError('unused fallback'));
      return _restageResult;
    });
s.ValueProgram intlUnusedFallbackProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h00b3e68ab7\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"00b3e68ab780815e2e04cf3e2e54a5eeab496bd354734614cc9e7fd492f36a3b\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlMetadataFailureBinding = "_hf053c2b953";
r.NativeCallAdapter intlMetadataFailureAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "f053c2b953461d2183c25445b6f6bdc0828fee78473d1ce2a13edb6079206648"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.message('fallback',
          name: "noArgs", desc: throw ArgumentError('metadata'));
      return _restageResult;
    });
s.ValueProgram intlMetadataFailureProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hf053c2b953\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"f053c2b953461d2183c25445b6f6bdc0828fee78473d1ce2a13edb6079206648\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlLiveCountBinding = "_h84706c3758";
r.NativeCallAdapter intlLiveCountAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{
              "_restageCapture0": <String, Object?>{"kind": "int"}
            },
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "84706c37585d4c6743d501e7367754da5a2867a337725521c3054125aa4683ac"
          }
        }), (_restageInputs, _restageCells) {
      final _restageCapture0 = _restageCells["_restageCapture0"]!.cast<int>();
      final String _restageResult = i.Intl.message('fallback',
          name: "items", args: [_restageCapture0.value++]);
      return _restageResult;
    });
s.ValueProgram intlLiveCountProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h84706c3758\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{\"_restageCapture0\":{\"kind\":\"int\"}},\"result\":{\"kind\":\"String\"},\"implementation\":\"84706c37585d4c6743d501e7367754da5a2867a337725521c3054125aa4683ac\"}},\"captures\":{\"_restageCapture0\":\"count\"}}}],\"root\":0,\"captures\":{},\"parameters\":{},\"outerLocals\":{\"count\":{\"kind\":\"int\"}}}",
        operations: operations,
        context: context);
const intlPluralMeaningBinding = "_hcafec75392";
r.NativeCallAdapter intlPluralMeaningAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "cafec75392e28f786edc1e84e31dc36d9be47a468a5818a4427983384b5cdaf5"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.plural(1, other: 'fallback', meaning: "secret");
      return _restageResult;
    });
s.ValueProgram intlPluralMeaningProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hcafec75392\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"cafec75392e28f786edc1e84e31dc36d9be47a468a5818a4427983384b5cdaf5\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlGenderMeaningBinding = "_hed8a1c4fb4";
r.NativeCallAdapter intlGenderMeaningAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "ed8a1c4fb436e70c0d3146e321dd6447643fcca681f9b90022dd365a68084b1b"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.gender('male', other: 'fallback', meaning: "secret");
      return _restageResult;
    });
s.ValueProgram intlGenderMeaningProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hed8a1c4fb4\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"ed8a1c4fb436e70c0d3146e321dd6447643fcca681f9b90022dd365a68084b1b\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlSelectMeaningBinding = "_he460169177";
r.NativeCallAdapter intlSelectMeaningAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "e4601691775a6f4f1ae20faa34282302a4c369490c479857672bf5d10db3cf25"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.select('active', {'other': 'fallback'}, meaning: "secret");
      return _restageResult;
    });
s.ValueProgram intlSelectMeaningProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_he460169177\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"e4601691775a6f4f1ae20faa34282302a4c369490c479857672bf5d10db3cf25\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlPluralNullMeaningNameBinding = "_h697db2584b";
r.NativeCallAdapter intlPluralNullMeaningNameAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "697db2584b2fadf7a2dafa34dfe6c901512f7239e6b2f3834b38f7464c7e90c7"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.plural(1,
          other: 'fallback', meaning: "secret", name: null, args: null);
      return _restageResult;
    });
s.ValueProgram intlPluralNullMeaningNameProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h697db2584b\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"697db2584b2fadf7a2dafa34dfe6c901512f7239e6b2f3834b38f7464c7e90c7\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlGenderNullMeaningNameBinding = "_hf51c482d0d";
r.NativeCallAdapter intlGenderNullMeaningNameAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "f51c482d0dcf8bcfb2d31b8c985060c59d49feb165365cd7c1a7f4b314b31918"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.gender('male',
          other: 'fallback', meaning: "secret", name: null, args: null);
      return _restageResult;
    });
s.ValueProgram intlGenderNullMeaningNameProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hf51c482d0d\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"f51c482d0dcf8bcfb2d31b8c985060c59d49feb165365cd7c1a7f4b314b31918\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlSelectNullMeaningNameBinding = "_h59f13ec113";
r.NativeCallAdapter intlSelectNullMeaningNameAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "59f13ec113ee240c707c8fc1028665e9a4e56304c8c4fe200ed01503261f132d"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.select(
          'active', {'other': 'fallback'},
          meaning: "secret", name: null, args: null);
      return _restageResult;
    });
s.ValueProgram intlSelectNullMeaningNameProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h59f13ec113\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"59f13ec113ee240c707c8fc1028665e9a4e56304c8c4fe200ed01503261f132d\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlNestedPluralMeaningBinding = "_h0887c1e024";
r.NativeCallAdapter intlNestedPluralMeaningAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "0887c1e0249837eb818bc6d5f049c8a97e2cc5f60dded28c2e88fa92ee35ce7f"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.message('fallback',
          name: "noArgs",
          desc: i.Intl.plural(1, other: 'fallback', meaning: "secret"));
      return _restageResult;
    });
s.ValueProgram intlNestedPluralMeaningProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h0887c1e024\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"0887c1e0249837eb818bc6d5f049c8a97e2cc5f60dded28c2e88fa92ee35ce7f\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlNestedGenderMeaningBinding = "_h76af519a58";
r.NativeCallAdapter intlNestedGenderMeaningAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "76af519a58271b17520207eb1ce7f23330603aaed36df983579ff82ab2f96087"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.message('fallback',
          name: "noArgs",
          desc: i.Intl.gender('male', other: 'fallback', meaning: "secret"));
      return _restageResult;
    });
s.ValueProgram intlNestedGenderMeaningProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h76af519a58\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"76af519a58271b17520207eb1ce7f23330603aaed36df983579ff82ab2f96087\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlNestedSelectMeaningBinding = "_hd2cac75e68";
r.NativeCallAdapter intlNestedSelectMeaningAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "d2cac75e683d2743da2950fd7c1dc98f1a1c49d57564aeebdb0a128bf16f717c"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.message('fallback',
          name: "noArgs",
          desc: i.Intl.select('active', {'other': 'fallback'},
              meaning: "secret"));
      return _restageResult;
    });
s.ValueProgram intlNestedSelectMeaningProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hd2cac75e68\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"d2cac75e683d2743da2950fd7c1dc98f1a1c49d57564aeebdb0a128bf16f717c\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlWidgetBinding = "_h59e1a1eaf5";
r.NativeCallAdapter intlWidgetAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "59e1a1eaf5caf8b38a4c9a0a63afe66a1c7576cf63cd540006710b3014e68637"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.message('fallback', name: "noArgs", args: []);
      return _restageResult;
    });
s.BuilderProgram intlWidgetProgram(Map<String, s.ValueOperation> operations) =>
    s.BuilderProgram.decode(
        "{\"version\":1,\"values\":{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}},\"name\":\"arg1\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h59e1a1eaf5\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"59e1a1eaf5caf8b38a4c9a0a63afe66a1c7576cf63cd540006710b3014e68637\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{\"arg1\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}}}},\"result\":{\"kind\":\"let\",\"node\":1,\"then\":{\"kind\":\"let\",\"node\":1,\"then\":{\"kind\":\"body\",\"body\":0,\"values\":{\"v0\":1}}}},\"bodyCount\":1,\"nullableResult\":false}",
        operations: operations);
const intlNullPluralBinding = "_h8088346dbd";
r.NativeCallAdapter intlNullPluralAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "8088346dbdd6cb08c0dd2a9318be6c9eb9b6f45af40b6355c65ba3ae8d1e2fe1"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.message('fallback',
          name: "noArgs",
          desc: i.Intl.plural(1, other: 'fallback', meaning: null));
      return _restageResult;
    });
s.BuilderProgram intlNullPluralProgram(
        Map<String, s.ValueOperation> operations) =>
    s.BuilderProgram.decode(
        "{\"version\":1,\"values\":{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}},\"name\":\"arg1\"},{\"op\":\"literal\",\"type\":{\"kind\":\"bool\"},\"value\":true},{\"op\":\"literal\",\"type\":{\"kind\":\"Null\",\"nullable\":true},\"value\":null},{\"op\":\"literal\",\"type\":{\"kind\":\"String\"},\"value\":\"secret\"},{\"op\":\"conditional\",\"type\":{\"kind\":\"String\",\"nullable\":true},\"inputs\":[1,2,3]},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h8088346dbd\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"8088346dbdd6cb08c0dd2a9318be6c9eb9b6f45af40b6355c65ba3ae8d1e2fe1\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{\"arg1\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}}}},\"result\":{\"kind\":\"let\",\"node\":4,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"body\",\"body\":0,\"values\":{\"v0\":5}}}}},\"bodyCount\":1,\"nullableResult\":false}",
        operations: operations);
const intlNullGenderBinding = "_h0b33ff9e6c";
r.NativeCallAdapter intlNullGenderAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "0b33ff9e6c49ea07815ea5d3d4a18cd8fbf05368ba7b46d88e5ae1a1af62cf83"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.message('fallback',
          name: "noArgs",
          desc: i.Intl.gender('male', other: 'fallback', meaning: null));
      return _restageResult;
    });
s.BuilderProgram intlNullGenderProgram(
        Map<String, s.ValueOperation> operations) =>
    s.BuilderProgram.decode(
        "{\"version\":1,\"values\":{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}},\"name\":\"arg1\"},{\"op\":\"literal\",\"type\":{\"kind\":\"bool\"},\"value\":true},{\"op\":\"literal\",\"type\":{\"kind\":\"Null\",\"nullable\":true},\"value\":null},{\"op\":\"literal\",\"type\":{\"kind\":\"String\"},\"value\":\"secret\"},{\"op\":\"conditional\",\"type\":{\"kind\":\"String\",\"nullable\":true},\"inputs\":[1,2,3]},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h0b33ff9e6c\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"0b33ff9e6c49ea07815ea5d3d4a18cd8fbf05368ba7b46d88e5ae1a1af62cf83\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{\"arg1\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}}}},\"result\":{\"kind\":\"let\",\"node\":4,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"body\",\"body\":0,\"values\":{\"v0\":5}}}}},\"bodyCount\":1,\"nullableResult\":false}",
        operations: operations);
const intlNullSelectBinding = "_h8fcce5a948";
r.NativeCallAdapter intlNullSelectAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "8fcce5a9487f519e2791483e5c6f781d390e0db842769b5498bb8bc53d497783"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.message('fallback',
          name: "noArgs",
          desc: i.Intl.select('active', {'other': 'fallback'}, meaning: null));
      return _restageResult;
    });
s.BuilderProgram intlNullSelectProgram(
        Map<String, s.ValueOperation> operations) =>
    s.BuilderProgram.decode(
        "{\"version\":1,\"values\":{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}},\"name\":\"arg1\"},{\"op\":\"literal\",\"type\":{\"kind\":\"bool\"},\"value\":true},{\"op\":\"literal\",\"type\":{\"kind\":\"Null\",\"nullable\":true},\"value\":null},{\"op\":\"literal\",\"type\":{\"kind\":\"String\"},\"value\":\"secret\"},{\"op\":\"conditional\",\"type\":{\"kind\":\"String\",\"nullable\":true},\"inputs\":[1,2,3]},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h8fcce5a948\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"8fcce5a9487f519e2791483e5c6f781d390e0db842769b5498bb8bc53d497783\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{\"arg1\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}}}},\"result\":{\"kind\":\"let\",\"node\":4,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"body\",\"body\":0,\"values\":{\"v0\":5}}}}},\"bodyCount\":1,\"nullableResult\":false}",
        operations: operations);
const intlAliasNullPluralBinding = "_h41b73bbc24";
r.NativeCallAdapter intlAliasNullPluralAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "41b73bbc2488720a320722d1ea47e35b6883f688ed229a128899925bf59a1551"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.message('fallback',
          name: "noArgs",
          desc: pluralLookupAlias(1, other: 'fallback', meaning: null));
      return _restageResult;
    });
s.BuilderProgram intlAliasNullPluralProgram(
        Map<String, s.ValueOperation> operations) =>
    s.BuilderProgram.decode(
        "{\"version\":1,\"values\":{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}},\"name\":\"arg1\"},{\"op\":\"literal\",\"type\":{\"kind\":\"bool\"},\"value\":true},{\"op\":\"literal\",\"type\":{\"kind\":\"Null\",\"nullable\":true},\"value\":null},{\"op\":\"literal\",\"type\":{\"kind\":\"String\"},\"value\":\"secret\"},{\"op\":\"conditional\",\"type\":{\"kind\":\"String\",\"nullable\":true},\"inputs\":[1,2,3]},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h41b73bbc24\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"41b73bbc2488720a320722d1ea47e35b6883f688ed229a128899925bf59a1551\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{\"arg1\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}}}},\"result\":{\"kind\":\"let\",\"node\":4,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"body\",\"body\":0,\"values\":{\"v0\":5}}}}},\"bodyCount\":1,\"nullableResult\":false}",
        operations: operations);
const intlAliasNullGenderBinding = "_h4fb54bbdab";
r.NativeCallAdapter intlAliasNullGenderAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "4fb54bbdab9ef8c3c575aca39cc7910b5e43f7a8a35f8602c747192825b947bd"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.message('fallback',
          name: "noArgs",
          desc: genderLookupAlias('male', other: 'fallback', meaning: null));
      return _restageResult;
    });
s.BuilderProgram intlAliasNullGenderProgram(
        Map<String, s.ValueOperation> operations) =>
    s.BuilderProgram.decode(
        "{\"version\":1,\"values\":{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}},\"name\":\"arg1\"},{\"op\":\"literal\",\"type\":{\"kind\":\"bool\"},\"value\":true},{\"op\":\"literal\",\"type\":{\"kind\":\"Null\",\"nullable\":true},\"value\":null},{\"op\":\"literal\",\"type\":{\"kind\":\"String\"},\"value\":\"secret\"},{\"op\":\"conditional\",\"type\":{\"kind\":\"String\",\"nullable\":true},\"inputs\":[1,2,3]},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h4fb54bbdab\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"4fb54bbdab9ef8c3c575aca39cc7910b5e43f7a8a35f8602c747192825b947bd\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{\"arg1\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}}}},\"result\":{\"kind\":\"let\",\"node\":4,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"body\",\"body\":0,\"values\":{\"v0\":5}}}}},\"bodyCount\":1,\"nullableResult\":false}",
        operations: operations);
const intlAliasNullSelectBinding = "_he7ca818320";
r.NativeCallAdapter intlAliasNullSelectAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "e7ca818320149969f774c4634f8c4eda105570b48161737cbf639b2b312ea02f"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.message('fallback',
          name: "noArgs",
          desc: selectLookupAlias('active', {'other': 'fallback'},
              meaning: null));
      return _restageResult;
    });
s.BuilderProgram intlAliasNullSelectProgram(
        Map<String, s.ValueOperation> operations) =>
    s.BuilderProgram.decode(
        "{\"version\":1,\"values\":{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}},\"name\":\"arg1\"},{\"op\":\"literal\",\"type\":{\"kind\":\"bool\"},\"value\":true},{\"op\":\"literal\",\"type\":{\"kind\":\"Null\",\"nullable\":true},\"value\":null},{\"op\":\"literal\",\"type\":{\"kind\":\"String\"},\"value\":\"secret\"},{\"op\":\"conditional\",\"type\":{\"kind\":\"String\",\"nullable\":true},\"inputs\":[1,2,3]},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_he7ca818320\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"e7ca818320149969f774c4634f8c4eda105570b48161737cbf639b2b312ea02f\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{\"arg1\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}}}},\"result\":{\"kind\":\"let\",\"node\":4,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"body\",\"body\":0,\"values\":{\"v0\":5}}}}},\"bodyCount\":1,\"nullableResult\":false}",
        operations: operations);
