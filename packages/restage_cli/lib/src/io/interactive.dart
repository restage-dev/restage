import 'dart:async';
import 'dart:io';

/// Shared interactive surface for every command.
///
/// Commands depend on this rather than on `dart:io` `stdin` directly so a
/// single `--non-interactive` / `--yes` mode can suppress every prompt and
/// so unit tests can supply scripted input.
abstract class Interactive {
  /// Whether the surface accepts live input from a user. Commands consult
  /// this when they need to *decide* whether to prompt (e.g. "an
  /// environment was required but is missing — prompt or fail?").
  bool get isInteractive;

  /// Ask [question]. Returns the typed value, or [defaultValue] when the
  /// user presses enter on an empty line. When [defaultValue] is null and
  /// the user enters an empty line, implementations may re-prompt.
  Future<String> prompt(String question, {String? defaultValue});

  /// Ask a yes/no [question]. [defaultYes] controls the value returned on
  /// empty input.
  Future<bool> confirm(String question, {bool defaultYes = false});

  /// Ask the user to pick one of [options]. Returns the picked value, or
  /// [defaultValue] when the user presses enter on an empty line.
  Future<T> select<T>(
    String question,
    List<({String label, T value})> options, {
    T? defaultValue,
  });

  /// Ask for a sensitive value. Implementations attempt to suppress local
  /// echo when running against a TTY.
  Future<String> secret(String question);

  /// Build a [Spinner] bound to this surface. On non-TTY surfaces the
  /// spinner degrades to a single message line.
  Spinner spinner(String message);
}

/// A simple progress affordance.
///
/// On TTY surfaces, [start] kicks off a background timer that overwrites
/// the current line with a Braille frame + the current message; [update]
/// changes the message; [stop] cancels the timer and prints [finalMessage]
/// on its own line.
///
/// On non-TTY surfaces, [start] prints the initial message once, [update]
/// is a no-op, and [stop] prints [finalMessage] once.
abstract class Spinner {
  void start();
  void update(String message);
  void stop({String? finalMessage});
}

/// Thrown by [NonInteractive] when a prompt has no default value.
///
/// The caller catches this to print a `required: --foo <value>` message
/// and exit with a user-error code.
class NonInteractiveDefaultMissing implements Exception {
  /// Construct with the [question] that lacked a default. When the
  /// caller can map the prompt back to a flag, [flagName] lets the
  /// command print a precise `required: --<flagName> <value>` hint
  /// instead of a generic message.
  const NonInteractiveDefaultMissing(this.question, {this.flagName});

  /// The question text the caller passed.
  final String question;

  /// Long-form flag name (without leading dashes) the caller can hint
  /// at, or null when the prompt does not correspond to a single flag.
  final String? flagName;

  @override
  String toString() =>
      'No default value supplied for "$question" in non-interactive mode.';
}

/// Function signature for reading a single line of input. Returns null on
/// end-of-stream.
typedef ReadLine = Future<String?> Function();

/// Real interactive surface. Reads lines from an injected [ReadLine] and
/// writes prompts/spinner frames to an injected [StringSink].
///
/// Production code constructs this with the platform's stdin / stdout;
/// tests inject scripted callbacks.
class RealInteractive implements Interactive {
  /// Construct a real interactive surface.
  ///
  /// [readLine] reads one line from the user (returning null on EOF).
  /// [stdout] receives prompt text and spinner frames.
  /// [isInteractiveOverride] forces the [isInteractive] value (used by
  /// tests and by callers that want to detect TTY presence via a different
  /// mechanism than [stdin.hasTerminal]).
  /// [spinnerFrameInterval] sets the spinner refresh rate (defaults to
  /// 100 ms; set to `Duration.zero` in tests to force immediate frames).
  RealInteractive({
    required ReadLine readLine,
    required StringSink stdout,
    bool? isInteractiveOverride,
    Duration spinnerFrameInterval = const Duration(milliseconds: 100),
  }) : _readLine = readLine,
       _stdout = stdout,
       _isInteractive = isInteractiveOverride ?? (stdioHasTerminal()),
       _spinnerFrameInterval = spinnerFrameInterval;

  final ReadLine _readLine;
  final StringSink _stdout;
  final bool _isInteractive;
  final Duration _spinnerFrameInterval;

  @override
  bool get isInteractive => _isInteractive;

  @override
  Future<String> prompt(String question, {String? defaultValue}) async {
    while (true) {
      _stdout.write(_promptLine(question, defaultValue));
      final input = await _readLine() ?? '';
      final trimmed = input.trim();
      if (trimmed.isNotEmpty) return trimmed;
      if (defaultValue != null) return defaultValue;
      _stdout.writeln('(A value is required.)');
    }
  }

  @override
  Future<bool> confirm(String question, {bool defaultYes = false}) async {
    final hint = defaultYes ? '[Y/n]' : '[y/N]';
    while (true) {
      _stdout.write('$question $hint ');
      final input = (await _readLine() ?? '').trim().toLowerCase();
      if (input.isEmpty) return defaultYes;
      if (input == 'y' || input == 'yes') return true;
      if (input == 'n' || input == 'no') return false;
      _stdout.writeln('(Please answer yes or no.)');
    }
  }

  @override
  Future<T> select<T>(
    String question,
    List<({String label, T value})> options, {
    T? defaultValue,
  }) async {
    if (options.isEmpty) {
      throw ArgumentError.value(options, 'options', 'Must not be empty.');
    }
    while (true) {
      _stdout.writeln(question);
      for (var i = 0; i < options.length; i++) {
        final marker = defaultValue == options[i].value ? ' (default)' : '';
        _stdout.writeln('  ${i + 1}) ${options[i].label}$marker');
      }
      _stdout.write('Pick 1-${options.length}: ');
      final input = (await _readLine() ?? '').trim();
      if (input.isEmpty && defaultValue != null) return defaultValue;
      final parsed = int.tryParse(input);
      if (parsed != null && parsed >= 1 && parsed <= options.length) {
        return options[parsed - 1].value;
      }
      _stdout.writeln('(Pick a number between 1 and ${options.length}.)');
    }
  }

