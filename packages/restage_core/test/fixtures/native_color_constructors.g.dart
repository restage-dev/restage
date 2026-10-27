part of 'native_color_constructors.dart';

r.NativeCallAdapter nativeColor_hef06d27cd5() => r.NativeCallAdapter(
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
                "ef06d27cd50049f1747e0a113b108c680e6cf4432cda658d18cb4ad503e36317"
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
r.NativeCallAdapter nativeColor_h0ad4e8efcd() => r.NativeCallAdapter(
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
                "0ad4e8efcde37366e2d8cd381a83630c54bad040f0157ec2a224bc00a496a941"
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
MaterialColor nativeColor_h7d28a2f9be() =>
    const MaterialColor(0xff102030, {500: Color(0xff102030)});
Color nativeColor_h329ec15e67() =>
    const Color.from(alpha: 1, red: .123456789, green: .3, blue: .4);
MaterialColor nativeColor_hc327f4621c() => localPalette;
MaterialColor nativeColor_h32cc6b076d() => palette.importedColor;
MaterialAccentColor nativeColor_hc4a47b1759() => palette.Palette.color;
MaterialAccentColor nativeColor_h721477f8a7() =>
    ColorConstructorSource.staticPalette;
Color? nativeColor_hef4dd8864d() => absentColor;
const nativeColorDslfresh =
    "LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[1],\\\"value\\\":{\\\"binding\\\":\\\"_hef06d27cd5\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"ef06d27cd50049f1747e0a113b108c680e6cf4432cda658d18cb4ad503e36317\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[2],\\\"name\\\":\\\"n3\\\"}],\\\"root\\\":0,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"}},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}}},\\\"locals\\\":{\\\"n3\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":2,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":3,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {c0: data.context._hc1912c494f}, bodies: [(builder0) => ColoredBox(color: {kind: \"nativeLocal\", slot: \"n3\", type: \"flutter.Color\", nullable: false})]))";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsfresh(
        Map<int, Color> swatch) =>
    {
      "_hc1912c494f": r.NativeBinding(
          contract: s.NativeBindingContract(
              type: 'dart:core#Map<dart:core#int,dart:ui#Color>',
              nullable: false),
          value: swatch),
      "_hef06d27cd5": r.NativeBinding(
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
                  "ef06d27cd50049f1747e0a113b108c680e6cf4432cda658d18cb4ad503e36317"
            }
          }),
          value: nativeColor_hef06d27cd5()),
    };
const nativeColorDslaccent =
    "LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[1],\\\"value\\\":{\\\"binding\\\":\\\"_h0ad4e8efcd\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"0ad4e8efcde37366e2d8cd381a83630c54bad040f0157ec2a224bc00a496a941\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[2],\\\"name\\\":\\\"n3\\\"}],\\\"root\\\":0,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"}},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}}},\\\"locals\\\":{\\\"n3\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":2,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":3,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {c0: data.context._hc1912c494f}, bodies: [(builder0) => ColoredBox(color: {kind: \"nativeLocal\", slot: \"n3\", type: \"flutter.Color\", nullable: false})]))";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsaccent(
        Map<int, Color> swatch) =>
    {
      "_h0ad4e8efcd": r.NativeBinding(
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
                  "0ad4e8efcde37366e2d8cd381a83630c54bad040f0157ec2a224bc00a496a941"
            }
          }),
          value: nativeColor_h0ad4e8efcd()),
      "_hc1912c494f": r.NativeBinding(
          contract: s.NativeBindingContract(
              type: 'dart:core#Map<dart:core#int,dart:ui#Color>',
              nullable: false),
          value: swatch),
    };
const nativeColorDslconstant = "ColoredBox(color: data.context._h7d28a2f9be)";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsconstant(
        Map<int, Color> swatch) =>
    {
      "_h7d28a2f9be": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: false),
          value: nativeColor_h7d28a2f9be()),
    };
const nativeColorDslbaseConstant =
    "ColoredBox(color: data.context._h329ec15e67)";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsbaseConstant(
        Map<int, Color> swatch) =>
    {
      "_h329ec15e67": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: false),
          value: nativeColor_h329ec15e67()),
    };
const nativeColorDslalias = "ColoredBox(color: data.context._hc327f4621c)";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsalias(
        Map<int, Color> swatch) =>
    {
      "_hc327f4621c": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: false),
          value: nativeColor_hc327f4621c()),
    };
const nativeColorDslimported = "ColoredBox(color: data.context._h32cc6b076d)";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsimported(
        Map<int, Color> swatch) =>
    {
      "_h32cc6b076d": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: false),
          value: nativeColor_h32cc6b076d()),
    };
