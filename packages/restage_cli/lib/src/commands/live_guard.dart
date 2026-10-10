import 'package:args/command_runner.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/io/interactive.dart';

/// A command that asks before it changes what a live target serves.
abstract interface class LiveGuardedCommand {}

/// Consent to change what a live target serves.
///
/// Sandbox targets proceed. On the live plane the global `--yes` is consent;
/// otherwise the operator confirms interactively, and a non-interactive run
/// is refused.
Future<bool> confirmLiveChange({
  required Command<int> command,
  required Interactive interactive,
  required StringSink stdout,
  required StringSink stderr,
  required String impactLine,
  RuntimePlane? runtimePlane,
  bool? live,
}) async {
  if (!(live ?? runtimePlane == RuntimePlane.live)) return true;
  final globals = command.globalResults;
  if (globals != null &&
      globals.options.contains('yes') &&
      globals['yes'] as bool) {
    return true;
  }
  if (!interactive.isInteractive) {
    stderr.writeln(
      'This changes what the live plane serves. Run interactively, or pass '
      '--yes.',
    );
    return false;
  }
  stdout.writeln(impactLine);
  final confirmed = await interactive.confirm('Proceed?');
  if (!confirmed) stdout.writeln('Aborted.');
  return confirmed;
}
