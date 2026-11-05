part of 'native_planner_source.dart';

const nativePlannerClosureBinding = "_h45a0e22657";
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
                "45a0e22657448ed9cbc5ccb352144fe21f721a328a435b556c8144540172a81f"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"callback.seen\"},\"name\":\"seen\"},{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"dart.List<Object>\"},\"name\":\"items\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"callback\"},\"inputs\":[0,1],\"value\":{\"binding\":\"_h45a0e22657\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"native\",\"nativeType\":\"callback.seen\"},{\"kind\":\"native\",\"nativeType\":\"dart.List<Object>\"}],\"captures\":{\"_restageCapture0\":{\"kind\":\"int\"}},\"result\":{\"kind\":\"native\",\"nativeType\":\"callback\"},\"implementation\":\"45a0e22657448ed9cbc5ccb352144fe21f721a328a435b556c8144540172a81f\"}},\"captures\":{\"_restageCapture0\":\"counter\"}}}],\"root\":2,\"captures\":{},\"parameters\":{\"seen\":{\"kind\":\"native\",\"nativeType\":\"callback.seen\"},\"items\":{\"kind\":\"native\",\"nativeType\":\"dart.List<Object>\"}},\"outerLocals\":{\"counter\":{\"kind\":\"int\"}}}",
        operations: operations,
        context: context);
const nativePlannerKeyBinding = "_ha40d8fb8ce";
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
                "a40d8fb8ce1107bbd01589a0c60cbfd8ba8af36c41158da2b780fad5b1246b83"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"dart.List<Object>\"},\"name\":\"items\"},{\"op\":\"parameter\",\"type\":{\"kind\":\"int\"},\"name\":\"index\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"flutter.Key\"},\"inputs\":[0,1],\"value\":{\"binding\":\"_ha40d8fb8ce\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"native\",\"nativeType\":\"dart.List<Object>\"},{\"kind\":\"int\"}],\"captures\":{},\"result\":{\"kind\":\"native\",\"nativeType\":\"flutter.Key\"},\"implementation\":\"a40d8fb8ce1107bbd01589a0c60cbfd8ba8af36c41158da2b780fad5b1246b83\"}},\"captures\":{}}}],\"root\":2,\"captures\":{},\"parameters\":{\"items\":{\"kind\":\"native\",\"nativeType\":\"dart.List<Object>\"},\"index\":{\"kind\":\"int\"}}}",
        operations: operations,
        context: context);
const nativePlannerColorBinding = "_h07101b052f";
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
                "07101b052fcb4d400bb481ddc2d2b00340c3b527c1c8bf94bad5ee7c425a1277"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"dart.Map<int,Color>\"},\"name\":\"swatch\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\"},\"inputs\":[0],\"value\":{\"binding\":\"_h07101b052f\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"native\",\"nativeType\":\"dart.Map<int,Color>\"}],\"captures\":{},\"result\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\"},\"implementation\":\"07101b052fcb4d400bb481ddc2d2b00340c3b527c1c8bf94bad5ee7c425a1277\"}},\"captures\":{}}}],\"root\":1,\"captures\":{},\"parameters\":{\"swatch\":{\"kind\":\"native\",\"nativeType\":\"dart.Map<int,Color>\"}}}",
        operations: operations,
        context: context);
const nativePlannerReassignBinding = "_h807922dffd";
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
                "807922dffd6779502a70250a59ffcb65456d331a51fb6bc5e0b636d579d3ba90"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"dart.Object\"},\"name\":\"replacement\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"callback.reassign\"},\"inputs\":[0],\"value\":{\"binding\":\"_h807922dffd\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"native\",\"nativeType\":\"dart.Object\"}],\"captures\":{\"_restageCapture0\":{\"kind\":\"native\",\"nativeType\":\"dart.Object\"}},\"result\":{\"kind\":\"native\",\"nativeType\":\"callback.reassign\"},\"implementation\":\"807922dffd6779502a70250a59ffcb65456d331a51fb6bc5e0b636d579d3ba90\"}},\"captures\":{\"_restageCapture0\":\"object\"}}}],\"root\":1,\"captures\":{},\"parameters\":{\"replacement\":{\"kind\":\"native\",\"nativeType\":\"dart.Object\"}},\"outerLocals\":{\"object\":{\"kind\":\"native\",\"nativeType\":\"dart.Object\"}}}",
        operations: operations,
        context: context);
const nativePlannerNullableBinding = "_h6fdf4a753b";
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
                "6fdf4a753b09cc148d004a90dc4923a4379491162f4f90b95eb5634fb1c50bf9"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"dart.Object\",\"nullable\":true},\"name\":\"model\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"flutter.Key\",\"nullable\":true},\"inputs\":[0],\"value\":{\"binding\":\"_h6fdf4a753b\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"native\",\"nativeType\":\"dart.Object\",\"nullable\":true}],\"captures\":{},\"result\":{\"kind\":\"native\",\"nativeType\":\"flutter.Key\",\"nullable\":true},\"implementation\":\"6fdf4a753b09cc148d004a90dc4923a4379491162f4f90b95eb5634fb1c50bf9\"}},\"captures\":{}}}],\"root\":1,\"captures\":{},\"parameters\":{\"model\":{\"kind\":\"native\",\"nativeType\":\"dart.Object\",\"nullable\":true}}}",
        operations: operations,
        context: context);
const nativePlannerStaticBinding = "_hce4e3b04ec";
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
                "ce4e3b04ec953e57fec8d6752e7f76d2d1201d588d85e4bfcd1a3a7f22217399"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"callback.static\"},\"value\":{\"binding\":\"_hce4e3b04ec\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{},\"result\":{\"kind\":\"native\",\"nativeType\":\"callback.static\"},\"implementation\":\"ce4e3b04ec953e57fec8d6752e7f76d2d1201d588d85e4bfcd1a3a7f22217399\"}},\"captures\":{}}}],\"root\":0,\"captures\":{},\"parameters\":{}}",
        operations: operations,
        context: context);
