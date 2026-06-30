// Complete a pub.dev trusted-publishing release.
//
// The publish workflow uploads one package per tag. This closeout step groups
// the package tags that point at the same commit, verifies pub.dev has the
// published versions, creates/updates one GitHub Release, and records a
// successful GitHub Deployment for the `pub.dev` environment.
//
// Usage:
//   dart run tool/publish_closeout.dart --sha <commit> --repo <owner/repo>

import 'dart:convert';
import 'dart:io';

const publishablePackages = <String>{
  'restage',
  'restage_core',
  'restage_material',
  'restage_cupertino',
  'rfw_catalog_schema',
  'restage_shared',
  'restage_codegen',
  'rfw_catalog_compiler',
  'restage_a2ui',
};

const _headlinePriority = <String>[
  'restage',
  'restage_codegen',
  'rfw_catalog_compiler',
  'restage_a2ui',
  'restage_shared',
  'rfw_catalog_schema',
  'restage_material',
  'restage_cupertino',
  'restage_core',
];

final _tagPattern = RegExp(
  r'^([A-Za-z_][A-Za-z0-9_]*)-v([0-9][0-9A-Za-z.+-]*)$',
);

void main(List<String> args) async {
  try {
    await _run(args);
  } on UsageException catch (error) {
    stderr.writeln('publish_closeout: ${error.message}');
    exitCode = 64;
  } on CloseoutException catch (error) {
    stderr.writeln('publish_closeout: ${error.message}');
    exitCode = 1;
  }
}

Future<void> _run(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    stdout.writeln(_usage);
    return;
  }

  final root = Directory(options.root);
  if (!root.existsSync()) {
    throw UsageException('root does not exist: ${options.root}');
  }

  final repo = options.repo ?? Platform.environment['GITHUB_REPOSITORY'];
  if (repo == null || repo.isEmpty) {
    throw UsageException('--repo is required outside GitHub Actions');
  }
  final sha = options.sha ?? Platform.environment['GITHUB_SHA'];
  if (sha == null || sha.isEmpty) {
    throw UsageException('--sha is required');
  }

  final tagNames = await _gitTagsPointingAt(root.path, sha);
  final pubspecVersions = _readPubspecVersions(root.path);
  final preliminary = planRelease(
    tagNames: tagNames,
    pubspecVersions: pubspecVersions,
    changelogs: const {},
  );
  final changelogs = _readChangelogs(root.path, preliminary.packages);
  final curatedNotes = _readCuratedNotes(root.path, preliminary.packages);
  final plan = planRelease(
    tagNames: tagNames,
    pubspecVersions: pubspecVersions,
    changelogs: changelogs,
    curatedNotes: curatedNotes,
  );

  await _waitForPubDev(plan.packages, options.pubDevWaitSeconds);

  if (options.dryRun) {
    stdout
      ..writeln('DRY RUN: would close out ${plan.headlineTag}')
      ..writeln(plan.title)
      ..writeln(plan.body);
    return;
  }

  final notesFile = await _writeTempNotes(plan.body);
  try {
    await _upsertRelease(
      repo: repo,
      sha: sha,
      plan: plan,
      notesFile: notesFile,
    );
    await _recordSuccessfulDeployment(
      repo: repo,
      sha: sha,
      plan: plan,
      runUrl: options.runUrl,
    );
  } finally {
    try {
      notesFile.deleteSync();
    } on FileSystemException {
      // Best-effort temp cleanup only.
    }
  }

  stdout.writeln('publish_closeout: closed out ${plan.headlineTag}');
}

