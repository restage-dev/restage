part of 'native_color_selectors.dart';

r.NativeCallAdapter nativeColor_h227c54f8cd() => r.NativeCallAdapter(
  s.NativeBindingContract.fromJson(<String, Object?>{
    "type": "installed.call",
    "nullable": false,
    "call": <String, Object?>{
      "inputs": <Object?>[
        <String, Object?>{"kind": "native", "nativeType": "dart:core#bool"},
        <String, Object?>{"kind": "native", "nativeType": "dart:ui#Color"},
      ],
      "captures": <String, Object?>{},
      "result": <String, Object?>{
        "kind": "native",
        "nativeType": "flutter.Color",
      },
      "implementation":
          "227c54f8cdcd32c4c289c5a6f904b539b31d97145a27fc676347c0118bfd235e",
    },
  }),
  (_restageInputs, _restageCells) {
    T _restageAs<T>(Object? value) => value as T;
    final bool _restageInput0 = _restageAs<bool>(
      (_restageInputs[0] as s.ValueNative).value,
    );
    final Color _restageInput1 = _restageAs<Color>(
      (_restageInputs[1] as s.ValueNative).value,
    );
    final Color _restageResult = _restageInput0 ? _restageInput1 : Colors.red;
    return r.NativeBinding<Color>(
      contract: s.NativeBindingContract(type: "flutter.Color", nullable: false),
      value: _restageResult,
    );
  },
);
r.NativeCallAdapter nativeColor_h8176358fe4() => r.NativeCallAdapter(
  s.NativeBindingContract.fromJson(<String, Object?>{
    "type": "installed.call",
    "nullable": false,
    "call": <String, Object?>{
      "inputs": <Object?>[
        <String, Object?>{"kind": "native", "nativeType": "dart:core#bool"},
        <String, Object?>{"kind": "native", "nativeType": "dart:ui#Color"},
        <String, Object?>{"kind": "native", "nativeType": "dart:ui#Color"},
      ],
      "captures": <String, Object?>{},
      "result": <String, Object?>{
        "kind": "native",
        "nativeType": "flutter.Color",
      },
      "implementation":
          "8176358fe4ea5038305bf103ccdb053ff8190ea86ab3cd9462678169f336c0b2",
    },
  }),
  (_restageInputs, _restageCells) {
    T _restageAs<T>(Object? value) => value as T;
    final bool _restageInput0 = _restageAs<bool>(
      (_restageInputs[0] as s.ValueNative).value,
    );
    final Color _restageInput1 = _restageAs<Color>(
      (_restageInputs[1] as s.ValueNative).value,
    );
    final Color _restageInput2 = _restageAs<Color>(
      (_restageInputs[2] as s.ValueNative).value,
    );
    final Color _restageResult = _restageInput0
        ? _restageInput1
        : _restageInput2;
    return r.NativeBinding<Color>(
      contract: s.NativeBindingContract(type: "flutter.Color", nullable: false),
      value: _restageResult,
    );
  },
);
r.NativeCallAdapter nativeColor_h64cd3f92b2() => r.NativeCallAdapter(
  s.NativeBindingContract.fromJson(<String, Object?>{
    "type": "installed.call",
    "nullable": false,
    "call": <String, Object?>{
      "inputs": <Object?>[
        <String, Object?>{
          "kind": "native",
          "nativeType": "dart:ui#Color?",
          "nullable": true,
        },
        <String, Object?>{"kind": "native", "nativeType": "dart:ui#Color"},
      ],
      "captures": <String, Object?>{},
      "result": <String, Object?>{
        "kind": "native",
        "nativeType": "flutter.Color",
      },
      "implementation":
          "64cd3f92b2f0393cb890f2933764202be6aee5f622c3b542e9ebcee331054361",
    },
  }),
  (_restageInputs, _restageCells) {
    T _restageAs<T>(Object? value) => value as T;
    final Color? _restageInput0 = _restageAs<Color?>(
      (_restageInputs[0] == null
          ? null
          : (_restageInputs[0] as s.ValueNative).value),
    );
    final Color _restageInput1 = _restageAs<Color>(
      (_restageInputs[1] as s.ValueNative).value,
    );
    final Color _restageResult = _restageInput0 ?? _restageInput1;
    return r.NativeBinding<Color>(
      contract: s.NativeBindingContract(type: "flutter.Color", nullable: false),
      value: _restageResult,
    );
  },
);
r.NativeCallAdapter nativeColor_h1593b1f9df() => r.NativeCallAdapter(
  s.NativeBindingContract.fromJson(<String, Object?>{
    "type": "installed.call",
    "nullable": false,
    "call": <String, Object?>{
      "inputs": <Object?>[
        <String, Object?>{"kind": "native", "nativeType": "dart:core#bool"},
        <String, Object?>{
          "kind": "native",
          "nativeType": "dart:ui#Color?",
          "nullable": true,
        },
      ],
      "captures": <String, Object?>{},
      "result": <String, Object?>{
        "kind": "native",
        "nativeType": "flutter.Color",
        "nullable": true,
      },
      "implementation":
          "1593b1f9df092481db583889f85ad0732516270f3b4bdee6153f0fadbe1a34fd",
    },
  }),
  (_restageInputs, _restageCells) {
    T _restageAs<T>(Object? value) => value as T;
    final bool _restageInput0 = _restageAs<bool>(
      (_restageInputs[0] as s.ValueNative).value,
    );
    final Color? _restageInput1 = _restageAs<Color?>(
      (_restageInputs[1] == null
          ? null
          : (_restageInputs[1] as s.ValueNative).value),
    );
    final Color? _restageResult = _restageInput0 ? _restageInput1 : null;
    if (_restageResult == null) return null;
    return r.NativeBinding<Color?>(
      contract: s.NativeBindingContract(type: "flutter.Color", nullable: true),
      value: _restageResult,
    );
  },
);
r.NativeCallAdapter nativeColor_hc9f7827385() => r.NativeCallAdapter(
  s.NativeBindingContract.fromJson(<String, Object?>{
    "type": "installed.call",
    "nullable": false,
    "call": <String, Object?>{
      "inputs": <Object?>[
        <String, Object?>{
          "kind": "native",
          "nativeType": "dart:ui#Color?",
          "nullable": true,
        },
        <String, Object?>{"kind": "native", "nativeType": "dart:core#bool"},
        <String, Object?>{"kind": "native", "nativeType": "dart:ui#Color"},
      ],
      "captures": <String, Object?>{},
      "result": <String, Object?>{
        "kind": "native",
        "nativeType": "flutter.Color",
        "nullable": true,
      },
      "implementation":
          "c9f7827385d9af1a8e460406fecf19ee57a52b2230907f6fc33a782ec02a5c37",
    },
  }),
  (_restageInputs, _restageCells) {
    T _restageAs<T>(Object? value) => value as T;
    final Color? _restageInput0 = _restageAs<Color?>(
      (_restageInputs[0] == null
          ? null
          : (_restageInputs[0] as s.ValueNative).value),
    );
    final bool _restageInput1 = _restageAs<bool>(
      (_restageInputs[1] as s.ValueNative).value,
    );
    final Color _restageInput2 = _restageAs<Color>(
      (_restageInputs[2] as s.ValueNative).value,
    );
    final Color? _restageResult =
        _restageInput0 ?? (_restageInput1 ? _restageInput2 : null);
    if (_restageResult == null) return null;
    return r.NativeBinding<Color?>(
      contract: s.NativeBindingContract(type: "flutter.Color", nullable: true),
      value: _restageResult,
    );
  },
);
r.NativeCallAdapter nativeColor_hcf8fa18a0c() => r.NativeCallAdapter(
  s.NativeBindingContract.fromJson(<String, Object?>{
    "type": "installed.call",
    "nullable": false,
    "call": <String, Object?>{
      "inputs": <Object?>[
        <String, Object?>{"kind": "native", "nativeType": "dart:core#bool"},
        <String, Object?>{
          "kind": "native",
          "nativeType": "dart:ui#Color?",
          "nullable": true,
        },
        <String, Object?>{"kind": "native", "nativeType": "dart:ui#Color"},
      ],
      "captures": <String, Object?>{},
      "result": <String, Object?>{
        "kind": "native",
        "nativeType": "flutter.Color",
      },
      "implementation":
          "cf8fa18a0c069e8d1cec4359e9452b2f0a228b1c70547992d6b8369a10a46fc3",
    },
  }),
  (_restageInputs, _restageCells) {
    T _restageAs<T>(Object? value) => value as T;
    final bool _restageInput0 = _restageAs<bool>(
      (_restageInputs[0] as s.ValueNative).value,
    );
    final Color? _restageInput1 = _restageAs<Color?>(
      (_restageInputs[1] == null
          ? null
          : (_restageInputs[1] as s.ValueNative).value),
    );
    final Color _restageInput2 = _restageAs<Color>(
      (_restageInputs[2] as s.ValueNative).value,
    );
    final Color _restageResult = !_restageInput0 || _restageInput1 == null
        ? Colors.red
        : _restageInput2;
    return r.NativeBinding<Color>(
      contract: s.NativeBindingContract(type: "flutter.Color", nullable: false),
      value: _restageResult,
    );
  },
);
const nativeSelectorDslconditional =
    "ColoredBox(color: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0,1],\\\"value\\\":{\\\"binding\\\":\\\"_h227c54f8cd\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"227c54f8cdcd32c4c289c5a6f904b539b31d97145a27fc676347c0118bfd235e\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":2,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._ha36787c06c, c1: data.context._h1476dbc035 } })";
