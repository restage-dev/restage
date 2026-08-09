import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/rfw.dart';

/// Decoded state of one Restage RFW constructor-presence envelope.
@immutable
final class RestageRfwConstructorPresence {
  const RestageRfwConstructorPresence._({
    required this.supplied,
    required this.hasValue,
    required this.valuePath,
  });

  /// Decodes the target-local, versioned constructor-presence convention.
  ///
  /// An absent outer map means the Dart argument was omitted. A present map
  /// must carry the reserved protocol marker; its nested value may itself be
  /// absent, which deliberately represents a supplied null.
  static RestageRfwConstructorPresence read(
    DataSource source,
    List<Object> outerPath,
  ) {
    final outerKind = _valueKind(source, outerPath);
    if (outerKind != _RfwValueKind.map) {
      if (outerKind != _RfwValueKind.absent) {
        throw ArgumentError.value(
          outerPath,
          'outerPath',
          'Restage constructor-presence value must be a protocol envelope.',
        );
      }
      return RestageRfwConstructorPresence._(
        supplied: false,
        hasValue: false,
        valuePath: List<Object>.unmodifiable(outerPath),
      );
    }

    final markerPath = <Object>[
      ...outerPath,
      RfwConstructorPresenceProtocol.markerKey,
    ];
    final version = source.v<int>(markerPath);
    if (version != RfwConstructorPresenceProtocol.version) {
      throw ArgumentError.value(
        version,
        'protocolVersion',
        'Unrecognized Restage constructor-presence envelope.',
      );
    }
    final valuePath = List<Object>.unmodifiable(<Object>[
      ...outerPath,
      RfwConstructorPresenceProtocol.valueKey,
    ]);
    return RestageRfwConstructorPresence._(
      supplied: true,
      hasValue: _valueKind(source, valuePath) != _RfwValueKind.absent,
      valuePath: valuePath,
    );
  }

  /// Whether the generated factory must pass the constructor argument.
  final bool supplied;

  /// Whether the supplied envelope contains an evaluated nested value.
  ///
  /// An explicit null and a missing reference both leave this false.
  final bool hasValue;

  /// Path of the nested supplied value, which may evaluate to null.
  final List<Object> valuePath;
}

enum _RfwValueKind { absent, scalar, list, map }

_RfwValueKind _valueKind(DataSource source, List<Object> path) {
  if (source.isMap(path)) return _RfwValueKind.map;
  if (source.isList(path)) return _RfwValueKind.list;
  if (source.v<bool>(path) != null ||
      source.v<int>(path) != null ||
      source.v<double>(path) != null ||
      source.v<String>(path) != null) {
    return _RfwValueKind.scalar;
  }
  return _RfwValueKind.absent;
}
