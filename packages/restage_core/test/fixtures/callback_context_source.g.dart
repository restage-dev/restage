part of 'callback_context_source.dart';

const contextDirectDsl =
    "import restage.core; widget Root = LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"name\\\":\\\"arg0\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[1],\\\"value\\\":{\\\"binding\\\":\\\"_h01ee78ea96\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"implementation\\\":\\\"01ee78ea9628339d11e8d8321489b8dc74049766b578f5e40f8008b2ebe0862b\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[2],\\\"name\\\":\\\"n3\\\"}],\\\"root\\\":0,\\\"captures\\\":{},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"arg0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}},\\\"locals\\\":{\\\"n3\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":3,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {}, bodies: [(b0) => ContextProbe(name: 'direct', callback: {kind: \"nativeLocal\", slot: \"n3\", type: \"context.callback\", nullable: false})]));";
r.NativeCallAdapter _contextDirect_h01ee78ea96Native() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{
                "kind": "native",
                "nativeType":
                    "package:flutter/src/widgets/framework.dart#BuildContext"
              }
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "context.callback"
            },
            "implementation":
                "01ee78ea9628339d11e8d8321489b8dc74049766b578f5e40f8008b2ebe0862b"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final f.BuildContext _restageInput0 = _restageAs<f.BuildContext>(
          (_restageInputs[0] as s.ValueNative).value);
      final f.BuildContext Function() _restageResult = () => _restageInput0;
      return r.NativeBinding<f.BuildContext Function()>(
          contract: s.NativeBindingContract(
              type: "context.callback", nullable: false),
          value: _restageResult);
    });
Map<String, r.NativeBinding<Object?>> contextDirectBindings() => {
      "_h01ee78ea96": r.NativeBinding<Object?>(
          contract: s.NativeBindingContract.fromJson(<String, Object?>{
            "type": "installed.call",
            "nullable": false,
            "call": <String, Object?>{
              "inputs": <Object?>[
                <String, Object?>{
                  "kind": "native",
                  "nativeType":
                      "package:flutter/src/widgets/framework.dart#BuildContext"
                }
              ],
              "captures": <String, Object?>{},
              "result": <String, Object?>{
                "kind": "native",
                "nativeType": "context.callback"
              },
              "implementation":
                  "01ee78ea9628339d11e8d8321489b8dc74049766b578f5e40f8008b2ebe0862b"
            }
          }),
          value: _contextDirect_h01ee78ea96Native()),
    };
const contextAliasDsl =
    "import restage.core; widget Root = Builder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"name\\\":\\\"arg0\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[0],\\\"value\\\":{\\\"binding\\\":\\\"_h91b83b6d60\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"implementation\\\":\\\"91b83b6d6097497a76542d700fd1920a66bb79d90a5346bb15f4ba9b78318dc7\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[1],\\\"name\\\":\\\"n2\\\"}],\\\"root\\\":0,\\\"captures\\\":{},\\\"parameters\\\":{\\\"arg0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}},\\\"locals\\\":{\\\"n2\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":2,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {}, bodies: [(b0) => ContextProbe(name: 'alias', callback: {kind: \"nativeLocal\", slot: \"n2\", type: \"context.callback\", nullable: false})]));";
r.NativeCallAdapter _contextAlias_h91b83b6d60Native() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{
                "kind": "native",
                "nativeType":
                    "package:flutter/src/widgets/framework.dart#BuildContext"
              }
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "context.callback"
            },
            "implementation":
                "91b83b6d6097497a76542d700fd1920a66bb79d90a5346bb15f4ba9b78318dc7"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final f.BuildContext _restageInput0 = _restageAs<f.BuildContext>(
          (_restageInputs[0] as s.ValueNative).value);
      final f.BuildContext Function() _restageResult = () => _restageInput0;
      return r.NativeBinding<f.BuildContext Function()>(
          contract: s.NativeBindingContract(
              type: "context.callback", nullable: false),
          value: _restageResult);
    });
Map<String, r.NativeBinding<Object?>> contextAliasBindings() => {
      "_h91b83b6d60": r.NativeBinding<Object?>(
          contract: s.NativeBindingContract.fromJson(<String, Object?>{
            "type": "installed.call",
            "nullable": false,
            "call": <String, Object?>{
              "inputs": <Object?>[
                <String, Object?>{
                  "kind": "native",
                  "nativeType":
                      "package:flutter/src/widgets/framework.dart#BuildContext"
                }
              ],
              "captures": <String, Object?>{},
              "result": <String, Object?>{
                "kind": "native",
                "nativeType": "context.callback"
              },
              "implementation":
                  "91b83b6d6097497a76542d700fd1920a66bb79d90a5346bb15f4ba9b78318dc7"
            }
          }),
          value: _contextAlias_h91b83b6d60Native()),
    };