Map<String, r.NativeBinding<Object?>> nativeSelectorBindingsconditional({
  required bool flag,
  required Color color,
  required Color? maybeColor,
  required Color other,
}) => {
  "_h1476dbc035": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color', nullable: false),
    value: color,
  ),
  "_h227c54f8cd": r.NativeBinding(
    contract: s.NativeBindingContract.fromJson(<String, Object?>{
      "type": "installed.call",
      "nullable": false,
      "call": <String, Object?>{
        "inputs": <Object?>[
          <String, Object?>{"kind": "native", "nativeType": "dart:core#bool"},
          <String, Object?>{"kind": "native", "nativeType": "dart:ui#Color"},
        ],
        "captures": <String, Object?>{},
        "result": <String, Object?>{
          "kind": "native",
          "nativeType": "flutter.Color",
        },
        "implementation":
            "227c54f8cdcd32c4c289c5a6f904b539b31d97145a27fc676347c0118bfd235e",
      },
    }),
    value: nativeColor_h227c54f8cd(),
  ),
  "_ha36787c06c": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:core#bool', nullable: false),
    value: flag,
  ),
};
const nativeSelectorDslalias =
    "ColoredBox(color: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0,1],\\\"value\\\":{\\\"binding\\\":\\\"_h227c54f8cd\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"227c54f8cdcd32c4c289c5a6f904b539b31d97145a27fc676347c0118bfd235e\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":2,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._ha36787c06c, c1: data.context._h1476dbc035 } })";
