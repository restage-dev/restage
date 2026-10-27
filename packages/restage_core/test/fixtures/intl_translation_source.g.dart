// Direct-throw arguments leave the adapter return unreachable.
// ignore_for_file: dead_code
part of 'intl_translation_source.dart';

const intlMessageBinding = "_h8b6cc2ed28";
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
                "8b6cc2ed286a73b02e1c1c75e7b74f0592133088b5675dee42b537f5f635a260"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"String\"},\"name\":\"user\"},{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"dart.DateTime\"},\"name\":\"date\"},{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"translation.Token\"},\"name\":\"token\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"inputs\":[0,1,2],\"value\":{\"binding\":\"_h8b6cc2ed28\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"String\"},{\"kind\":\"native\",\"nativeType\":\"dart.DateTime\"},{\"kind\":\"native\",\"nativeType\":\"translation.Token\"}],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"8b6cc2ed286a73b02e1c1c75e7b74f0592133088b5675dee42b537f5f635a260\"}},\"captures\":{}}}],\"root\":3,\"captures\":{},\"parameters\":{\"user\":{\"kind\":\"String\"},\"date\":{\"kind\":\"native\",\"nativeType\":\"dart.DateTime\"},\"token\":{\"kind\":\"native\",\"nativeType\":\"translation.Token\"}}}",
        operations: operations,
        context: context);
const intlPluralBinding = "_h8b8840db9f";
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
                "8b8840db9f74233ebe455b27e0495a289332f1d4f93acacce2245a208a6a5431"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"int\"},\"name\":\"count\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"inputs\":[0],\"value\":{\"binding\":\"_h8b8840db9f\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"int\"}],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"8b8840db9f74233ebe455b27e0495a289332f1d4f93acacce2245a208a6a5431\"}},\"captures\":{}}}],\"root\":1,\"captures\":{},\"parameters\":{\"count\":{\"kind\":\"int\"}}}",
        operations: operations,
        context: context);
const intlGenderBinding = "_ha4a2b64fc4";
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
                "a4a2b64fc422edfe98756b9e8593469e7952f2f3218c2df1a967b2f7c4dca1f2"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"String\"},\"name\":\"gender\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"inputs\":[0],\"value\":{\"binding\":\"_ha4a2b64fc4\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"String\"}],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"a4a2b64fc422edfe98756b9e8593469e7952f2f3218c2df1a967b2f7c4dca1f2\"}},\"captures\":{}}}],\"root\":1,\"captures\":{},\"parameters\":{\"gender\":{\"kind\":\"String\"}}}",
        operations: operations,
        context: context);
const intlSelectBinding = "_h22991a222a";
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
                "22991a222a9b8ad5f3f1608ca85b97aa8ca64b467d4a3404ff1d002a88626cdd"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"translation.Status\"},\"name\":\"choice\"},{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"translation.Token\"},\"name\":\"token\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"inputs\":[0,1],\"value\":{\"binding\":\"_h22991a222a\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"native\",\"nativeType\":\"translation.Status\"},{\"kind\":\"native\",\"nativeType\":\"translation.Token\"}],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"22991a222a9b8ad5f3f1608ca85b97aa8ca64b467d4a3404ff1d002a88626cdd\"}},\"captures\":{}}}],\"root\":2,\"captures\":{},\"parameters\":{\"choice\":{\"kind\":\"native\",\"nativeType\":\"translation.Status\"},\"token\":{\"kind\":\"native\",\"nativeType\":\"translation.Token\"}}}",
        operations: operations,
        context: context);
const intlAbsentArgsBinding = "_h91b5bbe40f";
r.NativeCallAdapter intlAbsentArgsAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "91b5bbe40fe8f3436d7057c30dc337059b91521e841ab2c1d22db838982e5c65"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.message('fallback', name: "noArgs");
      return _restageResult;
    });
s.ValueProgram intlAbsentArgsProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h91b5bbe40f\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"91b5bbe40fe8f3436d7057c30dc337059b91521e841ab2c1d22db838982e5c65\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlNullArgsBinding = "_h293d75c26d";
r.NativeCallAdapter intlNullArgsAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "293d75c26d819bcd2b6d0f0bdd387bae962db6299489419c79a0fe1a31ffe38c"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.message('fallback', name: "noArgs", args: null);
      return _restageResult;
    });
