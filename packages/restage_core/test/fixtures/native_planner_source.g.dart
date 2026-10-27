part of 'native_planner_source.dart';

const nativePlannerClosureBinding = "_h4024f41c38";
r.NativeCallAdapter nativePlannerClosureAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{
                "kind": "native",
                "nativeType": "callback.seen"
              },
              <String, Object?>{
                "kind": "native",
                "nativeType": "dart.List<Object>"
              }
            ],
            "captures": <String, Object?>{
              "_restageCapture0": <String, Object?>{"kind": "int"}
            },
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "callback"
            },
            "implementation":
                "4024f41c38b8c384160a33f84d8c6003c5c6090f2af3963160224f328ff549ef"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final void Function(f.TapDownDetails) _restageInput0 =
          _restageAs<void Function(f.TapDownDetails)>(
              (_restageInputs[0] as s.ValueNative).value);
      final List<Object> _restageInput1 =
          _restageAs<List<Object>>((_restageInputs[1] as s.ValueNative).value);
      final _restageCapture0 = _restageCells["_restageCapture0"]!.cast<int>();
      final f.ObjectKey Function(f.TapDownDetails) _restageResult =
          (f.TapDownDetails details) {
        _restageInput0(details);
        return f.ObjectKey(_restageInput1[_restageCapture0.value++]);
      };
      return r.NativeBinding<f.ObjectKey Function(f.TapDownDetails)>(
          contract: s.NativeBindingContract(type: "callback", nullable: false),
          value: _restageResult);
    });
s.ValueProgram nativePlannerClosureProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"callback.seen\"},\"name\":\"seen\"},{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"dart.List<Object>\"},\"name\":\"items\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"callback\"},\"inputs\":[0,1],\"value\":{\"binding\":\"_h4024f41c38\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"native\",\"nativeType\":\"callback.seen\"},{\"kind\":\"native\",\"nativeType\":\"dart.List<Object>\"}],\"captures\":{\"_restageCapture0\":{\"kind\":\"int\"}},\"result\":{\"kind\":\"native\",\"nativeType\":\"callback\"},\"implementation\":\"4024f41c38b8c384160a33f84d8c6003c5c6090f2af3963160224f328ff549ef\"}},\"captures\":{\"_restageCapture0\":\"counter\"}}}],\"root\":2,\"captures\":{},\"parameters\":{\"seen\":{\"kind\":\"native\",\"nativeType\":\"callback.seen\"},\"items\":{\"kind\":\"native\",\"nativeType\":\"dart.List<Object>\"}},\"outerLocals\":{\"counter\":{\"kind\":\"int\"}}}",
        operations: operations,
        context: context);
const nativePlannerKeyBinding = "_h5805774cb8";
r.NativeCallAdapter nativePlannerKeyAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{
                "kind": "native",
                "nativeType": "dart.List<Object>"
              },
              <String, Object?>{"kind": "int"}
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "flutter.Key"
            },
            "implementation":
                "5805774cb8f85d1e9b6d6a1798251cba5e4f6e24265103acb2d753faaad3169a"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final List<Object> _restageInput0 =
          _restageAs<List<Object>>((_restageInputs[0] as s.ValueNative).value);
      final int _restageInput1 = _restageAs<int>(_restageInputs[1]);
      final f.ObjectKey _restageResult =
          f.ObjectKey(_restageInput0[_restageInput1]);
      return r.NativeBinding<f.ObjectKey>(
          contract:
              s.NativeBindingContract(type: "flutter.Key", nullable: false),
          value: _restageResult);
    });