Map<String, r.NativeBinding<Object?>> nativeSelectorBindingsalias({
  required bool flag,
  required Color color,
  required Color? maybeColor,
  required Color other,
}) => {
  "_h1476dbc035": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color', nullable: false),
    value: color,
  ),
  "_h227c54f8cd": r.NativeBinding(
    contract: s.NativeBindingContract.fromJson(<String, Object?>{
      "type": "installed.call",
      "nullable": false,
      "call": <String, Object?>{
        "inputs": <Object?>[
          <String, Object?>{"kind": "native", "nativeType": "dart:core#bool"},
          <String, Object?>{"kind": "native", "nativeType": "dart:ui#Color"},
        ],
        "captures": <String, Object?>{},
        "result": <String, Object?>{
          "kind": "native",
          "nativeType": "flutter.Color",
        },
        "implementation":
            "227c54f8cdcd32c4c289c5a6f904b539b31d97145a27fc676347c0118bfd235e",
      },
    }),
    value: nativeColor_h227c54f8cd(),
  ),
  "_ha36787c06c": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:core#bool', nullable: false),
    value: flag,
  ),
};
const nativeSelectorDslborrowedBoth =
    "ColoredBox(color: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c2\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0,1,2],\\\"value\\\":{\\\"binding\\\":\\\"_h8176358fe4\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"8176358fe4ea5038305bf103ccdb053ff8190ea86ab3cd9462678169f336c0b2\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":3,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"c2\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._ha36787c06c, c1: data.context._h1476dbc035, c2: data.context._h3bfaebed40 } })";
