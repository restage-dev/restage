import 'package:restage_cli/src/api/selector_syntax.dart';

/// What a push should say when its surfaces use app widgets the dashboard's
/// build of [app] for [environment] cannot draw; null when it covers them.
/// [ownBuildCovers] says whether the user's own build draws them.
String? renderBundleCoverageSentence({
  required Map<String, int> required,
  required int? headVersion,
  required Map<String, int> registered,
  required int surfaceCount,
  required String app,
  required String environment,
  bool ownBuildCovers = false,
}) {
  if (required.isEmpty) return null;
  final names = (required.keys.toList()..sort()).join(', ');
  final subject = surfaceCount == 1
      ? 'This surface uses widgets from your app ($names)'
      : 'These surfaces use widgets from your app ($names)';
  final String problem;
  if (headVersion == null) {
    problem =
        '$subject. The dashboard has no build of $app for $environment '
        'yet';
  } else {
    final absent =
        required.keys
            .where((namespace) => !registered.containsKey(namespace))
            .toList()
          ..sort();
    final older = required.entries.any((entry) {
      final held = registered[entry.key];
      return held != null && held < entry.value;
    });
    if (absent.isEmpty && !older) return null;
    final build =
        "the dashboard's build of $app for $environment (version $headVersion)";
    problem = absent.isNotEmpty
        ? '$subject, and $build does not include ${absent.join(', ')}'
        : '$subject, and $build is older than they need';
  }
  final syntax = currentSelectorSyntax;
  final ownPush = syntax.command(
    const FollowUp('build push', 'restage_push_build'),
  );
  final everyonePush = syntax.command(
    FollowUp('build push', 'restage_push_build', [
      FollowUpArg('environmentSlug', environment, flag: 'env'),
    ]),
  );
  final everyone = '$everyonePush updates what everyone sees';
  const devices =
      'This affects dashboard previews only: devices draw these widgets '
      'from the app installed on them.';
  return ownBuildCovers
      ? '$problem. Your own build covers them, so they show in your dashboard '
            'preview; $everyone. $devices'
      : '$problem. ${syntax.run} $ownPush to see them in your own dashboard '
            'preview; $everyone. $devices';
}