const nativeColorDslimportedStatic =
    "ColoredBox(color: data.context._hc4a47b1759)";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsimportedStatic(
        Map<int, Color> swatch) =>
    {
      "_hc4a47b1759": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: false),
          value: nativeColor_hc4a47b1759()),
    };
const nativeColorDslwrappedConst =
    "ColoredBox(color: data.context._h32cc6b076d)";
Map<String, r.NativeBinding<Object?>> nativeColorBindingswrappedConst(
        Map<int, Color> swatch) =>
    {
      "_h32cc6b076d": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: false),
          value: nativeColor_h32cc6b076d()),
    };
const nativeColorDslstaticAlias =
    "ColoredBox(color: data.context._h721477f8a7)";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsstaticAlias(
        Map<int, Color> swatch) =>
    {
      "_h721477f8a7": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: false),
          value: nativeColor_h721477f8a7()),
    };
const nativeColorDsllocalAlias = "ColoredBox(color: data.context._h7d28a2f9be)";
Map<String, r.NativeBinding<Object?>> nativeColorBindingslocalAlias(
        Map<int, Color> swatch) =>
    {
      "_h7d28a2f9be": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: false),
          value: nativeColor_h7d28a2f9be()),
    };
const nativeColorDsllayout =
    "LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[1],\\\"value\\\":{\\\"binding\\\":\\\"_hef06d27cd5\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"ef06d27cd50049f1747e0a113b108c680e6cf4432cda658d18cb4ad503e36317\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[2],\\\"name\\\":\\\"n3\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[2],\\\"name\\\":\\\"n4\\\"}],\\\"root\\\":0,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#Map<dart:core#int,dart:ui#Color>\\\"}},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}}},\\\"locals\\\":{\\\"n3\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"n4\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":2,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":3,\\\"then\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":4,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {c0: data.context._hc1912c494f}, bodies: [(builder0) => Row(children: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0],\\\"name\\\":\\\"n1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[2],\\\"name\\\":\\\"n3_\\\"}],\\\"root\\\":0,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"}},\\\"parameters\\\":{},\\\"locals\\\":{\\\"n1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"n3_\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"sequence\\\",\\\"children\\\":[{\\\"kind\\\":\\\"let\\\",\\\"node\\\":1,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}},{\\\"kind\\\":\\\"let\\\",\\\"node\\\":3,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":1,\\\"values\\\":{}}}]},\\\"bodyCount\\\":2,\\\"nullableResult\\\":true,\\\"collection\\\":true}\", captures: {c0: {kind: \"nativeLocal\", slot: \"n3\", type: \"flutter.Color\", nullable: false}, c1: {kind: \"nativeLocal\", slot: \"n4\", type: \"flutter.Color\", nullable: false}}, bodies: [(builder1) => ColoredBox(color: {kind: \"nativeLocal\", slot: \"n1\", type: \"flutter.Color\", nullable: false}), (builder1) => ColoredBox(color: {kind: \"nativeLocal\", slot: \"n3_\", type: \"flutter.Color\", nullable: false})]))]))";
Map<String, r.NativeBinding<Object?>> nativeColorBindingslayout(
        Map<int, Color> swatch) =>
    {
      "_hc1912c494f": r.NativeBinding(
          contract: s.NativeBindingContract(
              type: 'dart:core#Map<dart:core#int,dart:ui#Color>',
              nullable: false),
          value: swatch),
      "_hef06d27cd5": r.NativeBinding(
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
                  "ef06d27cd50049f1747e0a113b108c680e6cf4432cda658d18cb4ad503e36317"
            }
          }),
          value: nativeColor_hef06d27cd5()),
    };
const nativeColorDslnullable = "Container(color: data.context._hef4dd8864d)";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsnullable(
        Map<int, Color> swatch) =>
    {
      "_hef4dd8864d": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: true),
          value: nativeColor_hef4dd8864d()),
    };
const nativeColorDslnullableLayout =
    "LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\",\\\"nullable\\\":true},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\",\\\"nullable\\\":true},\\\"inputs\\\":[1],\\\"name\\\":\\\"n2\\\"}],\\\"root\\\":0,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\",\\\"nullable\\\":true}},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}}},\\\"locals\\\":{\\\"n2\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\",\\\"nullable\\\":true}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":2,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {c0: data.context._hef4dd8864d}, bodies: [(builder0) => Container(color: {kind: \"nativeLocal\", slot: \"n2\", type: \"flutter.Color\", nullable: true})]))";
Map<String, r.NativeBinding<Object?>> nativeColorBindingsnullableLayout(
        Map<int, Color> swatch) =>
    {
      "_hef4dd8864d": r.NativeBinding(
          contract:
              s.NativeBindingContract(type: 'flutter.Color', nullable: true),
          value: nativeColor_hef4dd8864d()),
    };