  @override
  Future<String> secret(String question) async {
    _stdout.write(question.endsWith(' ') ? question : '$question ');
    // Best-effort: mute stdin echo on real TTY surfaces. The injected
    // [_readLine] path always wins for testability.
    final priorEcho = _isInteractive ? _muteEcho() : null;
    try {
      final value = (await _readLine() ?? '').trim();
      return value;
    } finally {
      if (priorEcho != null) _restoreEcho(priorEcho);
      if (_isInteractive) _stdout.writeln();
    }
  }

  @override
  Spinner spinner(String message) => _RealSpinner(
    initialMessage: message,
    stdout: _stdout,
    interval: _spinnerFrameInterval,
    isInteractive: _isInteractive,
  );

  String _promptLine(String question, String? defaultValue) {
    if (defaultValue == null) return '$question ';
    return '$question [$defaultValue] ';
  }
}

class _RealSpinner implements Spinner {
  _RealSpinner({
    required String initialMessage,
    required StringSink stdout,
    required Duration interval,
    required bool isInteractive,
  }) : _message = initialMessage,
       _stdout = stdout,
       _interval = interval,
       _isInteractive = isInteractive;

  // U+2800-range Braille frames; visually unambiguous on monospaced fonts.
  static const _frames = <String>[
    '⠋',
    '⠙',
    '⠹',
    '⠸',
    '⠼',
    '⠴',
    '⠦',
    '⠧',
    '⠇',
    '⠏',
  ];

  final StringSink _stdout;
  final Duration _interval;
  final bool _isInteractive;
  String _message;
  Timer? _timer;
  int _frameIndex = 0;
  bool _started = false;

  @override
  void start() {
    if (_started) return;
    _started = true;
    if (!_isInteractive) {
      _stdout.writeln(_message);
      return;
    }
    _renderFrame();
    _timer = Timer.periodic(_interval, (_) => _renderFrame());
  }

  @override
  void update(String message) {
    _message = message;
    if (!_isInteractive) return;
    if (!_started) return;
    _renderFrame();
  }

  @override
  void stop({String? finalMessage}) {
    _timer?.cancel();
    _timer = null;
    if (_isInteractive && _started) {
      // Clear the spinner line.
      _stdout.write('\r\x1b[2K');
    }
    if (finalMessage != null) _stdout.writeln(finalMessage);
  }

  void _renderFrame() {
    final frame = _frames[_frameIndex % _frames.length];
    _frameIndex++;
    // Carriage return rewinds to the line start so the next frame
    // overwrites this one in-place.
    _stdout.write('\r$frame $_message');
  }
}

/// Non-interactive surface used when the user passes `--non-interactive`
/// (or when stdin is not a TTY in a context where prompting would block).
///
/// Every method returns the supplied default; prompts without a default
/// throw [NonInteractiveDefaultMissing] so the command surfaces a clear
/// `required: --<flag> <value>` message instead of hanging.
class NonInteractive implements Interactive {
  /// Construct a non-interactive surface. [stdout] is consumed only by
  /// the [Spinner] this surface produces — every other method ignores
  /// it.
  const NonInteractive({this.stdout});

  /// Optional sink for the spinner's status lines.
  final StringSink? stdout;

  @override
  bool get isInteractive => false;

  @override
  Future<String> prompt(String question, {String? defaultValue}) async {
    if (defaultValue != null) return defaultValue;
    throw NonInteractiveDefaultMissing(question);
  }

  @override
  Future<bool> confirm(String question, {bool defaultYes = false}) async =>
      defaultYes;

  @override
  Future<T> select<T>(
    String question,
    List<({String label, T value})> options, {
    T? defaultValue,
  }) async {
    if (defaultValue != null) return defaultValue;
    throw NonInteractiveDefaultMissing(question);
  }

  @override
  Future<String> secret(String question) async {
    throw NonInteractiveDefaultMissing(question);
  }

  @override
  Spinner spinner(String message) =>
      _NonInteractiveSpinner(message: message, stdout: stdout);
}

class _NonInteractiveSpinner implements Spinner {
  _NonInteractiveSpinner({required String message, StringSink? stdout})
    : _message = message,
      _stdout = stdout;

  String _message;
  final StringSink? _stdout;

  @override
  void start() => _stdout?.writeln(_message);

  @override
  void update(String message) {
    _message = message;
  }

  @override
  void stop({String? finalMessage}) {
    if (finalMessage != null) _stdout?.writeln(finalMessage);
  }
}

// ---------------------------------------------------------------------------
// Platform-detection + echo helpers. Isolated so unit tests can ignore the
// terminal entirely and so each helper can be swapped out for testing.
// ---------------------------------------------------------------------------

/// True when both `stdin` and `stdout` are attached to a terminal.
///
/// Wrapped in a top-level function so [RealInteractive] callers can detect
/// TTY presence the same way regardless of platform; tests bypass the
/// check via the `isInteractiveOverride` constructor parameter.
bool stdioHasTerminal() => stdin.hasTerminal && stdout.hasTerminal;

bool? _muteEcho() {
  try {
    final prior = stdin.echoMode;
    stdin.echoMode = false;
    return prior;
  } on StdinException {
    return null;
  }
}

void _restoreEcho(bool prior) {
  try {
    stdin.echoMode = prior;
  } on StdinException {
    // Best-effort — already muted/unmuted by something else. Ignored.
  }
}
