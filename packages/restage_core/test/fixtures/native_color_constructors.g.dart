part of 'native_color_constructors.dart';

r.NativeCallAdapter nativeColor_h288429ff9a() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{
                "kind": "native",
                "nativeType": "dart:core#Map<dart:core#int,dart:ui#Color>"
              }
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "flutter.Color"
            },
            "implementation":
                "288429ff9ade00d9e73b96cfd15c12a36e1c70a33b4493fb936001b150a10137"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final Map<int, Color> _restageInput0 = _restageAs<Map<int, Color>>(
          (_restageInputs[0] as s.ValueNative).value);
      final MaterialColor _restageResult =
          MaterialColor(0xff102030, _restageInput0);
      return r.NativeBinding<MaterialColor>(
          contract:
              s.NativeBindingContract(type: "flutter.Color", nullable: false),
          value: _restageResult);
    });
r.NativeCallAdapter nativeColor_h29466f31ab() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{
                "kind": "native",
                "nativeType": "dart:core#Map<dart:core#int,dart:ui#Color>"
              }
            ],
            "captures": <String, Object?>{},
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "flutter.Color"
            },
            "implementation":
                "29466f31ab626ca1f30fa53a9dabf9744ebe04682543c68764cfd811740d88c9"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final Map<int, Color> _restageInput0 = _restageAs<Map<int, Color>>(
          (_restageInputs[0] as s.ValueNative).value);
      final MaterialAccentColor _restageResult =
          MaterialAccentColor(0xff102030, _restageInput0);
      return r.NativeBinding<MaterialAccentColor>(
          contract:
              s.NativeBindingContract(type: "flutter.Color", nullable: false),
          value: _restageResult);
    });
MaterialColor nativeColor_h62d376d3da() =>
    const MaterialColor(0xff102030, {500: Color(0xff102030)});
Color nativeColor_h3a3dba19f0() =>
    const Color.from(alpha: 1, red: .123456789, green: .3, blue: .4);
MaterialColor nativeColor_haccfeceba9() => localPalette;
MaterialColor nativeColor_hf944d0d7c1() => palette.importedColor;
MaterialAccentColor nativeColor_h82d2e17936() => palette.Palette.color;
MaterialAccentColor nativeColor_h3be7ce0b47() =>
    ColorConstructorSource.staticPalette;
Color? nativeColor_h74bbba614c() => absentColor;
const nativeColorDslfresh =
    "LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[1],\\\"value\\\":{\\\"binding\\\":\\\"_h288429ff9a\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"288429ff9ade00d9e73b96cfd15c12a36e1c70a33b4493fb936001b150a10137\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[2],\\\"name\\\":\\\"n3\\\"}],\\\"root\\\":0,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"}},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}}},\\\"locals\\\":{\\\"n3\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":2,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":3,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {c0: data.context._hc1912c494f}, bodies: [(builder0) => ColoredBox(color: {kind: \"nativeLocal\", slot: \"n3\", type: \"flutter.Color\", nullable: false})]))";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsfresh(
        Map<int, Color> swatch) =>
    {
      "_h288429ff9a": r.NativeBinding(
          contract: s.NativeBindingContract.fromJson(<String, Object?>{
            "type": "installed.call",
            "nullable": false,
            "call": <String, Object?>{
              "inputs": <Object?>[
                <String, Object?>{
                  "kind": "native",
                  "nativeType": "dart:core#Map<dart:core#int,dart:ui#Color>"
                }
              ],
              "captures": <String, Object?>{},
              "result": <String, Object?>{
                "kind": "native",
                "nativeType": "flutter.Color"
              },
              "implementation":
                  "288429ff9ade00d9e73b96cfd15c12a36e1c70a33b4493fb936001b150a10137"
            }
          }),
          value: nativeColor_h288429ff9a()),
      "_hc1912c494f": r.NativeBinding(
          contract: s.NativeBindingContract(
              type: 'dart:core#Map<dart:core#int,dart:ui#Color>',
              nullable: false),
          value: swatch),
    };
