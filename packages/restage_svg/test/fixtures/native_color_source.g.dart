part of 'native_color_source.dart';

r.NativeCallAdapter nativeColor_h570c003b5b() => r.NativeCallAdapter(
  s.NativeBindingContract.fromJson(<String, Object?>{
    "type": "installed.call",
    "nullable": false,
    "call": <String, Object?>{
      "inputs": <Object?>[
        <String, Object?>{
          "kind": "native",
          "nativeType": "dart:core#Map<dart:core#int,dart:ui#Color>",
        },
      ],
      "captures": <String, Object?>{},
      "result": <String, Object?>{
        "kind": "native",
        "nativeType": "flutter.Color",
      },
      "implementation":
          "570c003b5b7529fe21835fc6d85388387cdb2638da3c556c4bb7ce4902e84df7",
    },
  }),
  (_restageInputs, _restageCells) {
    T _restageAs<T>(Object? value) => value as T;
    final Map<int, Color> _restageInput0 = _restageAs<Map<int, Color>>(
      (_restageInputs[0] as s.ValueNative).value,
    );
    final MaterialColor _restageResult = MaterialColor(
      0xff123456,
      _restageInput0,
    );
    return r.NativeBinding<MaterialColor>(
      contract: s.NativeBindingContract(type: "flutter.Color", nullable: false),
      value: _restageResult,
    );
  },
);
const nativeSvgColorDsl =
    "LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[1],\\\"value\\\":{\\\"binding\\\":\\\"_h570c003b5b\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"570c003b5b7529fe21835fc6d85388387cdb2638da3c556c4bb7ce4902e84df7\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"String\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[2],\\\"name\\\":\\\"n4\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[2],\\\"name\\\":\\\"n5\\\"}],\\\"root\\\":0,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"String\\\"}},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}}},\\\"locals\\\":{\\\"n4\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"n5\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":2,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":3,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":4,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":5,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{\\\"v0\\\":3}}}}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {c0: data.context._hc1912c494f, c1: \"<svg xmlns=\\\"http://www.w3.org/2000/svg\\\" width=\\\"8\\\" height=\\\"8\\\"><path d=\\\"M0 0h8v8H0z\\\" fill=\\\"currentColor\\\"/></svg>\"}, bodies: [(builder0) => SvgPictureString(string: builder0.values.v0, theme: {currentColor: {kind: \"nativeLocal\", slot: \"n4\", type: \"flutter.Color\", nullable: false}}, colorFilter: {kind: \"mode\", color: {kind: \"nativeLocal\", slot: \"n5\", type: \"flutter.Color\", nullable: false}, blendMode: \"srcIn\"})]))";
Map<String, r.NativeBinding<Object?>> nativeSvgColorBindings(
  Map<int, Color> swatch,
) => {
  "_h570c003b5b": r.NativeBinding(
    contract: s.NativeBindingContract.fromJson(<String, Object?>{
      "type": "installed.call",
      "nullable": false,
      "call": <String, Object?>{
        "inputs": <Object?>[
          <String, Object?>{
            "kind": "native",
            "nativeType": "dart:core#Map<dart:core#int,dart:ui#Color>",
          },
        ],
        "captures": <String, Object?>{},
        "result": <String, Object?>{
          "kind": "native",
          "nativeType": "flutter.Color",
        },
        "implementation":
            "570c003b5b7529fe21835fc6d85388387cdb2638da3c556c4bb7ce4902e84df7",
      },
    }),
    value: nativeColor_h570c003b5b(),
  ),
  "_hc1912c494f": r.NativeBinding(
    contract: s.NativeBindingContract(
      type: 'dart:core#Map<dart:core#int,dart:ui#Color>',
      nullable: false,
    ),
    value: swatch,
  ),
};
