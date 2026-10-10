/// The Restage command-line interface.
///
/// Library entry for consumers that embed the CLI runner — most users will
/// invoke the `restage` binary directly rather than depend on this package.
library;

export 'src/cli.dart';
export 'src/commands/live_guard.dart' show LiveGuardedCommand;
export 'src/io/interactive.dart' show Interactive, NonInteractive;