const contextHelperDsl =
    "import restage.core; widget Root = LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"name\\\":\\\"arg0\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[1],\\\"value\\\":{\\\"binding\\\":\\\"_he010303550\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"implementation\\\":\\\"e01030355022b845f70043aa2d7f58beb1ef2b6b6f32d12e5f657d199121e252\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[2],\\\"name\\\":\\\"n3\\\"}],\\\"root\\\":0,\\\"captures\\\":{},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"arg0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}},\\\"locals\\\":{\\\"n3\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":3,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {}, bodies: [(b0) => ContextProbe(name: 'helper', callback: {kind: \"nativeLocal\", slot: \"n3\", type: \"context.callback\", nullable: false})]));";
r.NativeCallAdapter _contextHelper_he010303550Native() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{
                "kind": "native",
                "nativeType":
                    "package:flutter/src/widgets/framework.dart#BuildContext"
              }
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "context.callback"
            },
            "implementation":
                "e01030355022b845f70043aa2d7f58beb1ef2b6b6f32d12e5f657d199121e252"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final f.BuildContext _restageInput0 = _restageAs<f.BuildContext>(
          (_restageInputs[0] as s.ValueNative).value);
      final f.BuildContext Function() _restageResult = () => _restageInput0;
      return r.NativeBinding<f.BuildContext Function()>(
          contract: s.NativeBindingContract(
              type: "context.callback", nullable: false),
          value: _restageResult);
    });
Map<String, r.NativeBinding<Object?>> contextHelperBindings() => {
      "_he010303550": r.NativeBinding<Object?>(
          contract: s.NativeBindingContract.fromJson(<String, Object?>{
            "type": "installed.call",
            "nullable": false,
            "call": <String, Object?>{
              "inputs": <Object?>[
                <String, Object?>{
                  "kind": "native",
                  "nativeType":
                      "package:flutter/src/widgets/framework.dart#BuildContext"
                }
              ],
              "captures": <String, Object?>{},
              "result": <String, Object?>{
                "kind": "native",
                "nativeType": "context.callback"
              },
              "implementation":
                  "e01030355022b845f70043aa2d7f58beb1ef2b6b6f32d12e5f657d199121e252"
            }
          }),
          value: _contextHelper_he010303550Native()),
    };
const contextNestedDsl =
    "import restage.core; widget Root = LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"name\\\":\\\"arg0\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[1],\\\"value\\\":{\\\"binding\\\":\\\"_h91b83b6d60\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"implementation\\\":\\\"91b83b6d6097497a76542d700fd1920a66bb79d90a5346bb15f4ba9b78318dc7\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[2],\\\"name\\\":\\\"n3\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"inputs\\\":[1],\\\"name\\\":\\\"n4\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"inputs\\\":[1],\\\"name\\\":\\\"n5\\\"}],\\\"root\\\":0,\\\"captures\\\":{},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"arg0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}},\\\"locals\\\":{\\\"n3\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"n4\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"n5\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":3,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":4,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":5,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {}, bodies: [(b0) => ContextProbe(name: 'outer', callback: {kind: \"nativeLocal\", slot: \"n3\", type: \"context.callback\", nullable: false}, child: LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"name\\\":\\\"arg0\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"inputs\\\":[1],\\\"name\\\":\\\"local2\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"value\\\":{\\\"binding\\\":\\\"_h49c5c1ab03\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[],\\\"captures\\\":{\\\"_restageCapture0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"implementation\\\":\\\"49c5c1ab03bb6374284b4a46d95afcdfe9d16d75135b01e221dbb71c82d92e3e\\\"}},\\\"captures\\\":{\\\"_restageCapture0\\\":\\\"local2\\\"}}},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"inputs\\\":[4],\\\"name\\\":\\\"local2\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[1],\\\"value\\\":{\\\"binding\\\":\\\"_h6da92effb5\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"implementation\\\":\\\"6da92effb51d35661b4e30d1c7475511ee773219ad183b76a0f7d55fc342dc80\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[6],\\\"name\\\":\\\"n7\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[8],\\\"value\\\":{\\\"binding\\\":\\\"_h91b83b6d60\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"implementation\\\":\\\"91b83b6d6097497a76542d700fd1920a66bb79d90a5346bb15f4ba9b78318dc7\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[9],\\\"name\\\":\\\"n10\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[3],\\\"name\\\":\\\"n11\\\"}],\\\"root\\\":0,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"arg0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}},\\\"locals\\\":{\\\"local2\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"n7\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"n10\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"n11\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":2,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":3,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":5,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":7,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":10,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":11,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}}}}}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {c0: {kind: \"nativeLocal\", slot: \"n4\", type: \"package:flutter/src/widgets/framework.dart#BuildContext\", nullable: false}, c1: {kind: \"nativeLocal\", slot: \"n5\", type: \"package:flutter/src/widgets/framework.dart#BuildContext\", nullable: false}}, bodies: [(b1) => ContextProbe(name: 'inner', callback: {kind: \"nativeLocal\", slot: \"n7\", type: \"context.callback\", nullable: false}, child: ContextProbe(name: 'retainedOuter', callback: {kind: \"nativeLocal\", slot: \"n10\", type: \"context.callback\", nullable: false}, child: ContextProbe(name: 'mutable', callback: {kind: \"nativeLocal\", slot: \"n11\", type: \"context.callback\", nullable: false})))])))]));";
r.NativeCallAdapter _contextNested_h91b83b6d60Native() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{
                "kind": "native",
                "nativeType":
                    "package:flutter/src/widgets/framework.dart#BuildContext"
              }
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "context.callback"
            },
            "implementation":
                "91b83b6d6097497a76542d700fd1920a66bb79d90a5346bb15f4ba9b78318dc7"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final f.BuildContext _restageInput0 = _restageAs<f.BuildContext>(
          (_restageInputs[0] as s.ValueNative).value);
      final f.BuildContext Function() _restageResult = () => _restageInput0;
      return r.NativeBinding<f.BuildContext Function()>(
          contract: s.NativeBindingContract(
              type: "context.callback", nullable: false),
          value: _restageResult);
    });
