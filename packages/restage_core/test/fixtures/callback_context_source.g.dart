part of 'callback_context_source.dart';

const contextDirectDsl =
    "import restage.core; widget Root = LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"name\\\":\\\"arg0\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[1],\\\"value\\\":{\\\"binding\\\":\\\"_ha64c5eed83\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"implementation\\\":\\\"a64c5eed83398f3e3ea9a31e5cdbaa85ee33d6604c1cb560facdb02ade92d3b2\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[2],\\\"name\\\":\\\"n3\\\"}],\\\"root\\\":0,\\\"captures\\\":{},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"arg0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}},\\\"locals\\\":{\\\"n3\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":3,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {}, bodies: [(b0) => ContextProbe(name: 'direct', callback: {kind: \"nativeLocal\", slot: \"n3\", type: \"context.callback\", nullable: false})]));";
r.NativeCallAdapter _contextDirect_ha64c5eed83Native() => r.NativeCallAdapter(
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
                "a64c5eed83398f3e3ea9a31e5cdbaa85ee33d6604c1cb560facdb02ade92d3b2"
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
      "_ha64c5eed83": r.NativeBinding<Object?>(
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
                  "a64c5eed83398f3e3ea9a31e5cdbaa85ee33d6604c1cb560facdb02ade92d3b2"
            }
          }),
          value: _contextDirect_ha64c5eed83Native()),
    };
const contextAliasDsl =
    "import restage.core; widget Root = Builder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"name\\\":\\\"arg0\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[0],\\\"value\\\":{\\\"binding\\\":\\\"_h06aa495eff\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"implementation\\\":\\\"06aa495eff4eb2f0328d75c744d9db8a4ce131399fa1aa350bd7ebecf13d3fbb\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[1],\\\"name\\\":\\\"n2\\\"}],\\\"root\\\":0,\\\"captures\\\":{},\\\"parameters\\\":{\\\"arg0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}},\\\"locals\\\":{\\\"n2\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":2,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {}, bodies: [(b0) => ContextProbe(name: 'alias', callback: {kind: \"nativeLocal\", slot: \"n2\", type: \"context.callback\", nullable: false})]));";
r.NativeCallAdapter _contextAlias_h06aa495effNative() => r.NativeCallAdapter(
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
                "06aa495eff4eb2f0328d75c744d9db8a4ce131399fa1aa350bd7ebecf13d3fbb"
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
      "_h06aa495eff": r.NativeBinding<Object?>(
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
                  "06aa495eff4eb2f0328d75c744d9db8a4ce131399fa1aa350bd7ebecf13d3fbb"
            }
          }),
          value: _contextAlias_h06aa495effNative()),
    };
const contextHelperDsl =
    "import restage.core; widget Root = LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"name\\\":\\\"arg0\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[1],\\\"value\\\":{\\\"binding\\\":\\\"_h2cf38c9d4f\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"implementation\\\":\\\"2cf38c9d4fafd2b50da9a7007d3c0fb7392689d5534998946b6379021999fa05\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[2],\\\"name\\\":\\\"n3\\\"}],\\\"root\\\":0,\\\"captures\\\":{},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"arg0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}},\\\"locals\\\":{\\\"n3\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":3,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {}, bodies: [(b0) => ContextProbe(name: 'helper', callback: {kind: \"nativeLocal\", slot: \"n3\", type: \"context.callback\", nullable: false})]));";
r.NativeCallAdapter _contextHelper_h2cf38c9d4fNative() => r.NativeCallAdapter(
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
                "2cf38c9d4fafd2b50da9a7007d3c0fb7392689d5534998946b6379021999fa05"
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
      "_h2cf38c9d4f": r.NativeBinding<Object?>(
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
                  "2cf38c9d4fafd2b50da9a7007d3c0fb7392689d5534998946b6379021999fa05"
            }
          }),
          value: _contextHelper_h2cf38c9d4fNative()),
    };
