part of 'native_event_source.dart';

const nativeEventDsl =
    "Column(children: [FilledButton(onPressed: {nativeEvent: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/material/tab_controller.dart#TabController\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"()->void\\\"},\\\"inputs\\\":[0],\\\"value\\\":{\\\"binding\\\":\\\"_h206eda4f7f\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/material/tab_controller.dart#TabController\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"()->void\\\"},\\\"implementation\\\":\\\"206eda4f7f0e1008d7834705a7d6076f97e32fbaf06ae5f936e3b39564137d3f\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":1,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/material/tab_controller.dart#TabController\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._hb443e4d8b2 } }}, child: Text(text: \"Tab\")), GestureDetector(onTap: {nativeEvent: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/scroll_controller.dart#ScrollController\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"()->void\\\"},\\\"inputs\\\":[0],\\\"value\\\":{\\\"binding\\\":\\\"_hdeee177d54\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/scroll_controller.dart#ScrollController\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"()->void\\\"},\\\"implementation\\\":\\\"deee177d548a0fdc72e9d2f2263e68977a93d36d40faa6bc32d1faddf1f61dbd\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":1,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/scroll_controller.dart#ScrollController\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._heef329e319 } }}, child: Text(text: \"Scroll\")), FilledButton(onPressed: {nativeEvent: data.context._hf5940c9da1}, child: Text(text: \"Borrowed\"))])";
Map<String, Object?> nativeEventData() => {
      "_hb443e4d8b2": {
        "kind": "nativeBinding",
        "key": "_hb443e4d8b2",
        "type":
            "package:flutter/src/material/tab_controller.dart#TabController",
        "nullable": false
      },
      "_heef329e319": {
        "kind": "nativeBinding",
        "key": "_heef329e319",
        "type":
            "package:flutter/src/widgets/scroll_controller.dart#ScrollController",
        "nullable": false
      },
      "_hf5940c9da1": {
        "kind": "nativeBinding",
        "key": "_hf5940c9da1",
        "type": "()->void",
        "nullable": true
      },
    };
r.NativeCallAdapter _nativeEvent_h206eda4f7fNative() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{
                "kind": "native",
                "nativeType":
                    "package:flutter/src/material/tab_controller.dart#TabController"
              }
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "()->void"
            },
            "implementation":
                "206eda4f7f0e1008d7834705a7d6076f97e32fbaf06ae5f936e3b39564137d3f"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final f.TabController _restageInput0 = _restageAs<f.TabController>(
          (_restageInputs[0] as s.ValueNative).value);
      final void Function() _restageResult = () => _restageInput0.animateTo(1);
      return r.NativeBinding<void Function()>(
          contract: s.NativeBindingContract(type: "()->void", nullable: false),
          value: _restageResult);
    });
r.NativeCallAdapter _nativeEvent_hdeee177d54Native() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{
                "kind": "native",
                "nativeType":
                    "package:flutter/src/widgets/scroll_controller.dart#ScrollController"
              }
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "()->void"
            },
            "implementation":
                "deee177d548a0fdc72e9d2f2263e68977a93d36d40faa6bc32d1faddf1f61dbd"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final f.ScrollController _restageInput0 = _restageAs<f.ScrollController>(
          (_restageInputs[0] as s.ValueNative).value);
      final void Function() _restageResult = () => _restageInput0.jumpTo(80);
      return r.NativeBinding<void Function()>(
          contract: s.NativeBindingContract(type: "()->void", nullable: false),
          value: _restageResult);
    });
Map<String, r.NativeBinding<Object?>> nativeEventBindings(
        {required f.TabController tabs,
        required f.ScrollController scroll,
        required f.VoidCallback? borrowed}) =>
    {
      "_h206eda4f7f": r.NativeBinding(
          contract: s.NativeBindingContract.fromJson(<String, Object?>{
            "type": "installed.call",
            "nullable": false,
            "call": <String, Object?>{
              "inputs": <Object?>[
                <String, Object?>{
                  "kind": "native",
                  "nativeType":
                      "package:flutter/src/material/tab_controller.dart#TabController"
                }
              ],
              "captures": <String, Object?>{},
              "result": <String, Object?>{
                "kind": "native",
                "nativeType": "()->void"
              },
              "implementation":
                  "206eda4f7f0e1008d7834705a7d6076f97e32fbaf06ae5f936e3b39564137d3f"
            }
          }),
          value: _nativeEvent_h206eda4f7fNative()),
      "_hb443e4d8b2": r.NativeBinding(
          contract: s.NativeBindingContract(
              type:
                  'package:flutter/src/material/tab_controller.dart#TabController',
              nullable: false),
          value: tabs),
      "_hdeee177d54": r.NativeBinding(
          contract: s.NativeBindingContract.fromJson(<String, Object?>{
            "type": "installed.call",
            "nullable": false,
            "call": <String, Object?>{
              "inputs": <Object?>[
                <String, Object?>{
                  "kind": "native",
                  "nativeType":
                      "package:flutter/src/widgets/scroll_controller.dart#ScrollController"
                }
              ],
              "captures": <String, Object?>{},
              "result": <String, Object?>{
                "kind": "native",
                "nativeType": "()->void"
              },
              "implementation":
                  "deee177d548a0fdc72e9d2f2263e68977a93d36d40faa6bc32d1faddf1f61dbd"
            }
          }),
          value: _nativeEvent_hdeee177d54Native()),
      "_heef329e319": r.NativeBinding(
          contract: s.NativeBindingContract(
              type:
                  'package:flutter/src/widgets/scroll_controller.dart#ScrollController',
              nullable: false),
          value: scroll),
      "_hf5940c9da1": r.NativeBinding(
          contract: s.NativeBindingContract(type: '()->void', nullable: true),
          value: borrowed),
    };