s.ValueProgram intlNullArgsProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h293d75c26d\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"293d75c26d819bcd2b6d0f0bdd387bae962db6299489419c79a0fe1a31ffe38c\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlEmptyArgsBinding = "_hf029cf7fa2";
r.NativeCallAdapter intlEmptyArgsAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "f029cf7fa2cf4c72717df9dcc8721799f17bd7f54865729b206055f292f0eb4c"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.message('fallback', name: "noArgs", args: []);
      return _restageResult;
    });
s.ValueProgram intlEmptyArgsProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hf029cf7fa2\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"f029cf7fa2cf4c72717df9dcc8721799f17bd7f54865729b206055f292f0eb4c\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlMissingBinding = "_hcc6d4406c7";
r.NativeCallAdapter intlMissingAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "cc6d4406c7a13224223ea7f9f4e8366c0a91ebf552e0e7a2ea31753c2d5df5a5"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.message('untranslated', name: "absent", args: []);
      return _restageResult;
    });
s.ValueProgram intlMissingProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hcc6d4406c7\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"cc6d4406c7a13224223ea7f9f4e8366c0a91ebf552e0e7a2ea31753c2d5df5a5\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlNullNameBinding = "_he1b3ad3301";
r.NativeCallAdapter intlNullNameAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "e1b3ad330127b9828161e69c69df1ba612da85fe2c1c2743d75febd988e76282"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.message("unnamed", name: null, args: [1]);
      return _restageResult;
    });
s.ValueProgram intlNullNameProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_he1b3ad3301\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"e1b3ad330127b9828161e69c69df1ba612da85fe2c1c2743d75febd988e76282\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlImplicitNameBinding = "_h819b270073";
r.NativeCallAdapter intlImplicitNameAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "819b2700734fc94c3db1e25a2227515e6795034138b01c089e3f48ed4f6ef906"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.message("implicit");
      return _restageResult;
    });
s.ValueProgram intlImplicitNameProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h819b270073\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"819b2700734fc94c3db1e25a2227515e6795034138b01c089e3f48ed4f6ef906\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlEmptyNameBinding = "_hbc60adad77";
r.NativeCallAdapter intlEmptyNameAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "bc60adad77be748e5f8e850a44e10d0e17ba3716ca0e6fd3037bf95213814e12"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = i.Intl.message("implicit", name: "");
      return _restageResult;
    });
s.ValueProgram intlEmptyNameProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hbc60adad77\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"bc60adad77be748e5f8e850a44e10d0e17ba3716ca0e6fd3037bf95213814e12\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlMeaningBinding = "_h6ad8997f72";
r.NativeCallAdapter intlMeaningAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "6ad8997f723e90cb3ae2176f4e4838a595bd5a9d4a78fe6e3c0259b347f68b25"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.message("implicit", meaning: "context");
      return _restageResult;
    });
s.ValueProgram intlMeaningProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h6ad8997f72\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"6ad8997f723e90cb3ae2176f4e4838a595bd5a9d4a78fe6e3c0259b347f68b25\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlWrongArityBinding = "_h0e495f690b";
r.NativeCallAdapter intlWrongArityAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "0e495f690b97cf307b7861fd63e3e750293cafb43e28cd95d63cac66f52199c0"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.message('fallback', name: "wrongArity", args: [1]);
      return _restageResult;
    });
s.ValueProgram intlWrongArityProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h0e495f690b\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"0e495f690b97cf307b7861fd63e3e750293cafb43e28cd95d63cac66f52199c0\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlWrongTypeBinding = "_h25ef464815";
r.NativeCallAdapter intlWrongTypeAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "25ef464815a72ce4869f87313fda00ea96ede2b6b4c09124513013848ad8e62a"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.message('fallback', name: "wrongType", args: ['bad']);
      return _restageResult;
    });
