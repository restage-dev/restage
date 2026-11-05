part of 'native_color_selectors.dart';

r.NativeCallAdapter nativeColor_h71d09ad9ec() => r.NativeCallAdapter(
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
          "71d09ad9ec96f4c80217bbc7362d810205b7b3bf3ab713ca8f1b5304c0fcc7c4",
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
r.NativeCallAdapter nativeColor_hb56b61f80f() => r.NativeCallAdapter(
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
          "b56b61f80fd1377cc19707b9ea94668f05f523250e725fae344633674a3e82bd",
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
r.NativeCallAdapter nativeColor_h7d6328f993() => r.NativeCallAdapter(
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
          "7d6328f993eae5a06b1d133387b531ccc148252c8408fcd6224b630c891c85fd",
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
r.NativeCallAdapter nativeColor_ha232d3a82e() => r.NativeCallAdapter(
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
          "a232d3a82eab2122386e906b2d1e16f99161c0140ca578f11796a1712af5b84d",
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
r.NativeCallAdapter nativeColor_h2bd1735240() => r.NativeCallAdapter(
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
          "2bd1735240b303fb246d5c3391260e13542096a09ba47dda630a5444c5603de5",
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
r.NativeCallAdapter nativeColor_h4c85ea5024() => r.NativeCallAdapter(
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
          "4c85ea50246dd8d8009b00e0c15ed9c44bb02e80432810de8690ca193e79e4e3",
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
    "ColoredBox(color: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0,1],\\\"value\\\":{\\\"binding\\\":\\\"_h71d09ad9ec\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"71d09ad9ec96f4c80217bbc7362d810205b7b3bf3ab713ca8f1b5304c0fcc7c4\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":2,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._ha36787c06c, c1: data.context._h1476dbc035 } })";
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
  "_h71d09ad9ec": r.NativeBinding(
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
            "71d09ad9ec96f4c80217bbc7362d810205b7b3bf3ab713ca8f1b5304c0fcc7c4",
      },
    }),
    value: nativeColor_h71d09ad9ec(),
  ),
  "_ha36787c06c": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:core#bool', nullable: false),
    value: flag,
  ),
};
const nativeSelectorDslalias =
    "ColoredBox(color: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0,1],\\\"value\\\":{\\\"binding\\\":\\\"_h71d09ad9ec\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"71d09ad9ec96f4c80217bbc7362d810205b7b3bf3ab713ca8f1b5304c0fcc7c4\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":2,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._ha36787c06c, c1: data.context._h1476dbc035 } })";
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
  "_h71d09ad9ec": r.NativeBinding(
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
            "71d09ad9ec96f4c80217bbc7362d810205b7b3bf3ab713ca8f1b5304c0fcc7c4",
      },
    }),
    value: nativeColor_h71d09ad9ec(),
  ),
  "_ha36787c06c": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:core#bool', nullable: false),
    value: flag,
  ),
};
const nativeSelectorDslborrowedBoth =
    "ColoredBox(color: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c2\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0,1,2],\\\"value\\\":{\\\"binding\\\":\\\"_hb56b61f80f\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"b56b61f80fd1377cc19707b9ea94668f05f523250e725fae344633674a3e82bd\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":3,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"c2\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._ha36787c06c, c1: data.context._h1476dbc035, c2: data.context._h3bfaebed40 } })";
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
  "_ha36787c06c": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:core#bool', nullable: false),
    value: flag,
  ),
  "_hb56b61f80f": r.NativeBinding(
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
            "b56b61f80fd1377cc19707b9ea94668f05f523250e725fae344633674a3e82bd",
      },
    }),
    value: nativeColor_hb56b61f80f(),
  ),
};
const nativeSelectorDslcoalesce =
    "ColoredBox(color: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0,1],\\\"value\\\":{\\\"binding\\\":\\\"_h7d6328f993\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"7d6328f993eae5a06b1d133387b531ccc148252c8408fcd6224b630c891c85fd\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":2,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._h5b7dbd5757, c1: data.context._h1476dbc035 } })";
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
  "_h7d6328f993": r.NativeBinding(
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
            "7d6328f993eae5a06b1d133387b531ccc148252c8408fcd6224b630c891c85fd",
      },
    }),
    value: nativeColor_h7d6328f993(),
  ),
};
const nativeSelectorDslnullable =
    "Container(color: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\",\\\"nullable\\\":true},\\\"inputs\\\":[0,1],\\\"value\\\":{\\\"binding\\\":\\\"_ha232d3a82e\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\",\\\"nullable\\\":true},\\\"implementation\\\":\\\"a232d3a82eab2122386e906b2d1e16f99161c0140ca578f11796a1712af5b84d\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":2,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true}},\\\"parameters\\\":{}}\", captures: {c0: data.context._ha36787c06c, c1: data.context._h5b7dbd5757 } })";