const nativeColorDslaccent =
    "LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[1],\\\"value\\\":{\\\"binding\\\":\\\"_h29466f31ab\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"29466f31ab626ca1f30fa53a9dabf9744ebe04682543c68764cfd811740d88c9\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[2],\\\"name\\\":\\\"n3\\\"}],\\\"root\\\":0,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"}},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}}},\\\"locals\\\":{\\\"n3\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":2,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":3,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {c0: data.context._hc1912c494f}, bodies: [(builder0) => ColoredBox(color: {kind: \"nativeLocal\", slot: \"n3\", type: \"flutter.Color\", nullable: false})]))";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsaccent(
        Map<int, Color> swatch) =>
    {
      "_h29466f31ab": r.NativeBinding(
          contract: s.NativeBindingContract.fromJson(<String, Object?>{
            "type": "installed.call",
            "nullable": false,
            "call": <String, Object?>{
              "inputs": <Object?>[
                <String, Object?>{
                  "kind": "native",
                  "nativeType": "dart:core#Map<dart:core#int,dart:ui#Color>"
                }
              ],
              "captures": <String, Object?>{},
              "result": <String, Object?>{
                "kind": "native",
                "nativeType": "flutter.Color"
              },
              "implementation":
                  "29466f31ab626ca1f30fa53a9dabf9744ebe04682543c68764cfd811740d88c9"
            }
          }),
          value: nativeColor_h29466f31ab()),
      "_hc1912c494f": r.NativeBinding(
          contract: s.NativeBindingContract(
              type: 'dart:core#Map<dart:core#int,dart:ui#Color>',
              nullable: false),
          value: swatch),
    };
const nativeColorDslconstant = "ColoredBox(color: data.context._h62d376d3da)";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsconstant(
        Map<int, Color> swatch) =>
    {
      "_h62d376d3da": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: false),
          value: nativeColor_h62d376d3da()),
    };
const nativeColorDslbaseConstant =
    "ColoredBox(color: data.context._h3a3dba19f0)";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsbaseConstant(
        Map<int, Color> swatch) =>
    {
      "_h3a3dba19f0": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: false),
          value: nativeColor_h3a3dba19f0()),
    };
const nativeColorDslalias = "ColoredBox(color: data.context._haccfeceba9)";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsalias(
        Map<int, Color> swatch) =>
    {
      "_haccfeceba9": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: false),
          value: nativeColor_haccfeceba9()),
    };
const nativeColorDslimported = "ColoredBox(color: data.context._hf944d0d7c1)";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsimported(
        Map<int, Color> swatch) =>
    {
      "_hf944d0d7c1": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: false),
          value: nativeColor_hf944d0d7c1()),
    };
const nativeColorDslimportedStatic =
    "ColoredBox(color: data.context._h82d2e17936)";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsimportedStatic(
        Map<int, Color> swatch) =>
    {
      "_h82d2e17936": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: false),
          value: nativeColor_h82d2e17936()),
    };
const nativeColorDslwrappedConst =
    "ColoredBox(color: data.context._hf944d0d7c1)";
Map<String, r.NativeBinding<Object?>> nativeColorBindingswrappedConst(
        Map<int, Color> swatch) =>
    {
      "_hf944d0d7c1": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: false),
          value: nativeColor_hf944d0d7c1()),
    };
const nativeColorDslstaticAlias =
    "ColoredBox(color: data.context._h3be7ce0b47)";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsstaticAlias(
        Map<int, Color> swatch) =>
    {
      "_h3be7ce0b47": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: false),
          value: nativeColor_h3be7ce0b47()),
    };
const nativeColorDsllocalAlias = "ColoredBox(color: data.context._h62d376d3da)";
Map<String, r.NativeBinding<Object?>> nativeColorBindingslocalAlias(
        Map<int, Color> swatch) =>
    {
      "_h62d376d3da": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: false),
          value: nativeColor_h62d376d3da()),
    };