Map<String, r.NativeBinding<Object?>> nativeSelectorBindingsborrowedBoth({
  required bool flag,
  required Color color,
  required Color? maybeColor,
  required Color other,
}) => {
  "_h1476dbc035": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color', nullable: false),
    value: color,
  ),
  "_h3bfaebed40": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color', nullable: false),
    value: other,
  ),
  "_h8176358fe4": r.NativeBinding(
    contract: s.NativeBindingContract.fromJson(<String, Object?>{
      "type": "installed.call",
      "nullable": false,
      "call": <String, Object?>{
        "inputs": <Object?>[
          <String, Object?>{"kind": "native", "nativeType": "dart:core#bool"},
          <String, Object?>{"kind": "native", "nativeType": "dart:ui#Color"},
          <String, Object?>{"kind": "native", "nativeType": "dart:ui#Color"},
        ],
        "captures": <String, Object?>{},
        "result": <String, Object?>{
          "kind": "native",
          "nativeType": "flutter.Color",
        },
        "implementation":
            "8176358fe4ea5038305bf103ccdb053ff8190ea86ab3cd9462678169f336c0b2",
      },
    }),
    value: nativeColor_h8176358fe4(),
  ),
  "_ha36787c06c": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:core#bool', nullable: false),
    value: flag,
  ),
};
const nativeSelectorDslcoalesce =
    "ColoredBox(color: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0,1],\\\"value\\\":{\\\"binding\\\":\\\"_h64cd3f92b2\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"64cd3f92b2f0393cb890f2933764202be6aee5f622c3b542e9ebcee331054361\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":2,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._h5b7dbd5757, c1: data.context._h1476dbc035 } })";
Map<String, r.NativeBinding<Object?>> nativeSelectorBindingscoalesce({
  required bool flag,
  required Color color,
  required Color? maybeColor,
  required Color other,
}) => {
  "_h1476dbc035": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color', nullable: false),
    value: color,
  ),
  "_h5b7dbd5757": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color?', nullable: true),
    value: maybeColor,
  ),
  "_h64cd3f92b2": r.NativeBinding(
    contract: s.NativeBindingContract.fromJson(<String, Object?>{
      "type": "installed.call",
      "nullable": false,
      "call": <String, Object?>{
        "inputs": <Object?>[
          <String, Object?>{
            "kind": "native",
            "nativeType": "dart:ui#Color?",
            "nullable": true,
          },
          <String, Object?>{"kind": "native", "nativeType": "dart:ui#Color"},
        ],
        "captures": <String, Object?>{},
        "result": <String, Object?>{
          "kind": "native",
          "nativeType": "flutter.Color",
        },
        "implementation":
            "64cd3f92b2f0393cb890f2933764202be6aee5f622c3b542e9ebcee331054361",
      },
    }),
    value: nativeColor_h64cd3f92b2(),
  ),
};
const nativeSelectorDslnullable =
    "Container(color: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\",\\\"nullable\\\":true},\\\"inputs\\\":[0,1],\\\"value\\\":{\\\"binding\\\":\\\"_h1593b1f9df\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\",\\\"nullable\\\":true},\\\"implementation\\\":\\\"1593b1f9df092481db583889f85ad0732516270f3b4bdee6153f0fadbe1a34fd\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":2,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true}},\\\"parameters\\\":{}}\", captures: {c0: data.context._ha36787c06c, c1: data.context._h5b7dbd5757 } })";