Map<String, r.NativeBinding<Object?>> nativeSelectorBindingsnullable({
  required bool flag,
  required Color color,
  required Color? maybeColor,
  required Color other,
}) => {
  "_h5b7dbd5757": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color?', nullable: true),
    value: maybeColor,
  ),
  "_ha232d3a82e": r.NativeBinding(
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
            "a232d3a82eab2122386e906b2d1e16f99161c0140ca578f11796a1712af5b84d",
      },
    }),
    value: nativeColor_ha232d3a82e(),
  ),
  "_ha36787c06c": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:core#bool', nullable: false),
    value: flag,
  ),
};
const nativeSelectorDslnullableCoalesce =
    "Container(color: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c2\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\",\\\"nullable\\\":true},\\\"inputs\\\":[0,1,2],\\\"value\\\":{\\\"binding\\\":\\\"_h2bd1735240\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\",\\\"nullable\\\":true},\\\"implementation\\\":\\\"2bd1735240b303fb246d5c3391260e13542096a09ba47dda630a5444c5603de5\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":3,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"c2\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._h5b7dbd5757, c1: data.context._ha36787c06c, c2: data.context._h1476dbc035 } })";
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
  "_h2bd1735240": r.NativeBinding(
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
            "2bd1735240b303fb246d5c3391260e13542096a09ba47dda630a5444c5603de5",
      },
    }),
    value: nativeColor_h2bd1735240(),
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
const nativeSelectorDslnested =
    "ColoredBox(color: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c2\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0,1,2],\\\"value\\\":{\\\"binding\\\":\\\"_h4c85ea5024\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"4c85ea50246dd8d8009b00e0c15ed9c44bb02e80432810de8690ca193e79e4e3\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":3,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"c2\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._ha36787c06c, c1: data.context._h5b7dbd5757, c2: data.context._h1476dbc035 } })";
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
  "_h4c85ea5024": r.NativeBinding(
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
            "4c85ea50246dd8d8009b00e0c15ed9c44bb02e80432810de8690ca193e79e4e3",
      },
    }),
    value: nativeColor_h4c85ea5024(),
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
const nativeSelectorDsllayout =
    "LayoutBuilder(builder: __RestageBuilderContinuation(version: 1, program: \"{\\\"version\\\":1,\\\"values\\\":{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"parameter\\\",\\\"type\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}},\\\"name\\\":\\\"arg1\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[1,2],\\\"value\\\":{\\\"binding\\\":\\\"_h71d09ad9ec\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"71d09ad9ec96f4c80217bbc7362d810205b7b3bf3ab713ca8f1b5304c0fcc7c4\\\"}},\\\"captures\\\":{}}},{\\\"op\\\":\\\"local.write\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[3],\\\"name\\\":\\\"n4\\\"}],\\\"root\\\":0,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{\\\"arg1\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"minWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxWidth\\\":{\\\"kind\\\":\\\"double\\\"},\\\"minHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"maxHeight\\\":{\\\"kind\\\":\\\"double\\\"},\\\"hasBoundedWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasBoundedHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightWidth\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"hasTightHeight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"isTight\\\":{\\\"kind\\\":\\\"bool\\\"},\\\"biggest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}},\\\"smallest\\\":{\\\"kind\\\":\\\"record\\\",\\\"fields\\\":{\\\"width\\\":{\\\"kind\\\":\\\"double\\\"},\\\"height\\\":{\\\"kind\\\":\\\"double\\\"}}}}}},\\\"locals\\\":{\\\"n4\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"}}},\\\"result\\\":{\\\"kind\\\":\\\"let\\\",\\\"node\\\":4,\\\"then\\\":{\\\"kind\\\":\\\"body\\\",\\\"body\\\":0,\\\"values\\\":{}}},\\\"bodyCount\\\":1,\\\"nullableResult\\\":false}\", captures: {c0: data.context._ha36787c06c, c1: data.context._h1476dbc035}, bodies: [(builder0) => ColoredBox(color: {kind: \"nativeLocal\", slot: \"n4\", type: \"flutter.Color\", nullable: false})]))";
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
  "_h71d09ad9ec": r.NativeBinding(
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
            "71d09ad9ec96f4c80217bbc7362d810205b7b3bf3ab713ca8f1b5304c0fcc7c4",
      },
    }),
    value: nativeColor_h71d09ad9ec(),
  ),
  "_ha36787c06c": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:core#bool', nullable: false),
    value: flag,
  ),
};
const nativeSelectorDslsvgTheme =
    "SvgPictureString(string: \"<svg xmlns=\\\"http://www.w3.org/2000/svg\\\" width=\\\"8\\\" height=\\\"8\\\"><path d=\\\"M0 0h8v8H0z\\\" fill=\\\"currentColor\\\"/></svg>\", theme: {currentColor: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0,1],\\\"value\\\":{\\\"binding\\\":\\\"_h7d6328f993\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"7d6328f993eae5a06b1d133387b531ccc148252c8408fcd6224b630c891c85fd\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":2,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._h5b7dbd5757, c1: data.context._h1476dbc035 } }})";
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
  "_h7d6328f993": r.NativeBinding(
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
            "7d6328f993eae5a06b1d133387b531ccc148252c8408fcd6224b630c891c85fd",
      },
    }),
    value: nativeColor_h7d6328f993(),
  ),
};
const nativeSelectorDslsvgFilter =
    "SvgPictureString(string: \"<svg xmlns=\\\"http://www.w3.org/2000/svg\\\" width=\\\"8\\\" height=\\\"8\\\"><path d=\\\"M0 0h8v8H0z\\\" fill=\\\"currentColor\\\"/></svg>\", colorFilter: {kind: \"mode\", color: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0,1],\\\"value\\\":{\\\"binding\\\":\\\"_h71d09ad9ec\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"71d09ad9ec96f4c80217bbc7362d810205b7b3bf3ab713ca8f1b5304c0fcc7c4\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":2,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._ha36787c06c, c1: data.context._h1476dbc035 } }, blendMode: \"srcIn\"})";
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
  "_h71d09ad9ec": r.NativeBinding(
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
            "71d09ad9ec96f4c80217bbc7362d810205b7b3bf3ab713ca8f1b5304c0fcc7c4",
      },
    }),
    value: nativeColor_h71d09ad9ec(),
  ),
  "_ha36787c06c": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:core#bool', nullable: false),
    value: flag,
  ),
};
const nativeSelectorDslsvgBoth =
    "SvgPictureString(string: \"<svg xmlns=\\\"http://www.w3.org/2000/svg\\\" width=\\\"8\\\" height=\\\"8\\\"><path d=\\\"M0 0h8v8H0z\\\" fill=\\\"currentColor\\\"/></svg>\", theme: {currentColor: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0,1],\\\"value\\\":{\\\"binding\\\":\\\"_h7d6328f993\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"7d6328f993eae5a06b1d133387b531ccc148252c8408fcd6224b630c891c85fd\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":2,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color?\\\",\\\"nullable\\\":true},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._h5b7dbd5757, c1: data.context._h1476dbc035 } }}, colorFilter: {kind: \"mode\", color: { version: 1, program: \"{\\\"version\\\":1,\\\"nodes\\\":[{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"name\\\":\\\"c0\\\"},{\\\"op\\\":\\\"capture\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"},\\\"name\\\":\\\"c1\\\"},{\\\"op\\\":\\\"native.call\\\",\\\"type\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"inputs\\\":[0,1],\\\"value\\\":{\\\"binding\\\":\\\"_h71d09ad9ec\\\",\\\"contract\\\":{\\\"type\\\":\\\"installed.call\\\",\\\"nullable\\\":false,\\\"call\\\":{\\\"inputs\\\":[{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}],\\\"captures\\\":{},\\\"result\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"flutter.Color\\\"},\\\"implementation\\\":\\\"71d09ad9ec96f4c80217bbc7362d810205b7b3bf3ab713ca8f1b5304c0fcc7c4\\\"}},\\\"captures\\\":{}}}],\\\"root\\\":2,\\\"captures\\\":{\\\"c0\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:core#bool\\\"},\\\"c1\\\":{\\\"kind\\\":\\\"native\\\",\\\"nativeType\\\":\\\"dart:ui#Color\\\"}},\\\"parameters\\\":{}}\", captures: {c0: data.context._ha36787c06c, c1: data.context._h1476dbc035 } }, blendMode: \"srcIn\"})";
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
  "_h5b7dbd5757": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:ui#Color?', nullable: true),
    value: maybeColor,
  ),
  "_h71d09ad9ec": r.NativeBinding(
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
            "71d09ad9ec96f4c80217bbc7362d810205b7b3bf3ab713ca8f1b5304c0fcc7c4",
      },
    }),
    value: nativeColor_h71d09ad9ec(),
  ),
  "_h7d6328f993": r.NativeBinding(
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
            "7d6328f993eae5a06b1d133387b531ccc148252c8408fcd6224b630c891c85fd",
      },
    }),
    value: nativeColor_h7d6328f993(),
  ),
  "_ha36787c06c": r.NativeBinding(
    contract: s.NativeBindingContract(type: 'dart:core#bool', nullable: false),
    value: flag,
  ),
};
