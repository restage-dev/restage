/// Selected rendering style for command output.
///
/// The CLI emits two kinds of output: short [OutputFormatter.status] lines
/// (progress, single-line confirmations) and structured [OutputFormatter.data]
/// payloads (objects, lists, primitives returned by data-bearing commands).
/// Each format renders both differently:
///
/// - [OutputFormat.human]   — readable for terminals (default).
/// - [OutputFormat.json]    — single JSON value; suitable for piping.
/// - [OutputFormat.table]   — column-aligned ASCII table.
/// - [OutputFormat.quiet]   — suppress status lines; preserve data payloads.
///
/// The shape lets data-bearing commands take an [OutputFormatter] without
/// caring which format the user requested.
enum OutputFormat { human, json, table, quiet }

/// A render target shared by every command. Concrete implementations
/// translate calls into the [OutputFormat] the user selected.
abstract class OutputFormatter {
  /// Print a short progress / confirmation line. May be a no-op (e.g. in
  /// `quiet` mode or when [OutputFormat.json] would taint a pipeline).
  void status(String message);

  /// Render a structured payload — a `Map`, `List`, string, number, bool,
  /// or `null`. Each format chooses its own representation.
  void data(Object? payload);
}

/// Human-readable output: status lines are written verbatim; payloads are
/// rendered via [Object.toString]. This is the default for interactive
/// terminal sessions.
class HumanOutputFormatter implements OutputFormatter {
  /// Build a formatter that writes to [_sink].
  HumanOutputFormatter(this._sink);

  final StringSink _sink;

  @override
  void status(String message) => _sink.writeln(message);

  @override
  void data(Object? payload) {
    if (payload == null) return;
    _sink.writeln(payload.toString());
  }
}
