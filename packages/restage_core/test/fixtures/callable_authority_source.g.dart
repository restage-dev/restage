part of 'callable_authority_source.dart';

r.NativeCallAdapter callableAuthorityAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{
                "kind": "native",
                "nativeType": "callback.context"
              }
            ],
            "captures": <String, Object?>{
              "_restageCapture0": <String, Object?>{
                "kind": "native",
                "nativeType": "callback.context"
              }
            },
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "callback.context"
            },
            "implementation":
                "05604fd75735fff3ce34fe89e416d215d3b726d4eca8e7a045ae3affe25b6620"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final void Function(f.BuildContext) _restageInput0 =
          _restageAs<void Function(f.BuildContext)>(
              (_restageInputs[0] as s.ValueNative).value);
      final _restageCapture0 = _restageCells["_restageCapture0"]!
          .cast<void Function(f.BuildContext)>();
      final void Function(f.BuildContext) _restageResult =
          (f.BuildContext context) {
        final alias = _restageCapture0.value;
        alias(context);
        _restageCapture0.value = _restageInput0;
      };
      return r.NativeBinding<void Function(f.BuildContext)>(
          contract: s.NativeBindingContract(
              type: "callback.context", nullable: false),
          value: _restageResult);
    });
const nullableCallableSlot = 'local1';
r.NativeCallAdapter nullableCallableAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[
              <String, Object?>{
                "kind": "native",
                "nativeType": "callback.acquire"
              },
              <String, Object?>{
                "kind": "native",
                "nativeType": "callback.context"
              }
            ],
            "captures": <String, Object?>{
              "_restageCapture0": <String, Object?>{
                "kind": "native",
                "nativeType": "callback.context",
                "nullable": true
              }
            },
            "result": <String, Object?>{
              "kind": "native",
              "nativeType": "callback.context"
            },
            "implementation":
                "59230bd7e7bab3bc4cd98e98239567a75f924221b772c05fcd7207a541e369ad"
          }
        }), (_restageInputs, _restageCells) {
      T _restageAs<T>(Object? value) => value as T;
      final bool Function() _restageInput0 = _restageAs<bool Function()>(
          (_restageInputs[0] as s.ValueNative).value);
      final void Function(f.BuildContext) _restageInput1 =
          _restageAs<void Function(f.BuildContext)>(
              (_restageInputs[1] as s.ValueNative).value);
      final _restageCapture0 = _restageCells["_restageCapture0"]!
          .cast<void Function(f.BuildContext)?>();
      final void Function(f.BuildContext) _restageResult =
          (f.BuildContext context) {
        _restageCapture0.value ??=
            _restageInput0() ? _restageInput1 : _restageInput1;
        _restageCapture0.value!(context);
      };
      return r.NativeBinding<void Function(f.BuildContext)>(
          contract: s.NativeBindingContract(
              type: "callback.context", nullable: false),
          value: _restageResult);
    });
r.NativeCallAdapter aliasedLookupAdapter() => r.NativeCallAdapter(
        s.NativeBindingContract.fromJson(<String, Object?>{
          "type": "installed.call",
          "nullable": false,
          "call": <String, Object?>{
            "inputs": <Object?>[],
            "captures": <String, Object?>{},
            "result": <String, Object?>{"kind": "String"},
            "implementation":
                "a5e68df1cc08cef764aa7b1f141c2046e2d796fc6d1a2c0750db96f86bbc085d"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = callableLookup('fallback',
          name: "fixed", desc: callableFailMetadata());
      return _restageResult;
    });