ReleasePlan planRelease({
  required Iterable<String> tagNames,
  required Map<String, String> pubspecVersions,
  required Map<String, String> changelogs,
  Map<String, String> curatedNotes = const {},
}) {
  final packagesByName = <String, ReleasePackage>{};
  for (final tagName in tagNames) {
    final parsed = _parsePackageTag(tagName);
    if (parsed == null) continue;
    final expectedVersion = pubspecVersions[parsed.name];
    if (expectedVersion == null) {
      throw CloseoutException('missing pubspec version for ${parsed.name}');
    }
    if (expectedVersion != parsed.version) {
      throw CloseoutException(
        '${parsed.tag}: tag version ${parsed.version} does not match '
        'pubspec version $expectedVersion',
      );
    }
    packagesByName[parsed.name] = parsed;
  }
  if (packagesByName.isEmpty) {
    throw CloseoutException('no publishable package tags point at this commit');
  }

  final allPackages = _sortPackages(packagesByName.values.toList());
  final matchingCurated = curatedNotes.entries
      .where(
        (entry) => packagesByName.values.any((pkg) => pkg.tag == entry.key),
      )
      .toList();
  if (matchingCurated.length > 1) {
    throw CloseoutException(
      'multiple curated release notes match this commit: '
      '${matchingCurated.map((entry) => entry.key).join(', ')}',
    );
  }

  if (matchingCurated.isNotEmpty) {
    final noteTag = matchingCurated.single.key;
    final note = CuratedReleaseNotes.parse(matchingCurated.single.value);
    final headlineTag = note.headlineTag ?? noteTag;
    if (!packagesByName.values.any((pkg) => pkg.tag == headlineTag)) {
      throw CloseoutException(
        'curated headline tag is not in this release batch: $headlineTag',
      );
    }
    final packageNames = note.packageNames.isEmpty
        ? allPackages.map((pkg) => pkg.name).toList()
        : note.packageNames;
    final packages = <ReleasePackage>[];
    for (final name in packageNames) {
      final pkg = packagesByName[name];
      if (pkg == null) {
        throw CloseoutException(
          'curated package is not tagged at this commit: $name',
        );
      }
      packages.add(pkg);
    }
    return ReleasePlan(
      headlineTag: headlineTag,
      title: note.title ?? _defaultTitle(packages),
      body: note.body.trimRight(),
      packages: packages,
      updateExistingRelease: true,
    );
  }

  return ReleasePlan(
    headlineTag: allPackages.first.tag,
    title: _defaultTitle(allPackages),
    body: _generatedBody(allPackages, changelogs),
    packages: allPackages,
    updateExistingRelease: false,
  );
}

ReleasePackage? _parsePackageTag(String tagName) {
  final match = _tagPattern.firstMatch(tagName);
  if (match == null) return null;
  final name = match.group(1)!;
  if (!publishablePackages.contains(name)) return null;
  return ReleasePackage(name: name, version: match.group(2)!, tag: tagName);
}

List<ReleasePackage> _sortPackages(List<ReleasePackage> packages) {
  int priority(ReleasePackage package) {
    final index = _headlinePriority.indexOf(package.name);
    return index == -1 ? 1000 : index;
  }

  packages.sort((a, b) {
    final byPriority = priority(a).compareTo(priority(b));
    if (byPriority != 0) return byPriority;
    return a.name.compareTo(b.name);
  });
  return packages;
}

String _defaultTitle(List<ReleasePackage> packages) {
  if (packages.length == 1) {
    final pkg = packages.single;
    return '${pkg.name} ${pkg.version}';
  }
  final headline = packages.first;
  return '${headline.name} ${headline.version} release';
}

String _generatedBody(
  List<ReleasePackage> packages,
  Map<String, String> changelogs,
) {
  final out = StringBuffer()
    ..writeln('Coordinated package release.')
    ..writeln()
    ..writeln('| Package | Version |')
    ..writeln('|---|---|');
  for (final package in packages) {
    out.writeln('| `${package.name}` | ${package.version} |');
  }
  for (final package in packages) {
    out
      ..writeln()
      ..writeln('### `${package.name}` ${package.version}')
      ..writeln()
      ..writeln(
        _extractChangelogEntry(
          changelogs[package.name] ?? '',
          package.version,
        ),
      );
  }
  out
    ..writeln()
    ..writeln('Published via the pub.dev trusted-publisher workflow.');
  return out.toString().trimRight();
}

