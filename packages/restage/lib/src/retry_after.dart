Duration retryAfterDelay(String? value) {
  final text = value?.trim() ?? '';
  if (!RegExp(r'^[0-9]+$').hasMatch(text)) {
    return const Duration(seconds: 1);
  }
  final seconds = BigInt.parse(text);
  if (seconds <= BigInt.zero) return const Duration(seconds: 1);
  return Duration(seconds: seconds > BigInt.from(60) ? 60 : seconds.toInt());
}

/// The wait a `Retry-After` header names in whole seconds, uncapped; null
/// for a date, a malformed value or no wait.
Duration? requestedRetryAfter(String? value) {
  final text = value?.trim() ?? '';
  if (!RegExp(r'^[0-9]{1,9}$').hasMatch(text)) return null;
  final seconds = int.parse(text);
  return seconds == 0 ? null : Duration(seconds: seconds);
}
