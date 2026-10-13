/// What a push should say when its surfaces use app widgets the dashboard's
/// build of [app] for [environment] cannot draw; null when it covers them.
String? renderBundleCoverageSentence({
  required Map<String, int> required,
  required int? headVersion,
  required Map<String, int> registered,
  required int surfaceCount,
  required String app,
  required String environment,
}) {
  if (required.isEmpty) return null;
  final names = (required.keys.toList()..sort()).join(', ');
  final subject = surfaceCount == 1
      ? 'This surface uses widgets from your app ($names)'
      : 'These surfaces use widgets from your app ($names)';
  const command = 'run `restage build push --env';
  if (headVersion == null) {
    return '$subject. The dashboard has no build of $app for $environment '
        'yet, so it cannot display them; $command $environment`.';
  }
  final absent =
      required.keys
          .where((namespace) => !registered.containsKey(namespace))
          .toList()
        ..sort();
  final older =
      required.entries
          .where((entry) {
            final held = registered[entry.key];
            return held != null && held < entry.value;
          })
          .map((entry) => entry.key)
          .toList()
        ..sort();
  if (absent.isEmpty && older.isEmpty) return null;
  final build =
      "the dashboard's build of $app for $environment (version $headVersion)";
  if (absent.isNotEmpty) {
    return '$subject, and $build does not include ${absent.join(', ')}; '
        '$command $environment`.';
  }
  return '$subject, and $build is older than they need; '
      '$command $environment`.';
}