s.ValueProgram nativePlannerKeyProgram(Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"dart.List<Object>\"},\"name\":\"items\"},{\"op\":\"parameter\",\"type\":{\"kind\":\"int\"},\"name\":\"index\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"flutter.Key\"},\"inputs\":[0,1],\"value\":{\"binding\":\"_h5805774cb8\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"native\",\"nativeType\":\"dart.List<Object>\"},{\"kind\":\"int\"}],\"captures\":{},\"result\":{\"kind\":\"native\",\"nativeType\":\"flutter.Key\"},\"implementation\":\"5805774cb8f85d1e9b6d6a1798251cba5e4f6e24265103acb2d753faaad3169a\"}},\"captures\":{}}}],\"root\":2,\"captures\":{},\"parameters\":{\"items\":{\"kind\":\"native\",\"nativeType\":\"dart.List<Object>\"},\"index\":{\"kind\":\"int\"}}}",
        operations: operations,
        context: context);
const nativePlannerColorBinding = "_hc2cc8cad87";
r.NativeCallAdapter nativePlannerColorAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{
                "kind": "native",
                "nativeType": "dart.Map<int,Color>"
              }
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "flutter.Color"
            },
            "implementation":
                "c2cc8cad87cbc2a8f9cf5cb2ebfde27cf8e8e3e6aea26d4de0295b337a1bdf6f"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final Map<int, f.Color> _restageInput0 = _restageAs<Map<int, f.Color>>(
          (_restageInputs[0] as s.ValueNative).value);
      final f.MaterialColor _restageResult =
          f.MaterialColor(0xff102030, _restageInput0);
      return r.NativeBinding<f.MaterialColor>(
          contract:
              s.NativeBindingContract(type: "flutter.Color", nullable: false),
          value: _restageResult);
    });
s.ValueProgram nativePlannerColorProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"dart.Map<int,Color>\"},\"name\":\"swatch\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\"},\"inputs\":[0],\"value\":{\"binding\":\"_hc2cc8cad87\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"native\",\"nativeType\":\"dart.Map<int,Color>\"}],\"captures\":{},\"result\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\"},\"implementation\":\"c2cc8cad87cbc2a8f9cf5cb2ebfde27cf8e8e3e6aea26d4de0295b337a1bdf6f\"}},\"captures\":{}}}],\"root\":1,\"captures\":{},\"parameters\":{\"swatch\":{\"kind\":\"native\",\"nativeType\":\"dart.Map<int,Color>\"}}}",
        operations: operations,
        context: context);
const nativePlannerReassignBinding = "_h32db8e656c";
r.NativeCallAdapter nativePlannerReassignAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{"kind": "native", "nativeType": "dart.Object"}
            ],
            "captures": <String, Object?>{
              "_restageCapture0": <String, Object?>{
                "kind": "native",
                "nativeType": "dart.Object"
              }
            },
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "callback.reassign"
            },
            "implementation":
                "32db8e656c0ec8df1fec027fe92a2970ad1755959e4969e149e633a5f403eeaf"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final Object _restageInput0 =
          _restageAs<Object>((_restageInputs[0] as s.ValueNative).value);
      final _restageCapture0 =
          _restageCells["_restageCapture0"]!.cast<Object>();
      final f.ObjectKey Function() _restageResult = () {
        final old = _restageCapture0.value;
        _restageCapture0.value = _restageInput0;
        return f.ObjectKey(old);
      };
      return r.NativeBinding<f.ObjectKey Function()>(
          contract: s.NativeBindingContract(
              type: "callback.reassign", nullable: false),
          value: _restageResult);
    });
s.ValueProgram nativePlannerReassignProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"dart.Object\"},\"name\":\"replacement\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"callback.reassign\"},\"inputs\":[0],\"value\":{\"binding\":\"_h32db8e656c\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"native\",\"nativeType\":\"dart.Object\"}],\"captures\":{\"_restageCapture0\":{\"kind\":\"native\",\"nativeType\":\"dart.Object\"}},\"result\":{\"kind\":\"native\",\"nativeType\":\"callback.reassign\"},\"implementation\":\"32db8e656c0ec8df1fec027fe92a2970ad1755959e4969e149e633a5f403eeaf\"}},\"captures\":{\"_restageCapture0\":\"object\"}}}],\"root\":1,\"captures\":{},\"parameters\":{\"replacement\":{\"kind\":\"native\",\"nativeType\":\"dart.Object\"}},\"outerLocals\":{\"object\":{\"kind\":\"native\",\"nativeType\":\"dart.Object\"}}}",
        operations: operations,
        context: context);