String _extractChangelogEntry(String changelog, String version) {
  final lines = changelog.split('\n');
  final heading = RegExp('^##+\\s+${RegExp.escape(version)}(?:\\s|\$)');
  var start = -1;
  for (var i = 0; i < lines.length; i++) {
    if (heading.hasMatch(lines[i].trimRight())) {
      start = i + 1;
      break;
    }
  }
  if (start == -1) return '- Published to pub.dev.';

  final body = <String>[];
  for (var i = start; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('## ')) break;
    body.add(line);
  }
  final text = body.join('\n').trim();
  return text.isEmpty ? '- Published to pub.dev.' : text;
}

Map<String, String> _readPubspecVersions(String root) {
  final versions = <String, String>{};
  for (final package in publishablePackages) {
    final pubspec = File('$root/packages/$package/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    for (final line in pubspec.readAsLinesSync()) {
      final match = RegExp(r'^version:\s+(\S+)\s*$').firstMatch(line);
      if (match != null) {
        versions[package] = match.group(1)!;
        break;
      }
    }
  }
  return versions;
}

Map<String, String> _readChangelogs(
  String root,
  List<ReleasePackage> packages,
) {
  final changelogs = <String, String>{};
  for (final package in packages) {
    final file = File('$root/packages/${package.name}/CHANGELOG.md');
    if (file.existsSync()) {
      changelogs[package.name] = file.readAsStringSync();
    }
  }
  return changelogs;
}

Map<String, String> _readCuratedNotes(
  String root,
  List<ReleasePackage> packages,
) {
  final notes = <String, String>{};
  for (final package in packages) {
    final file = File('$root/docs/launch/releases/${package.tag}.md');
    if (file.existsSync()) {
      notes[package.tag] = file.readAsStringSync();
    }
  }
  return notes;
}

Future<List<String>> _gitTagsPointingAt(String root, String sha) async {
  final result = await _runCommand(
    'git',
    ['-C', root, 'tag', '--points-at', sha],
  );
  return LineSplitter.split(
    result.stdout,
  ).map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
}

Future<void> _waitForPubDev(
  List<ReleasePackage> packages,
  int waitSeconds,
) async {
  final deadline = DateTime.now().add(Duration(seconds: waitSeconds));
  while (true) {
    final missing = <String>[];
    for (final package in packages) {
      final latest = await _pubDevLatestVersion(package.name);
      if (latest != package.version) {
        missing.add('${package.name} ${package.version} (latest=$latest)');
      }
    }
    if (missing.isEmpty) return;
    if (DateTime.now().isAfter(deadline)) {
      throw CloseoutException(
        'pub.dev did not show expected versions before timeout: '
        '${missing.join(', ')}',
      );
    }
    stdout.writeln(
      'pub.dev not fully updated yet: ${missing.join(', ')}; retrying...',
    );
    await Future<void>.delayed(const Duration(seconds: 20));
  }
}

Future<String?> _pubDevLatestVersion(String package) async {
  final result = await _runCommand(
    'curl',
    ['-fsSL', 'https://pub.dev/api/packages/$package'],
  );
  final json = jsonDecode(result.stdout) as Map<String, Object?>;
  final latest = json['latest'] as Map<String, Object?>?;
  final version = latest?['version'];
  return version is String ? version : null;
}

Future<File> _writeTempNotes(String body) async {
  final dir = Directory.systemTemp.createTempSync('publish-closeout-');
  return File('${dir.path}/release-notes.md')..writeAsStringSync(body);
}

Future<void> _upsertRelease({
  required String repo,
  required String sha,
  required ReleasePlan plan,
  required File notesFile,
}) async {
  final exists = await _runCommand(
    'gh',
    ['release', 'view', plan.headlineTag, '--repo', repo],
    allowFailure: true,
  );
  if (exists.exitCode == 0) {
    if (!plan.updateExistingRelease) {
      stdout.writeln(
        'publish_closeout: release ${plan.headlineTag} already exists; '
        'leaving existing notes unchanged',
      );
      return;
    }
    await _runCommand('gh', [
      'release',
      'edit',
      plan.headlineTag,
      '--repo',
      repo,
      '--target',
      sha,
      '--title',
      plan.title,
      '--notes-file',
      notesFile.path,
    ]);
    return;
  }

  await _runCommand('gh', [
    'release',
    'create',
    plan.headlineTag,
    '--repo',
    repo,
    '--target',
    sha,
    '--verify-tag',
    '--title',
    plan.title,
    '--notes-file',
    notesFile.path,
  ]);
}

