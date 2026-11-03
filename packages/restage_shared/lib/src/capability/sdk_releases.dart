/// Assignment API levels the SDK has shipped, oldest first, with the release
/// that introduced each.
const List<({int level, String label})> sdkReleases = <({
  int level,
  String label,
})>[
  (level: 3, label: '3.0'),
  (level: 4, label: '3.0'),
];

/// One entry per release, with the lowest level it reports.
List<({int level, String label})> get sdkReleasesByLabel {
  final seen = <String>{};
  return [
    for (final release in sdkReleases)
      if (seen.add(release.label)) release,
  ];
}

/// The newest level any SDK release reports.
int get newestSdkLevel => sdkReleases.last.level;

/// [level] as its release, or the level itself when no release names it.
String sdkReleaseLabel(int level) {
  for (final release in sdkReleases) {
    if (release.level == level) return release.label;
  }
  return 'level $level';
}

/// What an audience needing at least [level] asks of the app: the first
/// release that reports it.
String restageReleaseRequirement(int level) {
  for (final release in sdkReleases) {
    if (release.level >= level) return 'restage ${release.label} or later';
  }
  return 'a newer Restage SDK release';
}

/// A platform as people name it.
String sdkPlatformName(String platform) => switch (platform) {
      'ios' => 'iOS',
      'android' => 'Android',
      _ => platform,
    };
