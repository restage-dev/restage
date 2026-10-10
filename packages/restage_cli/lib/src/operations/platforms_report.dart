/// The platforms an app ships on, in row order.
const platformsReportOrder = <String>['ios', 'android', 'web'];

/// The share of a week's presentations served from a fallback at which a
/// cell calls it out.
const platformsFallbackNotice = 0.05;

const _platformNames = {'ios': 'iOS', 'android': 'Android', 'web': 'Web'};
const _identifierKeys = {
  'ios': 'iosBundleId',
  'android': 'androidPackage',
  'web': 'webDomain',
};

/// Reshapes the platforms read into one entry per platform, each naming every
/// environment: seen or not, when, on which build and SDK, and how much fell
/// back in the last seven days.
Map<String, Object?> platformsReport(
  Map<String, Object?> raw, {
  required String project,
  required String app,
}) {
  final environments = [
    for (final environment in raw['environments']! as List)
      (environment as Map).cast<String, Object?>(),
  ];
  final cells = [
    for (final cell in raw['cells']! as List)
      (cell as Map).cast<String, Object?>(),
  ];
  Map<String, Object?>? cellFor(int namedEnvironmentId, String platform) {
    for (final cell in cells) {
      if (cell['namedEnvironmentId'] == namedEnvironmentId &&
          cell['platform'] == platform) {
        return cell;
      }
    }
    return null;
  }

  var seen = 0;
  final platforms = <Map<String, Object?>>[];
  for (final platform in platformsReportOrder) {
    final rows = <Map<String, Object?>>[];
    for (final environment in environments) {
      final cell = cellFor(environment['namedEnvironmentId']! as int, platform);
      if (cell == null) {
        rows.add({
          'environment': environment['slug'],
          'environmentName': environment['displayName'],
          'seen': false,
        });
        continue;
      }
      seen++;
      final presentations = cell['recentPresentations']! as int;
      final fallbacks = cell['recentFallbacks']! as int;
      rows.add({
        'environment': environment['slug'],
        'environmentName': environment['displayName'],
        'seen': true,
        'lastSeenHourUtc': cell['lastSeenAt'],
        'appVersion': cell['appVersion'],
        'appBuild': cell['appBuild'],
        'sdkVersion': cell['sdkVersion'],
        'presentationsLast7Days': presentations,
        'fallbacksLast7Days': fallbacks,
        'fallbackShare': presentations == 0 ? null : fallbacks / presentations,
      });
    }
    platforms.add({
      'platform': platform,
      'identifier': raw[_identifierKeys[platform]],
      'environments': rows,
    });
  }
  return {
    'project': project,
    'app': app,
    'seen': seen,
    'cells': environments.length * platformsReportOrder.length,
    'platforms': platforms,
  };
}

/// When a receipt hour was: "This hour", "N hr ago" within a day, then its
/// date.
String platformsLastSeen(DateTime hourStart, {required DateTime now}) {
  final at = hourStart.toUtc();
  final current = now.toUtc();
  final hours = DateTime.utc(
    current.year,
    current.month,
    current.day,
    current.hour,
  ).difference(DateTime.utc(at.year, at.month, at.day, at.hour)).inHours;
  if (hours <= 0) return 'This hour';
  if (hours < 24) return '$hours hr ago';
  final local = hourStart.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

/// Writes [report] as one block per platform, one line per environment.
void writePlatformsReport(
  StringSink out,
  Map<String, Object?> report, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  out.writeln('${report['seen']} of ${report['cells']} seen');
  for (final platform in report['platforms']! as List) {
    final entry = (platform as Map).cast<String, Object?>();
    final name = _platformNames[entry['platform']]!;
    final identifier = entry['identifier'] as String?;
    out
      ..writeln()
      ..writeln(
        identifier == null || identifier.isEmpty ? name : '$name  $identifier',
      );
    for (final row in entry['environments']! as List) {
      final cell = (row as Map).cast<String, Object?>();
      final label = '  ${cell['environmentName']}:';
      if (cell['seen'] != true) {
        out.writeln('$label Not seen');
        continue;
      }
      final version = cell['appVersion'] as String?;
      final build = cell['appBuild'];
      final sdk = cell['sdkVersion'] as String?;
      final share = cell['fallbackShare'] as num?;
      final parts = [
        platformsLastSeen(
          DateTime.parse(cell['lastSeenHourUtc']! as String),
          now: at,
        ),
        if (version == null) '($build)' else '$version ($build)',
        if (sdk != null) 'SDK $sdk',
        if (share != null && share >= platformsFallbackNotice)
          '${(share * 100).round()}% fallbacks',
      ];
      out.writeln('$label ${parts.join(' · ')}');
    }
  }
}
