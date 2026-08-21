import 'dart:io' as io;

/// Environment variable that opts a server in to experimental tools.
///
/// Set it to `1`, `true`, or `yes` (case-insensitive) to enable them.
const experimentalOptInVariable = 'RESTAGE_EXPERIMENTAL';

const _truthy = <String>{'1', 'true', 'yes'};

/// Whether experimental tools should be registered on this server.
///
/// A tool that is not registered does not appear in the tool list, which is
/// the only inventory an MCP client consults before calling. That is the
/// point: an experimental tool whose route is not served yet must not be
/// advertised as available.
///
/// [environment] defaults to the real process environment; tests pass their
/// own map so the opt-in can be exercised without mutating the process.
bool experimentalToolsEnabled([Map<String, String>? environment]) {
  final value =
      (environment ?? io.Platform.environment)[experimentalOptInVariable];
  return value != null && _truthy.contains(value.trim().toLowerCase());
}