Map<String, r.NativeBinding<Object?>> nativeSelectorBindingsnullable({
  required bool flag,
  required Color color,
  required Color? maybeColor,
  required Color other,
}) => {
  "_h1593b1f9df": r.NativeBinding(
    contract: s.NativeBindingContract.fromJson(<String, Object?>{
      "type": "installed.call",
      "nullable": false,
      "call": <String, Object?>{
        "inputs": <Object?>[
          <String, Object?>{"kind": "native", "nativeType": "dart:core#bool"},
          <String, Object?>{
            "kind": "native",
            "nativeType": "dart:ui#Color?",
            "nullable": true,
          },
        ],
        "captures": <String, Object?>{},
        "result": <String, Object?>{
          "kind": "native",
          "nativeType": "flutter.Color",
          "nullable": true,
        },
        "implementation":
            "1593b1f9df092481db583889f85ad0732516270f3b4bdee6153f0fadbe1a34fd",
      },
    }),
    value: nativeColor_h1593b1f9df(),
  ),
  "_h5b7dbd5757": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color?', nullable: true),
    value: maybeColor,
  ),
  "_ha36787c06c": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:core#bool', nullable: false),
    value: flag,
  ),
};
const nativeSelectorDslnullableCoalesce =
    "Container(color: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c2\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\",\\\"nullable\\\":true},\\\"inputs\\\":[0,1,2],\\\"value\\\":{\\\"binding\\\":\\\"_hc9f7827385\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\",\\\"nullable\\\":true},\\\"implementation\\\":\\\"c9f7827385d9af1a8e460406fecf19ee57a52b2230907f6fc33a782ec02a5c37\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":3,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"c2\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._h5b7dbd5757, c1: data.context._ha36787c06c, c2: data.context._h1476dbc035 } })";
Map<String, r.NativeBinding<Object?>> nativeSelectorBindingsnullableCoalesce({
  required bool flag,
  required Color color,
  required Color? maybeColor,
  required Color other,
}) => {
  "_h1476dbc035": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color', nullable: false),
    value: color,
  ),
  "_h5b7dbd5757": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color?', nullable: true),
    value: maybeColor,
  ),
  "_ha36787c06c": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:core#bool', nullable: false),
    value: flag,
  ),
  "_hc9f7827385": r.NativeBinding(
    contract: s.NativeBindingContract.fromJson(<String, Object?>{
      "type": "installed.call",
      "nullable": false,
      "call": <String, Object?>{
        "inputs": <Object?>[
          <String, Object?>{
            "kind": "native",
            "nativeType": "dart:ui#Color?",
            "nullable": true,
          },
          <String, Object?>{"kind": "native", "nativeType": "dart:core#bool"},
          <String, Object?>{"kind": "native", "nativeType": "dart:ui#Color"},
        ],
        "captures": <String, Object?>{},
        "result": <String, Object?>{
          "kind": "native",
          "nativeType": "flutter.Color",
          "nullable": true,
        },
        "implementation":
            "c9f7827385d9af1a8e460406fecf19ee57a52b2230907f6fc33a782ec02a5c37",
      },
    }),
    value: nativeColor_hc9f7827385(),
  ),
};
const nativeSelectorDslnested =
    "ColoredBox(color: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c2\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0,1,2],\\\"value\\\":{\\\"binding\\\":\\\"_hcf8fa18a0c\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"cf8fa18a0c069e8d1cec4359e9452b2f0a228b1c70547992d6b8369a10a46fc3\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":3,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"c2\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._ha36787c06c, c1: data.context._h5b7dbd5757, c2: data.context._h1476dbc035 } })";
