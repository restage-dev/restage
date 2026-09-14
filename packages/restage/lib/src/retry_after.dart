Duration retryAfterDelay(String? value) {
  final text = value?.trim() ?? '';
  if (!RegExp(r'^[0-9]+$').hasMatch(text)) {
    return const Duration(seconds: 1);
  }
  final seconds = BigInt.parse(text);
  if (seconds <= BigInt.zero) return const Duration(seconds: 1);
  return Duration(seconds: seconds > BigInt.from(60) ? 60 : seconds.toInt());
}