Future<void> _recordSuccessfulDeployment({
  required String repo,
  required String sha,
  required ReleasePlan plan,
  required String? runUrl,
}) async {
  if (await _hasSuccessfulPubDevDeployment(repo: repo, sha: sha)) {
    stdout.writeln('publish_closeout: pub.dev deployment already recorded');
    return;
  }

  final deployment = await _runCommand('gh', [
    'api',
    'repos/$repo/deployments',
    '--method',
    'POST',
    '-f',
    'ref=$sha',
    '-f',
    'environment=pub.dev',
    '-f',
    'description=pub.dev release closeout',
    '-F',
    'auto_merge=false',
    '-F',
    'required_contexts[]',
  ]);
  final deploymentJson = jsonDecode(deployment.stdout) as Map<String, Object?>;
  final deploymentId = deploymentJson['id'];
  if (deploymentId == null) {
    throw CloseoutException('GitHub deployment response did not include an id');
  }

  final releaseUrl =
      'https://github.com/$repo/releases/tag/${plan.headlineTag}';
  await _runCommand('gh', [
    'api',
    'repos/$repo/deployments/$deploymentId/statuses',
    '--method',
    'POST',
    '-f',
    'state=success',
    '-f',
    'environment=pub.dev',
    '-f',
    'description=${_deploymentDescription(plan)}',
    '-f',
    'environment_url=$releaseUrl',
    '-f',
    'target_url=${runUrl ?? releaseUrl}',
    '-F',
    'auto_inactive=false',
  ]);
}

Future<bool> _hasSuccessfulPubDevDeployment({
  required String repo,
  required String sha,
}) async {
  final deployments = await _runCommand('gh', [
    'api',
    'repos/$repo/deployments?sha=$sha&environment=pub.dev&per_page=100',
  ]);
  final decoded = jsonDecode(deployments.stdout) as List<Object?>;
  for (final item in decoded.cast<Map<String, Object?>>()) {
    final id = item['id'];
    if (id == null) continue;
    final statuses = await _runCommand('gh', [
      'api',
      'repos/$repo/deployments/$id/statuses',
    ]);
    final statusList = jsonDecode(statuses.stdout) as List<Object?>;
    if (statusList.isEmpty) continue;
    final latest = statusList.first;
    if (latest is Map<String, Object?> && latest['state'] == 'success') {
      return true;
    }
  }
  return false;
}

String _deploymentDescription(ReleasePlan plan) {
  final versions = plan.packages.map((pkg) => '${pkg.name} ${pkg.version}');
  final text = 'Published ${versions.join(', ')} to pub.dev';
  if (text.length <= 140) return text;
  return '${text.substring(0, 137)}...';
}

Future<_CommandResult> _runCommand(
  String executable,
  List<String> args, {
  bool allowFailure = false,
}) async {
  final result = await Process.run(executable, args);
  final command = '$executable ${args.join(' ')}';
  if (!allowFailure && result.exitCode != 0) {
    throw CloseoutException(
      'command failed ($command)\n'
      'stdout:\n${result.stdout}\n'
      'stderr:\n${result.stderr}',
    );
  }
  return _CommandResult(
    exitCode: result.exitCode,
    stdout: result.stdout.toString(),
    stderr: result.stderr.toString(),
  );
}

class ReleasePackage {
  const ReleasePackage({
    required this.name,
    required this.version,
    required this.tag,
  });

  final String name;
  final String version;
  final String tag;
}

