import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/measurement_wire.dart';

/// Injected authority transport for one exact activation command byte sequence.
@experimental
typedef ExperimentActivationByteTransport =
    Future<List<int>> Function(List<int> canonicalCommandBytes);

/// Reusable strict API boundary for experiment activation.
///
/// An authenticated embedding host supplies the authority transport. This
/// client has no endpoint fallback and does not manufacture server-owned
/// activation proof, materialization, lifecycle, or receipt values.
@experimental
final class ExperimentActivationApi {
  /// Creates an API boundary over one injected authority transport.
  const ExperimentActivationApi({
    required ExperimentActivationByteTransport transport,
  }) : _transport = transport;

  final ExperimentActivationByteTransport _transport;

  /// Strictly forwards one complete read activation command.
  Future<ExperimentActivationResultWireV1> execute(
    ExperimentActivationCommandWireV1 command,
  ) => executeCanonicalBytes(command.canonicalBytes);

  /// Strictly forwards exact canonical activation command bytes.
  Future<ExperimentActivationResultWireV1> executeCanonicalBytes(
    List<int> canonicalCommandBytes,
  ) async {
    final command = ExperimentActivationCommandWireV1.fromCanonicalBytes(
      canonicalCommandBytes,
    );
    final resultBytes = await _transport(command.canonicalBytes);
    return ExperimentActivationResultWireV1.fromCanonicalBytes(resultBytes);
  }
}