r.NativeCallAdapter _contextNested_h49c5c1ab03Native() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{
              "_restageCapture0": <String, Object?>{
                "kind": "native",
                "nativeType":
                    "package:flutter/src/widgets/framework.dart#BuildContext"
              }
            },
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "context.callback"
            },
            "implementation":
                "49c5c1ab03bb6374284b4a46d95afcdfe9d16d75135b01e221dbb71c82d92e3e"
          }
        }), (_restageInputs, _restageCells) {
      final _restageCapture0 =
          _restageCells["_restageCapture0"]!.cast<f.BuildContext>();
      final f.BuildContext Function() _restageResult =
          () => _restageCapture0.value;
      return r.NativeBinding<f.BuildContext Function()>(
          contract: s.NativeBindingContract(
              type: "context.callback", nullable: false),
          value: _restageResult);
    });
r.NativeCallAdapter _contextNested_h6da92effb5Native() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{
                "kind": "native",
                "nativeType":
                    "package:flutter/src/widgets/framework.dart#BuildContext"
              }
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "context.callback"
            },
            "implementation":
                "6da92effb51d35661b4e30d1c7475511ee773219ad183b76a0f7d55fc342dc80"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final f.BuildContext _restageInput0 = _restageAs<f.BuildContext>(
          (_restageInputs[0] as s.ValueNative).value);
      final f.BuildContext Function() _restageResult = () => _restageInput0;
      return r.NativeBinding<f.BuildContext Function()>(
          contract: s.NativeBindingContract(
              type: "context.callback", nullable: false),
          value: _restageResult);
    });
Map<String, r.NativeBinding<Object?>> contextNestedBindings() => {
      "_h91b83b6d60": r.NativeBinding<Object?>(
          contract: s.NativeBindingContract.fromJson(<String, Object?>{
            "type": "installed.call",
            "nullable": false,
            "call": <String, Object?>{
              "inputs": <Object?>[
                <String, Object?>{
                  "kind": "native",
                  "nativeType":
                      "package:flutter/src/widgets/framework.dart#BuildContext"
                }
              ],
              "captures": <String, Object?>{},
              "result": <String, Object?>{
                "kind": "native",
                "nativeType": "context.callback"
              },
              "implementation":
                  "91b83b6d6097497a76542d700fd1920a66bb79d90a5346bb15f4ba9b78318dc7"
            }
          }),
          value: _contextNested_h91b83b6d60Native()),
      "_h49c5c1ab03": r.NativeBinding<Object?>(
          contract: s.NativeBindingContract.fromJson(<String, Object?>{
            "type": "installed.call",
            "nullable": false,
            "call": <String, Object?>{
              "inputs": <Object?>[],
              "captures": <String, Object?>{
                "_restageCapture0": <String, Object?>{
                  "kind": "native",
                  "nativeType":
                      "package:flutter/src/widgets/framework.dart#BuildContext"
                }
              },
              "result": <String, Object?>{
                "kind": "native",
                "nativeType": "context.callback"
              },
              "implementation":
                  "49c5c1ab03bb6374284b4a46d95afcdfe9d16d75135b01e221dbb71c82d92e3e"
            }
          }),
          value: _contextNested_h49c5c1ab03Native()),
      "_h6da92effb5": r.NativeBinding<Object?>(
          contract: s.NativeBindingContract.fromJson(<String, Object?>{
            "type": "installed.call",
            "nullable": false,
            "call": <String, Object?>{
              "inputs": <Object?>[
                <String, Object?>{
                  "kind": "native",
                  "nativeType":
                      "package:flutter/src/widgets/framework.dart#BuildContext"
                }
              ],
              "captures": <String, Object?>{},
              "result": <String, Object?>{
                "kind": "native",
                "nativeType": "context.callback"
              },
              "implementation":
                  "6da92effb51d35661b4e30d1c7475511ee773219ad183b76a0f7d55fc342dc80"
            }
          }),
          value: _contextNested_h6da92effb5Native()),
    };
