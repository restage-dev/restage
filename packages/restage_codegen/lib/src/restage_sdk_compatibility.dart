import 'package:build/build.dart';
import 'package:package_config/package_config.dart';
import 'package:pub_semver/pub_semver.dart';

/// The oldest `restage` release whose API generated code compiles against.
final Version kMinimumRestageVersion = Version(2, 1, 0);

/// The oldest `restage_core` release with the decoders generated factories
/// call, such as `RestageDecoders.string`.
final Version kMinimumRestageCoreVersion = Version(2, 1, 0);

/// Why a runtime package [buildStep] resolves cannot run generated code, or
/// null when every one can or its version is unknown.
Future<String?> restageSdkIncompatibility(BuildStep buildStep) async {
  final config = await buildStep.packageConfig;
  return restageVersionIncompatibility(config['restage']) ??
      restageVersionIncompatibility(
        config['restage_core'],
        minimum: kMinimumRestageCoreVersion,
      );
}

/// The check [restageSdkIncompatibility] runs on one resolved [package],
/// against [minimum] (the `restage` minimum when omitted).
///
/// Only a pub-hosted package is checked; a path, workspace or git
/// dependency builds against the source it points at.
String? restageVersionIncompatibility(Package? package, {Version? minimum}) {
  if (package == null) return null;
  final required = minimum ?? kMinimumRestageVersion;
  final name = package.name;
  final segments = [
    for (final segment in package.root.pathSegments)
      if (segment.isNotEmpty) segment,
  ];
  if (!segments.contains('hosted')) return null;
  final directory = segments.last;
  if (!directory.startsWith('$name-')) return null;
  final Version version;
  try {
    version = Version.parse(directory.substring('$name-'.length));
  } on FormatException {
    return null;
  }
  if (version >= required) return null;
  return 'This version of restage_codegen generates code for $name '
      '$required or newer, and this package resolves $name $version. '
      'Upgrade it: dart pub upgrade $name (raise the constraint to '
      '^$required if pub keeps $version).';
}
