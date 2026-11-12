import 'package:flutter/foundation.dart';

/// Runs [body] with `debugPrint` captured and returns the `[restage]` lines;
/// `debugPrint` is restored before the test ends.
Future<List<String>> captureRestageLogs(Future<void> Function() body) async {
  final logs = <String>[];
  final original = debugPrint;
  debugPrint = (message, {wrapWidth}) {
    if (message != null && message.startsWith('[restage]')) logs.add(message);
  };
  try {
    await body();
  } finally {
    debugPrint = original;
  }
  return logs;
}
