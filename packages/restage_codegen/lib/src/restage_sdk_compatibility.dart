import 'package:build/build.dart';
import 'package:package_config/package_config.dart';
import 'package:pub_semver/pub_semver.dart';

/// The oldest `restage` release whose API generated code compiles against.
final Version kMinimumRestageVersion = Version(2, 1, 0);

/// Why the `restage` package [buildStep] resolves cannot run generated code,
/// or null when it can or its version is unknown.
Future<String?> restageSdkIncompatibility(BuildStep buildStep) async =>
    restageVersionIncompatibility((await buildStep.packageConfig)['restage']);

/// The check [restageSdkIncompatibility] runs on a resolved [restage].
///
/// Only a pub-hosted `restage` is checked; a path, workspace or git
/// dependency builds against the source it points at.
String? restageVersionIncompatibility(Package? restage) {
  if (restage == null) return null;
  final segments = [
    for (final segment in restage.root.pathSegments)
      if (segment.isNotEmpty) segment,
  ];
  if (!segments.contains('hosted')) return null;
  final directory = segments.last;
  if (!directory.startsWith('restage-')) return null;
  final Version version;
  try {
    version = Version.parse(directory.substring('restage-'.length));
  } on FormatException {
    return null;
  }
  if (version >= kMinimumRestageVersion) return null;
  return 'This version of restage_codegen generates code for restage '
      '$kMinimumRestageVersion or newer, and this package resolves restage '
      '$version. Upgrade it: dart pub upgrade restage (raise the constraint '
      'to ^$kMinimumRestageVersion if pub keeps $version).';
}
