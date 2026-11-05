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
                "99b9f2ec79e9ccfd3567a24aeb5702dde7ff37dcbff6ba0864f5b7a61cfa42fc"
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
                "e41f859bb6daa18d581cdc76b0a05aefe2ea483f6e9fa5e17261f8ef75ec7ba1"
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
                "3d74013fe4f5fea17bd31c13543e24731271b5bdc8c046a7e14e85aaeaabaa43"
          }
        }), (_restageInputs, _restageCells) {
      final String _restageResult = callableLookup('fallback',
          name: "fixed", desc: callableFailMetadata());
      return _restageResult;
    });