const nativeColorDsllayout =
    "LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[1],\\\"value\\\":{\\\"binding\\\":\\\"_h288429ff9a\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"288429ff9ade00d9e73b96cfd15c12a36e1c70a33b4493fb936001b150a10137\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[2],\\\"name\\\":\\\"n3\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[2],\\\"name\\\":\\\"n4\\\"}],\\\"root\\\":0,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"}},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}}},\\\"locals\\\":{\\\"n3\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"n4\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":2,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":3,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":4,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {c0: data.context._hc1912c494f}, bodies: [(builder0) => Row(children: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0],\\\"name\\\":\\\"n1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[2],\\\"name\\\":\\\"n3_\\\"}],\\\"root\\\":0,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"}},\\\"parameters\\\":{},\\\"locals\\\":{\\\"n1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"n3_\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"sequence\\\",\\\"children\\\":[{\\\"kind\\\":\\\"let\\\",\\\"node\\\":1,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}},{\\\"kind\\\":\\\"let\\\",\\\"node\\\":3,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":1,\\\"values\\\":{}}}]},\\\"bodyCount\\\":2,\\\"nullableResult\\\":true,\\\"collection\\\":true}\", captures: {c0: {kind: \"nativeLocal\", slot: \"n3\", type: \"flutter.Color\", nullable: false}, c1: {kind: \"nativeLocal\", slot: \"n4\", type: \"flutter.Color\", nullable: false}}, bodies: [(builder1) => ColoredBox(color: {kind: \"nativeLocal\", slot: \"n1\", type: \"flutter.Color\", nullable: false}), (builder1) => ColoredBox(color: {kind: \"nativeLocal\", slot: \"n3_\", type: \"flutter.Color\", nullable: false})]))]))";
Map<String, r.NativeBinding<Object?>> nativeColorBindingslayout(
        Map<int, Color> swatch) =>
    {
      "_h288429ff9a": r.NativeBinding(
          contract: s.NativeBindingContract.fromJson(<String, Object?>{
            "type": "installed.call",
            "nullable": false,
            "call": <String, Object?>{
              "inputs": <Object?>[
                <String, Object?>{
                  "kind": "native",
                  "nativeType": "dart:core#Map<dart:core#int,dart:ui#Color>"
                }
              ],
              "captures": <String, Object?>{},
              "result": <String, Object?>{
                "kind": "native",
                "nativeType": "flutter.Color"
              },
              "implementation":
                  "288429ff9ade00d9e73b96cfd15c12a36e1c70a33b4493fb936001b150a10137"
            }
          }),
          value: nativeColor_h288429ff9a()),
      "_hc1912c494f": r.NativeBinding(
          contract: s.NativeBindingContract(
              type: 'dart:core#Map<dart:core#int,dart:ui#Color>',
              nullable: false),
          value: swatch),
    };
const nativeColorDslnullable = "Container(color: data.context._h74bbba614c)";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsnullable(
        Map<int, Color> swatch) =>
    {
      "_h74bbba614c": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: true),
          value: nativeColor_h74bbba614c()),
    };
const nativeColorDslnullableLayout =
    "LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\",\\\"nullable\\\":true},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\",\\\"nullable\\\":true},\\\"inputs\\\":[1],\\\"name\\\":\\\"n2\\\"}],\\\"root\\\":0,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\",\\\"nullable\\\":true}},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}}},\\\"locals\\\":{\\\"n2\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\",\\\"nullable\\\":true}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":2,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {c0: data.context._h74bbba614c}, bodies: [(builder0) => Container(color: {kind: \"nativeLocal\", slot: \"n2\", type: \"flutter.Color\", nullable: true})]))";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsnullableLayout(
        Map<int, Color> swatch) =>
    {
      "_h74bbba614c": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: true),
          value: nativeColor_h74bbba614c()),
    };