class ReleasePlan {
  const ReleasePlan({
    required this.headlineTag,
    required this.title,
    required this.body,
    required this.packages,
    required this.updateExistingRelease,
  });

  final String headlineTag;
  final String title;
  final String body;
  final List<ReleasePackage> packages;
  final bool updateExistingRelease;
}

class CuratedReleaseNotes {
  const CuratedReleaseNotes({
    required this.title,
    required this.headlineTag,
    required this.packageNames,
    required this.body,
  });

  factory CuratedReleaseNotes.parse(String content) {
    final lines = content.replaceAll('\r\n', '\n').split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') {
      return CuratedReleaseNotes(
        title: null,
        headlineTag: null,
        packageNames: const [],
        body: content,
      );
    }

    final frontMatter = <String>[];
    var end = -1;
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        end = i;
        break;
      }
      frontMatter.add(lines[i]);
    }
    if (end == -1) {
      throw CloseoutException(
        'curated release notes front matter is not closed',
      );
    }

    String? title;
    String? headlineTag;
    final packageNames = <String>[];
    var inPackages = false;
    for (final line in frontMatter) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed == 'packages:') {
        inPackages = true;
        continue;
      }
      if (trimmed.startsWith('- ') && inPackages) {
        packageNames.add(trimmed.substring(2).trim());
        continue;
      }
      inPackages = false;
      final split = trimmed.indexOf(':');
      if (split == -1) continue;
      final key = trimmed.substring(0, split).trim();
      final value = trimmed.substring(split + 1).trim();
      if (key == 'title') title = value;
      if (key == 'headline_tag') headlineTag = value;
    }

    return CuratedReleaseNotes(
      title: title,
      headlineTag: headlineTag,
      packageNames: packageNames,
      body: lines.skip(end + 1).join('\n'),
    );
  }

  final String? title;
  final String? headlineTag;
  final List<String> packageNames;
  final String body;
}

class UsageException implements Exception {
  UsageException(this.message);

  final String message;
}

class CloseoutException implements Exception {
  CloseoutException(this.message);

  final String message;
}

class _CommandResult {
  const _CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

class _Options {
  const _Options({
    required this.root,
    required this.repo,
    required this.sha,
    required this.runUrl,
    required this.pubDevWaitSeconds,
    required this.dryRun,
    required this.help,
  });

  factory _Options.parse(List<String> args) {
    var root = Directory.current.path;
    String? repo;
    String? sha;
    String? runUrl;
    var pubDevWaitSeconds = 900;
    var dryRun = false;
    var help = false;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String takeValue() {
        if (i + 1 >= args.length) {
          throw UsageException('$arg requires a value');
        }
        return args[++i];
      }

      switch (arg) {
        case '--root':
          root = takeValue();
        case '--repo':
          repo = takeValue();
        case '--sha':
          sha = takeValue();
        case '--run-url':
          runUrl = takeValue();
        case '--pubdev-wait-seconds':
          pubDevWaitSeconds = int.parse(takeValue());
        case '--dry-run':
          dryRun = true;
        case '--help':
        case '-h':
          help = true;
        default:
          throw UsageException('unknown argument: $arg');
      }
    }

    return _Options(
      root: root,
      repo: repo,
      sha: sha,
      runUrl: runUrl,
      pubDevWaitSeconds: pubDevWaitSeconds,
      dryRun: dryRun,
      help: help,
    );
  }

  final String root;
  final String? repo;
  final String? sha;
  final String? runUrl;
  final int pubDevWaitSeconds;
  final bool dryRun;
  final bool help;
}

const _usage = '''
usage: dart run tool/publish_closeout.dart --sha <commit> --repo <owner/repo>

Options:
  --root <dir>                 repository root (default: current directory)
  --repo <owner/repo>          GitHub repository (default: GITHUB_REPOSITORY)
  --sha <commit>               release commit SHA
  --run-url <url>              Actions run URL for deployment target_url
  --pubdev-wait-seconds <n>    pub.dev polling deadline (default: 900)
  --dry-run                    render the closeout plan without GitHub writes
''';