const nativePlannerNullableBinding = "_h0e57b63812";
r.NativeCallAdapter nativePlannerNullableAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{
                "kind": "native",
                "nativeType": "dart.Object",
                "nullable": true
              }
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "flutter.Key",
              "nullable": true
            },
            "implementation":
                "0e57b63812c230d528d088b0b4f9022bc19c2b86ead4980e549bee0476bb94d8"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final Object? _restageInput0 = _restageAs<Object?>(
          (_restageInputs[0] == null
              ? null
              : (_restageInputs[0] as s.ValueNative).value));
      final f.ObjectKey? _restageResult = _restageInput0 == null
          ? null
          : f.ObjectKey(_restageAs<Object>(_restageInput0));
      if (_restageResult == null) return null;
      return r.NativeBinding<f.ObjectKey?>(
          contract:
              s.NativeBindingContract(type: "flutter.Key", nullable: true),
          value: _restageResult);
    });
s.ValueProgram nativePlannerNullableProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"dart.Object\",\"nullable\":true},\"name\":\"model\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"flutter.Key\",\"nullable\":true},\"inputs\":[0],\"value\":{\"binding\":\"_h0e57b63812\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"native\",\"nativeType\":\"dart.Object\",\"nullable\":true}],\"captures\":{},\"result\":{\"kind\":\"native\",\"nativeType\":\"flutter.Key\",\"nullable\":true},\"implementation\":\"0e57b63812c230d528d088b0b4f9022bc19c2b86ead4980e549bee0476bb94d8\"}},\"captures\":{}}}],\"root\":1,\"captures\":{},\"parameters\":{\"model\":{\"kind\":\"native\",\"nativeType\":\"dart.Object\",\"nullable\":true}}}",
        operations: operations,
        context: context);
const nativePlannerStaticBinding = "_h27c6590844";
r.NativeCallAdapter nativePlannerStaticAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "callback.static"
            },
            "implementation":
                "27c65908442015174857b78cb09e34c169bc73c720d7dc4a60e06ffd3b80edec"
          }
        }), (_restageInputs, _restageCells) {
      final int Function() _restageResult = () {
        final tearoff = NativePlannerStatics.answer;
        return NativePlannerStatics.constant +
            NativePlannerStatics.field +
            NativePlannerStatics.getter +
            NativePlannerStatics.answer() +
            tearoff();
      };
      return r.NativeBinding<int Function()>(
          contract:
              s.NativeBindingContract(type: "callback.static", nullable: false),
          value: _restageResult);
    });
s.ValueProgram nativePlannerStaticProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"callback.static\"},\"value\":{\"binding\":\"_h27c6590844\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"native\",\"nativeType\":\"callback.static\"},\"implementation\":\"27c65908442015174857b78cb09e34c169bc73c720d7dc4a60e06ffd3b80edec\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const nativePlannerInterpolationBinding = "_h6c80981d39";
r.NativeCallAdapter nativePlannerInterpolationAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{
              "_restageCapture0": <String, Object?>{"kind": "int"}
            },
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "callback.interpolation"
            },
            "implementation":
                "6c80981d39d05cfe7f1f6c4ef814b606f04ebabfe160f8b97b55bc86c0f06c36"
          }
        }), (_restageInputs, _restageCells) {
      final _restageCapture0 = _restageCells["_restageCapture0"]!.cast<int>();
      final String Function() _restageResult =
          () => 'count:${_restageCapture0.value}:${_restageCapture0.value++}';
      return r.NativeBinding<String Function()>(
          contract: s.NativeBindingContract(
              type: "callback.interpolation", nullable: false),
          value: _restageResult);
    });
