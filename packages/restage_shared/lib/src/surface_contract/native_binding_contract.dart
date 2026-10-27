import 'package:meta/meta.dart';
import 'package:restage_shared/src/expressions/value_program.dart';
import 'package:restage_shared/src/surface_contract/surface_contract_json.dart';

/// The installed signature consumed by no-argument event slots.
const kNativeVoidCallbackType = '()->void';

/// The installed type and nullability of one borrowed native binding.
@immutable
final class NativeBindingContract {
  /// Declares a type fixed by generated Dart, including callback signatures.
  const NativeBindingContract(
      {required this.type, this.nullable = false, this.call});

  /// A canonical type identifier; never a dynamically resolved class name.
  final String type;

  /// Whether the installed value may be null.
  final bool nullable;

  /// The installed callable signature, when this slot contains an adapter.
  final NativeCallContract? call;

  /// Decodes a strict contract declaration.
  factory NativeBindingContract.fromJson(Object? value) {
    final json = SurfaceContractJson.requireObject(value, 'native binding');
    SurfaceContractJson.exactKeys(
        json,
        {'type', 'nullable', if (json.containsKey('call')) 'call'},
        'native binding');
    final type =
        SurfaceContractJson.requiredString(json, 'type', 'native binding');
    final nullable = json['nullable'];
    if (type.isEmpty || nullable is! bool) {
      throw const FormatException('Invalid native binding contract.');
    }
    return NativeBindingContract(
        type: type,
        nullable: nullable,
        call: json.containsKey('call')
            ? NativeCallContract.fromJson(json['call'])
            : null);
  }

  /// The declaration included in the publication fingerprint.
  Map<String, Object?> toJson() => {
        'type': type,
        'nullable': nullable,
        if (call != null) 'call': call!.toJson()
      };

  /// The inert reference to this declaration's installed slot.
  Map<String, Object?> reference(String key) => {
        'kind': 'nativeBinding',
        'key': key,
        ...toJson(),
      };

  @override
  bool operator ==(Object other) =>
      other is NativeBindingContract &&
      type == other.type &&
      nullable == other.nullable &&
      call == other.call;

  @override
  int get hashCode => Object.hash(type, nullable, call);
}

/// A fixed installed call with typed operands and live lexical captures.
@immutable
final class NativeCallContract {
  const NativeCallContract(
      {required this.inputs,
      this.captures = const {},
      required this.result,
      required this.implementation});
  final List<ValueType> inputs;
  final Map<String, ValueType> captures;
  final ValueType result;
  final String implementation;

  factory NativeCallContract.fromJson(Object? value) {
    final json = SurfaceContractJson.requireObject(value, 'native call');
    SurfaceContractJson.exactKeys(json,
        {'inputs', 'captures', 'result', 'implementation'}, 'native call');
    final implementation = SurfaceContractJson.requiredString(
        json, 'implementation', 'native call');
    if (implementation.isEmpty)
      throw const FormatException('Missing native implementation identity');
    ValueType type(Object? value) => ValueType.fromJson(
        SurfaceContractJson.requireObject(value, 'native type'));
    return NativeCallContract(
        inputs: SurfaceContractJson.requireList(json['inputs'], 'inputs')
            .map(type)
            .toList(),
        captures:
            SurfaceContractJson.requireObject(json['captures'], 'captures')
                .map((key, value) => MapEntry(key, type(value))),
        result: type(json['result']),
        implementation: implementation);
  }
  Map<String, Object?> toJson() => {
        'inputs': inputs.map((type) => type.toJson()).toList(),
        'captures': {
          for (final key in captures.keys.toList()..sort())
            key: captures[key]!.toJson()
        },
        'result': result.toJson(),
        'implementation': implementation,
      };
  @override
  bool operator ==(Object other) =>
      other is NativeCallContract &&
      SurfaceContractJson.encode(toJson()) ==
          SurfaceContractJson.encode(other.toJson());
  @override
  int get hashCode => SurfaceContractJson.encode(toJson()).hashCode;
}