Map<String, r.NativeBinding<Object?>> nativeSelectorBindingsnested({
  required bool flag,
  required Color color,
  required Color? maybeColor,
  required Color other,
}) => {
  "_h1476dbc035": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color', nullable: false),
    value: color,
  ),
  "_h5b7dbd5757": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color?', nullable: true),
    value: maybeColor,
  ),
  "_ha36787c06c": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:core#bool', nullable: false),
    value: flag,
  ),
  "_hcf8fa18a0c": r.NativeBinding(
    contract: s.NativeBindingContract.fromJson(<String, Object?>{
      "type": "installed.call",
      "nullable": false,
      "call": <String, Object?>{
        "inputs": <Object?>[
          <String, Object?>{"kind": "native", "nativeType": "dart:core#bool"},
          <String, Object?>{
            "kind": "native",
            "nativeType": "dart:ui#Color?",
            "nullable": true,
          },
          <String, Object?>{"kind": "native", "nativeType": "dart:ui#Color"},
        ],
        "captures": <String, Object?>{},
        "result": <String, Object?>{
          "kind": "native",
          "nativeType": "flutter.Color",
        },
        "implementation":
            "cf8fa18a0c069e8d1cec4359e9452b2f0a228b1c70547992d6b8369a10a46fc3",
      },
    }),
    value: nativeColor_hcf8fa18a0c(),
  ),
};
const nativeSelectorDsllayout =
    "LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[1,2],\\\"value\\\":{\\\"binding\\\":\\\"_h227c54f8cd\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"227c54f8cdcd32c4c289c5a6f904b539b31d97145a27fc676347c0118bfd235e\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[3],\\\"name\\\":\\\"n4\\\"}],\\\"root\\\":0,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}}},\\\"locals\\\":{\\\"n4\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":4,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {c0: data.context._ha36787c06c, c1: data.context._h1476dbc035}, bodies: [(builder0) => ColoredBox(color: {kind: \"nativeLocal\", slot: \"n4\", type: \"flutter.Color\", nullable: false})]))";
Map<String, r.NativeBinding<Object?>> nativeSelectorBindingslayout({
  required bool flag,
  required Color color,
  required Color? maybeColor,
  required Color other,
}) => {
  "_h1476dbc035": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color', nullable: false),
    value: color,
  ),
  "_h227c54f8cd": r.NativeBinding(
    contract: s.NativeBindingContract.fromJson(<String, Object?>{
      "type": "installed.call",
      "nullable": false,
      "call": <String, Object?>{
        "inputs": <Object?>[
          <String, Object?>{"kind": "native", "nativeType": "dart:core#bool"},
          <String, Object?>{"kind": "native", "nativeType": "dart:ui#Color"},
        ],
        "captures": <String, Object?>{},
        "result": <String, Object?>{
          "kind": "native",
          "nativeType": "flutter.Color",
        },
        "implementation":
            "227c54f8cdcd32c4c289c5a6f904b539b31d97145a27fc676347c0118bfd235e",
      },
    }),
    value: nativeColor_h227c54f8cd(),
  ),
  "_ha36787c06c": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:core#bool', nullable: false),
    value: flag,
  ),
};
const nativeSelectorDslsvgTheme =
    "SvgPictureString(string: \"<svg xmlns=\\\"http://www.w3.org/2000/svg\\\" width=\\\"8\\\" height=\\\"8\\\"><path d=\\\"M0 0h8v8H0z\\\" fill=\\\"currentColor\\\"/></svg>\", theme: {currentColor: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0,1],\\\"value\\\":{\\\"binding\\\":\\\"_h64cd3f92b2\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"64cd3f92b2f0393cb890f2933764202be6aee5f622c3b542e9ebcee331054361\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":2,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._h5b7dbd5757, c1: data.context._h1476dbc035 } }})";
Map<String, r.NativeBinding<Object?>> nativeSelectorBindingssvgTheme({
  required bool flag,
  required Color color,
  required Color? maybeColor,
  required Color other,
}) => {
  "_h1476dbc035": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color', nullable: false),
    value: color,
  ),
  "_h5b7dbd5757": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color?', nullable: true),
    value: maybeColor,
  ),
  "_h64cd3f92b2": r.NativeBinding(
    contract: s.NativeBindingContract.fromJson(<String, Object?>{
      "type": "installed.call",
      "nullable": false,
      "call": <String, Object?>{
        "inputs": <Object?>[
          <String, Object?>{
            "kind": "native",
            "nativeType": "dart:ui#Color?",
            "nullable": true,
          },
          <String, Object?>{"kind": "native", "nativeType": "dart:ui#Color"},
        ],
        "captures": <String, Object?>{},
        "result": <String, Object?>{
          "kind": "native",
          "nativeType": "flutter.Color",
        },
        "implementation":
            "64cd3f92b2f0393cb890f2933764202be6aee5f622c3b542e9ebcee331054361",
      },
    }),
    value: nativeColor_h64cd3f92b2(),
  ),
};
const nativeSelectorDslsvgFilter =
    "SvgPictureString(string: \"<svg xmlns=\\\"http://www.w3.org/2000/svg\\\" width=\\\"8\\\" height=\\\"8\\\"><path d=\\\"M0 0h8v8H0z\\\" fill=\\\"currentColor\\\"/></svg>\", colorFilter: {kind: \"mode\", color: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0,1],\\\"value\\\":{\\\"binding\\\":\\\"_h227c54f8cd\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"227c54f8cdcd32c4c289c5a6f904b539b31d97145a27fc676347c0118bfd235e\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":2,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._ha36787c06c, c1: data.context._h1476dbc035 } }, blendMode: \"srcIn\"})";