const nativePlannerInterpolationBinding = "_h9ba9b04f82";
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
                "9ba9b04f828b4df7f4647b97f249448b50e40c7aeaa03656c7667d1fe8cc74d9"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"callback.interpolation\"},\"value\":{\"binding\":\"_h9ba9b04f82\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[],\"captures\":{\"_restageCapture0\":{\"kind\":\"int\"}},\"result\":{\"kind\":\"native\",\"nativeType\":\"callback.interpolation\"},\"implementation\":\"9ba9b04f828b4df7f4647b97f249448b50e40c7aeaa03656c7667d1fe8cc74d9\"}},\"captures\":{\"_restageCapture0\":\"counter\"}}}],\"root\":0,\"captures\":{},\"parameters\":{},\"outerLocals\":{\"counter\":{\"kind\":\"int\"}}}",
        operations: operations,
        context: context);
const nativePlannerSelectColorBinding = "_ha16476779d";
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
                "a16476779d7029adbc240c63dbf99fce8196af69de613beaa8055b2f6ba3bee0"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"bool\"},\"name\":\"flag\"},{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\"},\"name\":\"color\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\"},\"inputs\":[0,1],\"value\":{\"binding\":\"_ha16476779d\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"bool\"},{\"kind\":\"native\",\"nativeType\":\"flutter.Color\"}],\"captures\":{},\"result\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\"},\"implementation\":\"a16476779d7029adbc240c63dbf99fce8196af69de613beaa8055b2f6ba3bee0\"}},\"captures\":{}}}],\"root\":2,\"captures\":{},\"parameters\":{\"flag\":{\"kind\":\"bool\"},\"color\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\"}}}",
        operations: operations,
        context: context);
const nativePlannerCoalesceColorBinding = "_hfb0a89e676";
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
                "fb0a89e676d2e3069882f2aef57f09ddaea2d538bdbf9bdbe9abd6beff527b3e"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\",\"nullable\":true},\"name\":\"optional\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\"},\"inputs\":[0],\"value\":{\"binding\":\"_hfb0a89e676\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"native\",\"nativeType\":\"flutter.Color\",\"nullable\":true}],\"captures\":{},\"result\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\"},\"implementation\":\"fb0a89e676d2e3069882f2aef57f09ddaea2d538bdbf9bdbe9abd6beff527b3e\"}},\"captures\":{}}}],\"root\":1,\"captures\":{},\"parameters\":{\"optional\":{\"kind\":\"native\",\"nativeType\":\"flutter.Color\",\"nullable\":true}}}",
        operations: operations,
        context: context);
const nativePlannerSelectKeyBinding = "_h6acbe2342c";
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
                "6acbe2342c42ed88ed1ddea8166bb70880e6fe7b61819a07813d4b23cac48810"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"bool\"},\"name\":\"flag\"},{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"flutter.Key\"},\"name\":\"key\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"flutter.Key\"},\"inputs\":[0,1],\"value\":{\"binding\":\"_h6acbe2342c\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"bool\"},{\"kind\":\"native\",\"nativeType\":\"flutter.Key\"}],\"captures\":{},\"result\":{\"kind\":\"native\",\"nativeType\":\"flutter.Key\"},\"implementation\":\"6acbe2342c42ed88ed1ddea8166bb70880e6fe7b61819a07813d4b23cac48810\"}},\"captures\":{}}}],\"root\":2,\"captures\":{},\"parameters\":{\"flag\":{\"kind\":\"bool\"},\"key\":{\"kind\":\"native\",\"nativeType\":\"flutter.Key\"}}}",
        operations: operations,
        context: context);
const nativePlannerSelectCallbackBinding = "_h6fa713c6f3";
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
                "6fa713c6f3351cb81a11e3d573a91b706de80c1481ad57d63c407b35be68f4d0"
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
        "{\"version\":1,\"nodes\":[{\"op\":\"parameter\",\"type\":{\"kind\":\"bool\"},\"name\":\"flag\"},{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"callback.selected\"},\"name\":\"first\"},{\"op\":\"parameter\",\"type\":{\"kind\":\"native\",\"nativeType\":\"callback.selected\"},\"name\":\"second\"},{\"op\":\"native.call\",\"type\":{\"kind\":\"native\",\"nativeType\":\"callback.selected\"},\"inputs\":[0,1,2],\"value\":{\"binding\":\"_h6fa713c6f3\",\"contract\":{\"type\":\"installed.call\",\"nullable\":false,\"call\":{\"inputs\":[{\"kind\":\"bool\"},{\"kind\":\"native\",\"nativeType\":\"callback.selected\"},{\"kind\":\"native\",\"nativeType\":\"callback.selected\"}],\"captures\":{},\"result\":{\"kind\":\"native\",\"nativeType\":\"callback.selected\"},\"implementation\":\"6fa713c6f3351cb81a11e3d573a91b706de80c1481ad57d63c407b35be68f4d0\"}},\"captures\":{}}}],\"root\":3,\"captures\":{},\"parameters\":{\"flag\":{\"kind\":\"bool\"},\"first\":{\"kind\":\"native\",\"nativeType\":\"callback.selected\"},\"second\":{\"kind\":\"native\",\"nativeType\":\"callback.selected\"}}}",
        operations: operations,
        context: context);
f.MaterialColor nativePlannerConstant() =>
    const f.MaterialColor(0xff102030, {500: f.Color(0xff102030)});