const contextNestedDsl =
    "import restage.core; widget Root = LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"name\\\":\\\"arg0\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[1],\\\"value\\\":{\\\"binding\\\":\\\"_h06aa495eff\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"implementation\\\":\\\"06aa495eff4eb2f0328d75c744d9db8a4ce131399fa1aa350bd7ebecf13d3fbb\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[2],\\\"name\\\":\\\"n3\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"inputs\\\":[1],\\\"name\\\":\\\"n4\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"inputs\\\":[1],\\\"name\\\":\\\"n5\\\"}],\\\"root\\\":0,\\\"captures\\\":{},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"arg0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}},\\\"locals\\\":{\\\"n3\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"n4\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"n5\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":3,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":4,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":5,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {}, bodies: [(b0) => ContextProbe(name: 'outer', callback: {kind: \"nativeLocal\", slot: \"n3\", type: \"context.callback\", nullable: false}, child: LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"name\\\":\\\"arg0\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"inputs\\\":[1],\\\"name\\\":\\\"local2\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"value\\\":{\\\"binding\\\":\\\"_heb99e042af\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[],\\\"captures\\\":{\\\"_restageCapture0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"implementation\\\":\\\"eb99e042af59b8a5ad3bd28ff4564d978550042bfc0c7a0c93945a6ec38d41c6\\\"}},\\\"captures\\\":{\\\"_restageCapture0\\\":\\\"local2\\\"}}},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"inputs\\\":[4],\\\"name\\\":\\\"local2\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[1],\\\"value\\\":{\\\"binding\\\":\\\"_h83b69f2f63\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"implementation\\\":\\\"83b69f2f63b2ec1d757cfd80a53270951096c29c129d46d036961c78d296cbf1\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[6],\\\"name\\\":\\\"n7\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[8],\\\"value\\\":{\\\"binding\\\":\\\"_h06aa495eff\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"implementation\\\":\\\"06aa495eff4eb2f0328d75c744d9db8a4ce131399fa1aa350bd7ebecf13d3fbb\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[9],\\\"name\\\":\\\"n10\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"inputs\\\":[3],\\\"name\\\":\\\"n11\\\"}],\\\"root\\\":0,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"arg0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"}},\\\"locals\\\":{\\\"local2\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"package:flutter/src/widgets/framework.dart#BuildContext\\\"},\\\"n7\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"n10\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"},\\\"n11\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"context.callback\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":2,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":3,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":5,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":7,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":10,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":11,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}}}}}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {c0: {kind: \"nativeLocal\", slot: \"n4\", type: \"package:flutter/src/widgets/framework.dart#BuildContext\", nullable: false}, c1: {kind: \"nativeLocal\", slot: \"n5\", type: \"package:flutter/src/widgets/framework.dart#BuildContext\", nullable: false}}, bodies: [(b1) => ContextProbe(name: 'inner', callback: {kind: \"nativeLocal\", slot: \"n7\", type: \"context.callback\", nullable: false}, child: ContextProbe(name: 'retainedOuter', callback: {kind: \"nativeLocal\", slot: \"n10\", type: \"context.callback\", nullable: false}, child: ContextProbe(name: 'mutable', callback: {kind: \"nativeLocal\", slot: \"n11\", type: \"context.callback\", nullable: false})))])))]));";
r.NativeCallAdapter _contextNested_h06aa495effNative() => r.NativeCallAdapter(
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
                "06aa495eff4eb2f0328d75c744d9db8a4ce131399fa1aa350bd7ebecf13d3fbb"
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
r.NativeCallAdapter _contextNested_heb99e042afNative() => r.NativeCallAdapter(
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
                "eb99e042af59b8a5ad3bd28ff4564d978550042bfc0c7a0c93945a6ec38d41c6"
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
r.NativeCallAdapter _contextNested_h83b69f2f63Native() => r.NativeCallAdapter(
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
                "83b69f2f63b2ec1d757cfd80a53270951096c29c129d46d036961c78d296cbf1"
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
      "_h06aa495eff": r.NativeBinding<Object?>(
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
                  "06aa495eff4eb2f0328d75c744d9db8a4ce131399fa1aa350bd7ebecf13d3fbb"
            }
          }),
          value: _contextNested_h06aa495effNative()),
      "_heb99e042af": r.NativeBinding<Object?>(
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
                  "eb99e042af59b8a5ad3bd28ff4564d978550042bfc0c7a0c93945a6ec38d41c6"
            }
          }),
          value: _contextNested_heb99e042afNative()),
      "_h83b69f2f63": r.NativeBinding<Object?>(
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
                  "83b69f2f63b2ec1d757cfd80a53270951096c29c129d46d036961c78d296cbf1"
            }
          }),
          value: _contextNested_h83b69f2f63Native()),
    };