s.ValueProgram intlWrongTypeProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h25ef464815\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"25ef464815a72ce4869f87313fda00ea96ede2b6b4c09124513013848ad8e62a\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlOrderedBinding = "_hd11c17fd81";
r.NativeCallAdapter intlOrderedAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "d11c17fd81e869b2be4aa8f58fe10a42c7aae3ab76ecffdeece01a28d07ab568"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hd11c17fd81\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"d11c17fd81e869b2be4aa8f58fe10a42c7aae3ab76ecffdeece01a28d07ab568\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlUnusedFallbackBinding = "_h4970499eab";
r.NativeCallAdapter intlUnusedFallbackAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "4970499eaba7e20c65fa0c859e2d490a77c19b9c344ffb01ffa5a17148e2c7d9"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h4970499eab\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"4970499eaba7e20c65fa0c859e2d490a77c19b9c344ffb01ffa5a17148e2c7d9\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlMetadataFailureBinding = "_h0348662969";
r.NativeCallAdapter intlMetadataFailureAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "03486629693fdc77574095aef8b85aa102e3914c13aa498ce46999adf2e91614"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h0348662969\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"03486629693fdc77574095aef8b85aa102e3914c13aa498ce46999adf2e91614\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlLiveCountBinding = "_hb09beb0bc2";
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
                "b09beb0bc251f26b3e9447df50b7c9056aaebd2cc9e3eb9f739c43dc8b929efc"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hb09beb0bc2\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{\"_restageCapture0\":{\"kind\":\"int\"}},\"result\":{\"kind\":\"String\"},\"implementation\":\"b09beb0bc251f26b3e9447df50b7c9056aaebd2cc9e3eb9f739c43dc8b929efc\"}},\"captures\":{\"_restageCapture0\":\"count\"}}}],\"root\":0,\"captures\":{},\"parameters\":{},\"outerLocals\":{\"count\":{\"kind\":\"int\"}}}",
        operations: operations,
        context: context);
const intlPluralMeaningBinding = "_h03556ed34b";
r.NativeCallAdapter intlPluralMeaningAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "03556ed34b5ea556a7341d1a4a20f81ccbb127b3b342b325cbb8f692e4e8361a"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h03556ed34b\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"03556ed34b5ea556a7341d1a4a20f81ccbb127b3b342b325cbb8f692e4e8361a\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlGenderMeaningBinding = "_ha8f44146e1";
r.NativeCallAdapter intlGenderMeaningAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "a8f44146e1f7b2efb0b778ad4224388b406f49a49b7e6bc65b99280f65155708"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_ha8f44146e1\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"a8f44146e1f7b2efb0b778ad4224388b406f49a49b7e6bc65b99280f65155708\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlSelectMeaningBinding = "_h3ead81f84d";
r.NativeCallAdapter intlSelectMeaningAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "3ead81f84dafefe47596afda5d08f48d39d8ceb086f1600472faa9c68fe17b1e"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h3ead81f84d\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"3ead81f84dafefe47596afda5d08f48d39d8ceb086f1600472faa9c68fe17b1e\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlPluralNullMeaningNameBinding = "_h9805910114";
r.NativeCallAdapter intlPluralNullMeaningNameAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "9805910114d84728d4279b53f7c8f481f433dc073b81532e79ac1c249726331f"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h9805910114\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"9805910114d84728d4279b53f7c8f481f433dc073b81532e79ac1c249726331f\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlGenderNullMeaningNameBinding = "_hdd30d15ad9";
r.NativeCallAdapter intlGenderNullMeaningNameAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "dd30d15ad94c1c44fcedd20a556da9a6cc2444c68c8ded2da4469f6df5f74c76"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hdd30d15ad9\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"dd30d15ad94c1c44fcedd20a556da9a6cc2444c68c8ded2da4469f6df5f74c76\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlSelectNullMeaningNameBinding = "_h7d47c691f1";
r.NativeCallAdapter intlSelectNullMeaningNameAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "7d47c691f1be6b0541fa1b7aa40f31c9d3875cd117a51020879aba88793b1af8"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h7d47c691f1\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"7d47c691f1be6b0541fa1b7aa40f31c9d3875cd117a51020879aba88793b1af8\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlNestedPluralMeaningBinding = "_hf87bb96eea";
r.NativeCallAdapter intlNestedPluralMeaningAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "f87bb96eea82a76e3da073cf10abb41c4dcc78c5437fe5bd1672cc6e0e26a62a"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hf87bb96eea\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"f87bb96eea82a76e3da073cf10abb41c4dcc78c5437fe5bd1672cc6e0e26a62a\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlNestedGenderMeaningBinding = "_h5e09cef186";
r.NativeCallAdapter intlNestedGenderMeaningAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "5e09cef1865d01ea0e429b980fb842bbbff868765aef8b9d632a0cb0fab3902e"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h5e09cef186\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"5e09cef1865d01ea0e429b980fb842bbbff868765aef8b9d632a0cb0fab3902e\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlNestedSelectMeaningBinding = "_h8ea941b548";
r.NativeCallAdapter intlNestedSelectMeaningAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "8ea941b54881646c2edaa76da8e66ce41ac5ca34f39fbaf4ae17f055eca2b5f9"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h8ea941b548\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"8ea941b54881646c2edaa76da8e66ce41ac5ca34f39fbaf4ae17f055eca2b5f9\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const intlWidgetBinding = "_hf029cf7fa2";
r.NativeCallAdapter intlWidgetAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "f029cf7fa2cf4c72717df9dcc8721799f17bd7f54865729b206055f292f0eb4c"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult =
          i.Intl.message('fallback', name: "noArgs", args: []);
      return _restageResult;
    });
