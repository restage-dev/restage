import 'package:restage_shared/src/capability/capability_manifest.dart';
import 'package:restage_shared/src/capability/installed_capability.dart';

/// Whether an installed custom widget library can render content that
/// requires a given library version.
enum LibraryCompatibility {
  /// The installed library renders content built against the required version.
  satisfied,

  /// The library is not installed, or is installed without a version.
  missing,

  /// The installed library is older than the required version.
  tooOld,

  /// The installed library declared a breaking change after the required
  /// version, so content built against it no longer renders faithfully.
  contractBroken;

  /// Evaluates [required] against [installed], the library installed under the
  /// same namespace (or `null` when none is).
  static LibraryCompatibility evaluate(
    InstalledLibrary? installed,
    LibraryRequirement required,
  ) {
    if (installed != null && installed.namespace != required.namespace) {
      throw ArgumentError.value(
        installed.namespace,
        'installed',
        'must be the library named "${required.namespace}"',
      );
    }
    final version = installed?.version;
    if (installed == null || version == null) return missing;
    if (version < required.minVersion) return tooOld;
    if (required.minVersion < installed.effectiveCompatibleSince) {
      return contractBroken;
    }
    return satisfied;
  }

  /// Evaluates [required] against the matching library in [installed].
  static LibraryCompatibility evaluateIn(
    InstalledCapability installed,
    LibraryRequirement required,
  ) =>
      evaluate(installed.libraryOf(required.namespace), required);

  /// A short phrase naming what is installed, for a diagnostic after
  /// [evaluate] returned anything but [satisfied].
  static String describeInstalled(InstalledLibrary? installed) {
    if (installed == null) return 'not registered';
    final version = installed.version;
    if (version == null) return 'registered without a capability version';
    final since = installed.effectiveCompatibleSince;
    return since > 1
        ? 'installed v$version, compatible since v$since'
        : 'installed v$version';
  }
}