s.ValueProgram nativePlannerInterpolationProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"callback.interpolation\"},\"value\":{\"binding\":\"_h6c80981d39\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{\"_restageCapture0\":{\"kind\":\"int\"}},\"result\":{\"kind\":\"native\",\"nativeType\":\"callback.interpolation\"},\"implementation\":\"6c80981d39d05cfe7f1f6c4ef814b606f04ebabfe160f8b97b55bc86c0f06c36\"}},\"captures\":{\"_restageCapture0\":\"counter\"}}}],\"root\":0,\"captures\":{},\"parameters\":{},\"outerLocals\":{\"counter\":{\"kind\":\"int\"}}}",
        operations: operations,
        context: context);
const nativePlannerSelectColorBinding = "_h160ecdb70c";
r.NativeCallAdapter nativePlannerSelectColorAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{"kind": "bool"},
              <String, Object?>{"kind": "native", "nativeType": "flutter.Color"}
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "flutter.Color"
            },
            "implementation":
                "160ecdb70c764854ac5ec3c440128162534a419ea210a9365f7d7ea1165163f2"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final bool _restageInput0 = _restageAs<bool>(_restageInputs[0]);
      final f.MaterialColor _restageInput1 = _restageAs<f.MaterialColor>(
          (_restageInputs[1] as s.ValueNative).value);
      final f.MaterialColor _restageResult =
          _restageInput0 ? _restageInput1 : f.Colors.red;
      return r.NativeBinding<f.MaterialColor>(
          contract:
              s.NativeBindingContract(type: "flutter.Color", nullable: false),
          value: _restageResult);
    });
s.ValueProgram nativePlannerSelectColorProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"bool\"},\"name\":\"flag\"},{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\"},\"name\":\"color\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\"},\"inputs\":[0,1],\"value\":{\"binding\":\"_h160ecdb70c\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"bool\"},{\"kind\":\"native\",\"nativeType\":\"flutter.Color\"}],\"captures\":{},\"result\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\"},\"implementation\":\"160ecdb70c764854ac5ec3c440128162534a419ea210a9365f7d7ea1165163f2\"}},\"captures\":{}}}],\"root\":2,\"captures\":{},\"parameters\":{\"flag\":{\"kind\":\"bool\"},\"color\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\"}}}",
        operations: operations,
        context: context);
const nativePlannerCoalesceColorBinding = "_he2dbbe815c";
r.NativeCallAdapter nativePlannerCoalesceColorAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{
                "kind": "native",
                "nativeType": "flutter.Color",
                "nullable": true
              }
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "flutter.Color"
            },
            "implementation":
                "e2dbbe815c5200c7fe685dd8e5fbbe7ec39f3e2e1195a0a2b384e107d4404e70"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final f.Color? _restageInput0 = _restageAs<f.Color?>(
          (_restageInputs[0] == null
              ? null
              : (_restageInputs[0] as s.ValueNative).value));
      final f.Color _restageResult = _restageInput0 ?? f.Colors.red;
      return r.NativeBinding<f.Color>(
          contract:
              s.NativeBindingContract(type: "flutter.Color", nullable: false),
          value: _restageResult);
    });
s.ValueProgram nativePlannerCoalesceColorProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\",\"nullable\":true},\"name\":\"optional\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\"},\"inputs\":[0],\"value\":{\"binding\":\"_he2dbbe815c\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"native\",\"nativeType\":\"flutter.Color\",\"nullable\":true}],\"captures\":{},\"result\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\"},\"implementation\":\"e2dbbe815c5200c7fe685dd8e5fbbe7ec39f3e2e1195a0a2b384e107d4404e70\"}},\"captures\":{}}}],\"root\":1,\"captures\":{},\"parameters\":{\"optional\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\",\"nullable\":true}}}",
        operations: operations,
        context: context);