Map<String, r.NativeBinding<Object?>> nativeSelectorBindingssvgFilter({
  required bool flag,
  required Color color,
  required Color? maybeColor,
  required Color other,
}) => {
  "_h1476dbc035": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color', nullable: false),
    value: color,
  ),
  "_h227c54f8cd": r.NativeBinding(
    contract: s.NativeBindingContract.fromJson(<String, Object?>{
      "type": "installed.call",
      "nullable": false,
      "call": <String, Object?>{
        "inputs": <Object?>[
          <String, Object?>{"kind": "native", "nativeType": "dart:core#bool"},
          <String, Object?>{"kind": "native", "nativeType": "dart:ui#Color"},
        ],
        "captures": <String, Object?>{},
        "result": <String, Object?>{
          "kind": "native",
          "nativeType": "flutter.Color",
        },
        "implementation":
            "227c54f8cdcd32c4c289c5a6f904b539b31d97145a27fc676347c0118bfd235e",
      },
    }),
    value: nativeColor_h227c54f8cd(),
  ),
  "_ha36787c06c": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:core#bool', nullable: false),
    value: flag,
  ),
};
const nativeSelectorDslsvgBoth =
    "SvgPictureString(string: \"<svg xmlns=\\\"http://www.w3.org/2000/svg\\\" width=\\\"8\\\" height=\\\"8\\\"><path d=\\\"M0 0h8v8H0z\\\" fill=\\\"currentColor\\\"/></svg>\", theme: {currentColor: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0,1],\\\"value\\\":{\\\"binding\\\":\\\"_h64cd3f92b2\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"64cd3f92b2f0393cb890f2933764202be6aee5f622c3b542e9ebcee331054361\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":2,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._h5b7dbd5757, c1: data.context._h1476dbc035 } }}, colorFilter: {kind: \"mode\", color: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0,1],\\\"value\\\":{\\\"binding\\\":\\\"_h227c54f8cd\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"227c54f8cdcd32c4c289c5a6f904b539b31d97145a27fc676347c0118bfd235e\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":2,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._ha36787c06c, c1: data.context._h1476dbc035 } }, blendMode: \"srcIn\"})";
Map<String, r.NativeBinding<Object?>> nativeSelectorBindingssvgBoth({
  required bool flag,
  required Color color,
  required Color? maybeColor,
  required Color other,
}) => {
  "_h1476dbc035": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color', nullable: false),
    value: color,
  ),
  "_h227c54f8cd": r.NativeBinding(
    contract: s.NativeBindingContract.fromJson(<String, Object?>{
      "type": "installed.call",
      "nullable": false,
      "call": <String, Object?>{
        "inputs": <Object?>[
          <String, Object?>{"kind": "native", "nativeType": "dart:core#bool"},
          <String, Object?>{"kind": "native", "nativeType": "dart:ui#Color"},
        ],
        "captures": <String, Object?>{},
        "result": <String, Object?>{
          "kind": "native",
          "nativeType": "flutter.Color",
        },
        "implementation":
            "227c54f8cdcd32c4c289c5a6f904b539b31d97145a27fc676347c0118bfd235e",
      },
    }),
    value: nativeColor_h227c54f8cd(),
  ),
  "_h5b7dbd5757": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color?', nullable: true),
    value: maybeColor,
  ),
  "_h64cd3f92b2": r.NativeBinding(
    contract: s.NativeBindingContract.fromJson(<String, Object?>{
      "type": "installed.call",
      "nullable": false,
      "call": <String, Object?>{
        "inputs": <Object?>[
          <String, Object?>{
            "kind": "native",
            "nativeType": "dart:ui#Color?",
            "nullable": true,
          },
          <String, Object?>{"kind": "native", "nativeType": "dart:ui#Color"},
        ],
        "captures": <String, Object?>{},
        "result": <String, Object?>{
          "kind": "native",
          "nativeType": "flutter.Color",
        },
        "implementation":
            "64cd3f92b2f0393cb890f2933764202be6aee5f622c3b542e9ebcee331054361",
      },
    }),
    value: nativeColor_h64cd3f92b2(),
  ),
  "_ha36787c06c": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:core#bool', nullable: false),
    value: flag,
  ),
};