const nativeLexicalDsl =
    "LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"literal\\\",\\\"type\\\":{\\\"kind\\\":\\\"int\\\"},\\\"value\\\":0},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"int\\\"},\\\"inputs\\\":[1],\\\"name\\\":\\\"local2\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"(dart:core#int)->void\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"()->void\\\"},\\\"inputs\\\":[3],\\\"value\\\":{\\\"binding\\\":\\\"_h71d7344085\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"(dart:core#int)->void\\\"}],\\\"captures\\\":{\\\"_restageCapture0\\\":{\\\"kind\\\":\\\"int\\\"}},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"()->void\\\"},\\\"implementation\\\":\\\"71d7344085f5a3e6500eafaf4e950ef1a9352fc0782551239db075b0bf6c2221\\\"}},\\\"captures\\\":{\\\"_restageCapture0\\\":\\\"local2\\\"}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"()->void\\\"},\\\"inputs\\\":[4],\\\"name\\\":\\\"n5\\\"},{\\\"op\\\":\\\"literal\\\",\\\"type\\\":{\\\"kind\\\":\\\"String\\\"},\\\"value\\\":\\\"Count\\\"}],\\\"root\\\":0,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"(dart:core#int)->void\\\"}},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}}},\\\"locals\\\":{\\\"local2\\\":{\\\"kind\\\":\\\"int\\\"},\\\"n5\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"()->void\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":2,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":5,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":6,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{\\\"v0\\\":6}}}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {c0: data.context._h2dec8b66f2}, bodies: [(builder0) => FilledButton(onPressed: {nativeEvent: {kind: \"nativeLocal\", slot: \"n5\", type: \"()->void\", nullable: false}}, child: Text(text: builder0.values.v0))]))";
Map<String, Object?> nativeLexicalData() => {
      "_h2dec8b66f2": {
        "kind": "nativeBinding",
        "key": "_h2dec8b66f2",
        "type": "(dart:core#int)->void",
        "nullable": false
      },
    };
r.NativeCallAdapter _nativeLexical_h71d7344085Native() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{
                "kind": "native",
                "nativeType": "(dart:core#int)->void"
              }
            ],
            "captures": <String, Object?>{
              "_restageCapture0": <String, Object?>{"kind": "int"}
            },
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "()->void"
            },
            "implementation":
                "71d7344085f5a3e6500eafaf4e950ef1a9352fc0782551239db075b0bf6c2221"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final f.ValueChanged<int> _restageInput0 =
          _restageAs<f.ValueChanged<int>>(
              (_restageInputs[0] as s.ValueNative).value);
      final _restageCapture0 = _restageCells["_restageCapture0"]!.cast<int>();
      final void Function() _restageResult =
          () => _restageInput0(_restageCapture0.value++);
      return r.NativeBinding<void Function()>(
          contract: s.NativeBindingContract(type: "()->void", nullable: false),
          value: _restageResult);
    });
Map<String, r.NativeBinding<Object?>> nativeLexicalBindings(
        {required f.ValueChanged<int> observer}) =>
    {
      "_h2dec8b66f2": r.NativeBinding(
          contract: s.NativeBindingContract(
              type: '(dart:core#int)->void', nullable: false),
          value: observer),
      "_h71d7344085": r.NativeBinding(
          contract: s.NativeBindingContract.fromJson(<String, Object?>{
            "type": "installed.call",
            "nullable": false,
            "call": <String, Object?>{
              "inputs": <Object?>[
                <String, Object?>{
                  "kind": "native",
                  "nativeType": "(dart:core#int)->void"
                }
              ],
              "captures": <String, Object?>{
                "_restageCapture0": <String, Object?>{"kind": "int"}
              },
              "result": <String, Object?>{
                "kind": "native",
                "nativeType": "()->void"
              },
              "implementation":
                  "71d7344085f5a3e6500eafaf4e950ef1a9352fc0782551239db075b0bf6c2221"
            }
          }),
          value: _nativeLexical_h71d7344085Native()),
    };