s.BuilderProgram intlWidgetProgram(Map<String, s.ValueOperation> operations) =>
    s.BuilderProgram.decode(
        "{\"version\":1,\"values\":{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}},\"name\":\"arg1\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hf029cf7fa2\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"f029cf7fa2cf4c72717df9dcc8721799f17bd7f54865729b206055f292f0eb4c\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{\"arg1\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}}}},\"result\":{\"kind\":\"let\",\"node\":1,\"then\":{\"kind\":\"let\",\"node\":1,\"then\":{\"kind\":\"body\",\"body\":0,\"values\":{\"v0\":1}}}},\"bodyCount\":1,\"nullableResult\":false}",
        operations: operations);
const intlNullPluralBinding = "_hd898a4316f";
r.NativeCallAdapter intlNullPluralAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "d898a4316f37dd289241f6faffcd11cd98e127e15726937465c7a87e70ca2974"
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
        "{\"version\":1,\"values\":{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}},\"name\":\"arg1\"},{\"op\":\"literal\",\"type\":{\"kind\":\"bool\"},\"value\":true},{\"op\":\"literal\",\"type\":{\"kind\":\"Null\",\"nullable\":true},\"value\":null},{\"op\":\"literal\",\"type\":{\"kind\":\"String\"},\"value\":\"secret\"},{\"op\":\"conditional\",\"type\":{\"kind\":\"String\",\"nullable\":true},\"inputs\":[1,2,3]},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_hd898a4316f\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"d898a4316f37dd289241f6faffcd11cd98e127e15726937465c7a87e70ca2974\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{\"arg1\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}}}},\"result\":{\"kind\":\"let\",\"node\":4,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"body\",\"body\":0,\"values\":{\"v0\":5}}}}},\"bodyCount\":1,\"nullableResult\":false}",
        operations: operations);
const intlNullGenderBinding = "_heea8d88bf4";
r.NativeCallAdapter intlNullGenderAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "eea8d88bf44aea98ac935242ab627dae556aa3ba1ed3a12bf25c9c69f72cd6c1"
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
        "{\"version\":1,\"values\":{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}},\"name\":\"arg1\"},{\"op\":\"literal\",\"type\":{\"kind\":\"bool\"},\"value\":true},{\"op\":\"literal\",\"type\":{\"kind\":\"Null\",\"nullable\":true},\"value\":null},{\"op\":\"literal\",\"type\":{\"kind\":\"String\"},\"value\":\"secret\"},{\"op\":\"conditional\",\"type\":{\"kind\":\"String\",\"nullable\":true},\"inputs\":[1,2,3]},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_heea8d88bf4\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"eea8d88bf44aea98ac935242ab627dae556aa3ba1ed3a12bf25c9c69f72cd6c1\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{\"arg1\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}}}},\"result\":{\"kind\":\"let\",\"node\":4,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"body\",\"body\":0,\"values\":{\"v0\":5}}}}},\"bodyCount\":1,\"nullableResult\":false}",
        operations: operations);
const intlNullSelectBinding = "_ha6a8282877";
r.NativeCallAdapter intlNullSelectAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "a6a8282877606373f2f6c0ca04e4a051deadb14bb85259e8fc39e9e9a60e5165"
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
        "{\"version\":1,\"values\":{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}},\"name\":\"arg1\"},{\"op\":\"literal\",\"type\":{\"kind\":\"bool\"},\"value\":true},{\"op\":\"literal\",\"type\":{\"kind\":\"Null\",\"nullable\":true},\"value\":null},{\"op\":\"literal\",\"type\":{\"kind\":\"String\"},\"value\":\"secret\"},{\"op\":\"conditional\",\"type\":{\"kind\":\"String\",\"nullable\":true},\"inputs\":[1,2,3]},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_ha6a8282877\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"a6a8282877606373f2f6c0ca04e4a051deadb14bb85259e8fc39e9e9a60e5165\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{\"arg1\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}}}},\"result\":{\"kind\":\"let\",\"node\":4,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"body\",\"body\":0,\"values\":{\"v0\":5}}}}},\"bodyCount\":1,\"nullableResult\":false}",
        operations: operations);
const intlAliasNullPluralBinding = "_h2214301ac8";
r.NativeCallAdapter intlAliasNullPluralAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "2214301ac88aef9c700bd1f05baafdf66b9690688599e8bff1403ab9690f21e9"
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
        "{\"version\":1,\"values\":{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}},\"name\":\"arg1\"},{\"op\":\"literal\",\"type\":{\"kind\":\"bool\"},\"value\":true},{\"op\":\"literal\",\"type\":{\"kind\":\"Null\",\"nullable\":true},\"value\":null},{\"op\":\"literal\",\"type\":{\"kind\":\"String\"},\"value\":\"secret\"},{\"op\":\"conditional\",\"type\":{\"kind\":\"String\",\"nullable\":true},\"inputs\":[1,2,3]},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h2214301ac8\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"2214301ac88aef9c700bd1f05baafdf66b9690688599e8bff1403ab9690f21e9\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{\"arg1\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}}}},\"result\":{\"kind\":\"let\",\"node\":4,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"body\",\"body\":0,\"values\":{\"v0\":5}}}}},\"bodyCount\":1,\"nullableResult\":false}",
        operations: operations);
const intlAliasNullGenderBinding = "_h669f9f4b29";
r.NativeCallAdapter intlAliasNullGenderAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "669f9f4b29fa5a4d009170fcc36a14c4a088c1b944c7266588746a8062cd8e32"
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
        "{\"version\":1,\"values\":{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}},\"name\":\"arg1\"},{\"op\":\"literal\",\"type\":{\"kind\":\"bool\"},\"value\":true},{\"op\":\"literal\",\"type\":{\"kind\":\"Null\",\"nullable\":true},\"value\":null},{\"op\":\"literal\",\"type\":{\"kind\":\"String\"},\"value\":\"secret\"},{\"op\":\"conditional\",\"type\":{\"kind\":\"String\",\"nullable\":true},\"inputs\":[1,2,3]},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h669f9f4b29\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"669f9f4b29fa5a4d009170fcc36a14c4a088c1b944c7266588746a8062cd8e32\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{\"arg1\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}}}},\"result\":{\"kind\":\"let\",\"node\":4,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"body\",\"body\":0,\"values\":{\"v0\":5}}}}},\"bodyCount\":1,\"nullableResult\":false}",
        operations: operations);
const intlAliasNullSelectBinding = "_h9e935980da";
r.NativeCallAdapter intlAliasNullSelectAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "9e935980da4cd0da1c756a431d342c7ddfa32f757eeaf44d366afceb9c5064f3"
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
        "{\"version\":1,\"values\":{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}},\"name\":\"arg1\"},{\"op\":\"literal\",\"type\":{\"kind\":\"bool\"},\"value\":true},{\"op\":\"literal\",\"type\":{\"kind\":\"Null\",\"nullable\":true},\"value\":null},{\"op\":\"literal\",\"type\":{\"kind\":\"String\"},\"value\":\"secret\"},{\"op\":\"conditional\",\"type\":{\"kind\":\"String\",\"nullable\":true},\"inputs\":[1,2,3]},{\"op\":\"native.call\",\"type\":{\"kind\":\"String\"},\"value\":{\"binding\":\"_h9e935980da\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"String\"},\"implementation\":\"9e935980da4cd0da1c756a431d342c7ddfa32f757eeaf44d366afceb9c5064f3\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{\"arg1\":{\"kind\":\"record\",\"fields\":{\"minWidth\":{\"kind\":\"double\"},\"maxWidth\":{\"kind\":\"double\"},\"minHeight\":{\"kind\":\"double\"},\"maxHeight\":{\"kind\":\"double\"},\"hasBoundedWidth\":{\"kind\":\"bool\"},\"hasBoundedHeight\":{\"kind\":\"bool\"},\"hasTightWidth\":{\"kind\":\"bool\"},\"hasTightHeight\":{\"kind\":\"bool\"},\"isTight\":{\"kind\":\"bool\"},\"biggest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}},\"smallest\":{\"kind\":\"record\",\"fields\":{\"width\":{\"kind\":\"double\"},\"height\":{\"kind\":\"double\"}}}}}}},\"result\":{\"kind\":\"let\",\"node\":4,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"let\",\"node\":5,\"then\":{\"kind\":\"body\",\"body\":0,\"values\":{\"v0\":5}}}}},\"bodyCount\":1,\"nullableResult\":false}",
        operations: operations);