const nativePlannerSelectKeyBinding = "_hc847829082";
r.NativeCallAdapter nativePlannerSelectKeyAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{"kind": "bool"},
              <String, Object?>{"kind": "native", "nativeType": "flutter.Key"}
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "flutter.Key"
            },
            "implementation":
                "c8478290820dab791bd0eea2c1ca2708df7bef25f4d332b1b481d596d33c2bd6"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final bool _restageInput0 = _restageAs<bool>(_restageInputs[0]);
      final f.Key _restageInput1 =
          _restageAs<f.Key>((_restageInputs[1] as s.ValueNative).value);
      final f.Key _restageResult = _restageInput0
          ? _restageInput1
          : const f.ValueKey<String>('fallback');
      return r.NativeBinding<f.Key>(
          contract:
              s.NativeBindingContract(type: "flutter.Key", nullable: false),
          value: _restageResult);
    });
s.ValueProgram nativePlannerSelectKeyProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"bool\"},\"name\":\"flag\"},{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"flutter.Key\"},\"name\":\"key\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"flutter.Key\"},\"inputs\":[0,1],\"value\":{\"binding\":\"_hc847829082\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"bool\"},{\"kind\":\"native\",\"nativeType\":\"flutter.Key\"}],\"captures\":{},\"result\":{\"kind\":\"native\",\"nativeType\":\"flutter.Key\"},\"implementation\":\"c8478290820dab791bd0eea2c1ca2708df7bef25f4d332b1b481d596d33c2bd6\"}},\"captures\":{}}}],\"root\":2,\"captures\":{},\"parameters\":{\"flag\":{\"kind\":\"bool\"},\"key\":{\"kind\":\"native\",\"nativeType\":\"flutter.Key\"}}}",
        operations: operations,
        context: context);
const nativePlannerSelectCallbackBinding = "_h10a3790ee5";
r.NativeCallAdapter nativePlannerSelectCallbackAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{"kind": "bool"},
              <String, Object?>{
                "kind": "native",
                "nativeType": "callback.selected"
              },
              <String, Object?>{
                "kind": "native",
                "nativeType": "callback.selected"
              }
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "callback.selected"
            },
            "implementation":
                "10a3790ee5d4011f51baff58a0daa9e6d601a4bbea9e17ae54c827f865ebd7a9"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final bool _restageInput0 = _restageAs<bool>(_restageInputs[0]);
      final void Function() _restageInput1 = _restageAs<void Function()>(
          (_restageInputs[1] as s.ValueNative).value);
      final void Function() _restageInput2 = _restageAs<void Function()>(
          (_restageInputs[2] as s.ValueNative).value);
      final void Function() _restageResult =
          _restageInput0 ? _restageInput1 : _restageInput2;
      return r.NativeBinding<void Function()>(
          contract: s.NativeBindingContract(
              type: "callback.selected", nullable: false),
          value: _restageResult);
    });
s.ValueProgram nativePlannerSelectCallbackProgram(
        Map<String, s.ValueOperation> operations,
        {s.ValueOperationContext? context}) =>
    s.ValueProgram.decode(
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"bool\"},\"name\":\"flag\"},{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"callback.selected\"},\"name\":\"first\"},{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"callback.selected\"},\"name\":\"second\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"callback.selected\"},\"inputs\":[0,1,2],\"value\":{\"binding\":\"_h10a3790ee5\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"bool\"},{\"kind\":\"native\",\"nativeType\":\"callback.selected\"},{\"kind\":\"native\",\"nativeType\":\"callback.selected\"}],\"captures\":{},\"result\":{\"kind\":\"native\",\"nativeType\":\"callback.selected\"},\"implementation\":\"10a3790ee5d4011f51baff58a0daa9e6d601a4bbea9e17ae54c827f865ebd7a9\"}},\"captures\":{}}}],\"root\":3,\"captures\":{},\"parameters\":{\"flag\":{\"kind\":\"bool\"},\"first\":{\"kind\":\"native\",\"nativeType\":\"callback.selected\"},\"second\":{\"kind\":\"native\",\"nativeType\":\"callback.selected\"}}}",
        operations: operations,
        context: context);
f.MaterialColor nativePlannerConstant() =>
    const f.MaterialColor(0xff102030, {500: f.Color(0xff102030)});
