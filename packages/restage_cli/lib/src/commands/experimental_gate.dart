import 'dart:io' as io;

/// Environment variable that opts a session in to experimental commands.
///
/// Set it to `1`, `true`, or `yes` (case-insensitive) to enable them.
const experimentalOptInVariable = 'RESTAGE_EXPERIMENTAL';

const _truthy = <String>{'1', 'true', 'yes'};

/// Whether experimental commands are enabled for this process.
///
/// [environment] defaults to the real process environment; tests pass their
/// own map so the opt-in can be exercised without mutating the process.
bool experimentalCommandsEnabled([Map<String, String>? environment]) {
  final value =
      (environment ?? io.Platform.environment)[experimentalOptInVariable];
  return value != null && _truthy.contains(value.trim().toLowerCase());
}

/// The refusal shown when an experimental command runs without the opt-in.
///
/// It names the reason rather than pretending the command is unknown: the
/// command exists and works, but the endpoint it calls is not served yet, so a
/// user who reaches it deserves to know that rather than to debug a failure.
String experimentalCommandRefusal(String commandName) =>
    '`$commandName` is experimental and is not served by production yet.\n'
    'Set $experimentalOptInVariable=1 to run it anyway. Expect calls to fail '
    'against an endpoint that does not exist, and expect its interface to '
    'change without a deprecation.';
