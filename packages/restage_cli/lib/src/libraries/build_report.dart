import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/config/restage_config.dart'
    show loadRestageConfig;
import 'package:restage_cli/src/libraries/generated_part_check.dart';
import 'package:restage_cli/src/render_bundles/generated_widget_catalog.dart'
    show generatedCompilerHandoffPath;
import 'package:restage_cli/src/render_bundles/package_resolution.dart'
    show readProjectPackageName;

/// The command that moves an island into a widget class of the app's own.
const promoteCommandName = 'widget promote';

/// The committed baseline a build report compares against, at the package
/// root.
const buildReportBaselineName = 'restage_build_report.json';

/// The build report could not be read.
@experimental
final class BuildReportException implements Exception {
  /// Creates the failure.
  const BuildReportException(this.message);

  /// The sentence that says so.
  final String message;

  @override
  String toString() => message;
}

/// One part of a compiled surface, as the code generator recorded it.
@experimental
@immutable
final class BuildReportPart {
  /// Creates a part.
  const BuildReportPart({
    required this.kind,
    required this.mount,
    required this.name,
    required this.widget,
    required this.location,
    this.reason,
    this.token,
    this.interface,
    this.widgets,
    this.promotion,
  });

  /// `design`, `island`, `value`, `action` or `mount`.
  final String kind;

  /// The generated widget the part belongs to.
  final String mount;

  /// The qualified island name, the value or action key, or the kept class.
  final String name;

  /// The widget type, or the value's or action's source.
  final String widget;

  /// `path:line:column`, or the source path for a design.
  final String location;

  /// Why an island renders from the app, or why the mount keeps a wrapper.
  final String? reason;

  /// An island's fit token.
  final String? token;

  /// An island's inputs and slots, one per line.
  final String? interface;

  /// The widgets an island renders from the app, or a design delivers.
  final int? widgets;

  /// How to move an island into a widget class of the app's own:
  /// `file`, `offset`, `original`, `class` and `call`, or `refusal`.
  final Map<String, Object?>? promotion;

  /// The source of the class an island would move into, or null.
  String? get promotedClass => promotion?['class'] as String?;

  /// How many literal arguments an island takes from the design.
  int get properties => (interface ?? '')
      .split('\n')
      .where((line) => line.startsWith('property '))
      .length;

  /// The JSON form.
  Map<String, Object?> toJson() => {
    'kind': kind,
    'name': name,
    'widget': widget,
    'location': location,
    'reason': ?reason,
    'token': ?token,
    'interface': ?interface,
    'widgets': ?widgets,
    'promotion': ?promotion,
  };
}

/// What changed in one generated widget since the baseline.
@experimental
@immutable
final class BuildReportChange {
  /// Creates a change.
  const BuildReportChange(this.kind, this.mount, this.widget, {this.location});

  /// `islandAdded`, `islandRemoved`, `islandChanged`, `keptAdded` or
  /// `keptRemoved`.
  final String kind;

  /// The generated widget.
  final String mount;

  /// The island's or kept wrapper's widget.
  final String widget;

  /// Where this build has it.
  final String? location;

  /// The JSON form.
  Map<String, Object?> toJson() => {
    'kind': kind,
    'mount': mount,
    'widget': widget,
    'location': ?location,
  };

  /// The line naming this change.
  String get sentence => switch (kind) {
    'islandAdded' =>
      '`$widget`${_at(location)} in `$mount` now renders from the app.',
    'islandRemoved' => '`$widget` in `$mount` no longer renders from the app.',
    'islandChanged' =>
      'The app code of `$widget`${_at(location)} in `$mount` changed. Live '
          'versions that show it fall back to the screen compiled into the '
          'app until you republish them.',
    'keptAdded' => 'App code now keeps `$widget` in `$mount` for every design.',
    _ => 'App code no longer keeps `$widget` in `$mount` for every design.',
  };
}

/// What the last local build compiled: each generated widget's delivered
/// design, values, actions, islands and kept wrappers.
@experimental
@immutable
final class BuildReport {
  /// Creates a report of [parts], in build order.
  const BuildReport(this.parts);

  /// Reads the last build of the package at [projectRoot].
  factory BuildReport.read(Directory projectRoot) {
    final String package;
    try {
      package = readProjectPackageName(projectRoot);
    } on StateError {
      throw BuildReportException(
        "${projectRoot.path} isn't inside a Dart package. Try running the "
        "command in your app's package directory.",
      );
    }
    final handoff = File(generatedCompilerHandoffPath(projectRoot, package));
    if (!handoff.existsSync()) {
      throw const BuildReportException(
        'There is no build to report on. Try running `dart run build_runner '
        'build` first.',
      );
    }
    try {
      if (jsonDecode(handoff.readAsStringSync()) case {
        'splitSites': final List<Object?> sites,
      }) {
        return BuildReport([
          for (final site in sites.cast<Map<String, Object?>>())
            BuildReportPart(
              kind: site['kind']! as String,
              mount: site['mount']! as String,
              name: site['name']! as String,
              widget: site['widget']! as String,
              location: site['location']! as String,
              reason: site['reason'] as String?,
              token: site['token'] as String?,
              interface: site['interface'] as String?,
              widgets: site['widgets'] as int?,
              promotion: site['promotion'] as Map<String, Object?>?,
            ),
        ]);
      }
      return const BuildReport([]);
    } on Object catch (error) {
      if (error is BuildReportException) rethrow;
      throw const BuildReportException(
        "The last build's report can't be read. Try running `dart run "
        'build_runner build` again.',
      );
    }
  }

  /// Every part, in build order.
  final List<BuildReportPart> parts;

  /// The generated widgets, in build order.
  List<String> get mounts => {for (final part in parts) part.mount}.toList();

  /// The parts of [mount].
  Iterable<BuildReportPart> of(String mount) =>
      parts.where((part) => part.mount == mount);

  /// The widgets [mount] delivers and renders from the app.
  ({int delivered, int app}) share(String mount) {
    var delivered = 0;
    var app = 0;
    for (final part in of(mount)) {
      if (part.kind == 'design') delivered += part.widgets ?? 0;
      if (part.kind == 'island') app += part.widgets ?? 1;
    }
    return (delivered: delivered, app: app);
  }

  /// What a baseline records: each generated widget's islands and kept
  /// wrappers, without locations, so moving code changes nothing.
  Map<String, Object?> get baseline => {
    'mounts': {
      for (final mount in mounts.toList()..sort())
        mount: {
          'islands': {
            for (final island in of(mount).where((p) => p.kind == 'island'))
              island.name: {'widget': island.widget, 'token': island.token},
          },
          'kept': [
            for (final kept in of(mount).where((p) => p.kind == 'mount'))
              kept.widget,
          ]..sort(),
        },
    },
  };

  /// What changed since [baseline], in mount order.
  List<BuildReportChange> changesSince(Map<String, Object?> baseline) {
    final before = switch (baseline['mounts']) {
      final Map<String, Object?> mounts => mounts,
      _ => const <String, Object?>{},
    };
    final now = this.baseline['mounts']! as Map<String, Object?>;
    final changes = <BuildReportChange>[];
    for (final mount in {...before.keys, ...now.keys}.toList()..sort()) {
      final (oldIslands, oldKept) = _entries(before[mount]);
      final (newIslands, newKept) = _entries(now[mount]);
      String? where(String name) =>
          of(mount).where((part) => part.name == name).firstOrNull?.location;
      for (final MapEntry(key: name, value: island) in newIslands.entries) {
        final old = oldIslands[name];
        if (old == null) {
          changes.add(
            BuildReportChange(
              'islandAdded',
              mount,
              island.widget,
              location: where(name),
            ),
          );
        } else if (old.token != island.token) {
          changes.add(
            BuildReportChange(
              'islandChanged',
              mount,
              island.widget,
              location: where(name),
            ),
          );
        }
      }
      for (final MapEntry(key: name, value: island) in oldIslands.entries) {
        if (!newIslands.containsKey(name)) {
          changes.add(BuildReportChange('islandRemoved', mount, island.widget));
        }
      }
      for (final kept in _minus(newKept, oldKept)) {
        changes.add(BuildReportChange('keptAdded', mount, kept));
      }
      for (final kept in _minus(oldKept, newKept)) {
        changes.add(BuildReportChange('keptRemoved', mount, kept));
      }
    }
    return changes;
  }

  /// The JSON form, with [changes] when a baseline exists.
  Map<String, Object?> toJson({List<BuildReportChange>? changes}) => {
    'mounts': [
      for (final mount in mounts)
        {
          'mount': mount,
          'delivered': share(mount).delivered,
          'app': share(mount).app,
          'parts': [
            for (final part in of(mount))
              if (part.kind != 'design') part.toJson(),
          ],
        },
    ],
    if (changes != null)
      'changes': [for (final change in changes) change.toJson()],
  };

  /// The report as lines: one block per generated widget, then where a
  /// widget class of the app's own would pay off.
  List<String> get lines => [
    for (final mount in mounts) ..._mountLines(mount),
    ...promotionSuggestions,
  ];

  /// Islands worth moving into a widget class: the same code in several
  /// generated widgets, or one that takes many values from the design.
  List<String> get promotionSuggestions {
    final byCode = <String, List<BuildReportPart>>{};
    for (final island in parts.where((part) => part.kind == 'island')) {
      final code = island.promotedClass
          ?.split('\n')
          .where((line) => !line.trimLeft().startsWith('///'))
          .join('\n');
      if (code != null) (byCode[code] ??= []).add(island);
    }
    return [
      for (final same in byCode.values)
        if ({for (final part in same) part.mount}.length > 1)
          'The same app code renders `${same.first.widget}` in '
              '${{for (final part in same) '`${part.mount}`'}.join(', ')}. '
              'Try `restage $promoteCommandName ${same.first.location}` to '
              'move it into one widget class that designs can use.'
        else
          for (final part in same)
            if (part.properties >= 3)
              '`${part.widget}` (${part.location}) takes ${part.properties} '
                  'values from the design. Try `restage $promoteCommandName '
                  '${part.location}` to name them in the editor.',
    ];
  }

  List<String> _mountLines(String mount) {
    final (:delivered, :app) = share(mount);
    final total = delivered + app;
    final percent = total == 0 ? 100 : (delivered * 100 / total).floor();
    final design = of(mount).where((part) => part.kind == 'design');
    final source = design.isEmpty ? '' : ' (${design.first.location})';
    return [
      '`$mount`$source: designs can change $delivered of its $total widgets '
          '($percent%).',
      for (final part in of(mount))
        if (_partLine(part) case final line?) '  $line',
    ];
  }

  static String? _partLine(BuildReportPart part) => switch (part.kind) {
    'value' => 'App code computes `${part.widget}`${_at(part.location)}.',
    'action' => 'App code runs `${part.widget}`${_at(part.location)}.',
    'island' =>
      '`${part.widget}`${_at(part.location)} renders from the app.${part.reason == null ? '' : ' ${part.reason}'}',
    'mount' => switch (part.reason) {
      'state' =>
        "App code holds the screen's state in "
            '`${part.widget}`${_at(part.location)} for every design.',
      'builder' =>
        'App code keeps `${part.widget}`${_at(part.location)} around every '
            'design, and every design can read its values.',
      _ =>
        'App code keeps `${part.widget}`${_at(part.location)} around every '
            'design.',
    },
    _ => null,
  };
}

/// The baseline of the package at [projectRoot], or null when it has none.
@experimental
Map<String, Object?>? readBuildReportBaseline(Directory projectRoot) {
  final file = File(p.join(projectRoot.path, buildReportBaselineName));
  if (!file.existsSync()) return null;
  try {
    return switch (jsonDecode(file.readAsStringSync())) {
      final Map<String, Object?> baseline => baseline,
      _ => throw const FormatException(),
    };
  } on FormatException {
    throw const BuildReportException(
      "$buildReportBaselineName can't be read. Try running `restage build "
      'report --accept` to write it again.',
    );
  }
}

/// Records [report] as the baseline of the package at [projectRoot].
@experimental
void writeBuildReportBaseline(Directory projectRoot, BuildReport report) {
  File(p.join(projectRoot.path, buildReportBaselineName)).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.baseline)}\n',
  );
}

String _at(String? location) =>
    location == null || location.isEmpty ? '' : ' ($location)';

(Map<String, ({String widget, String? token})>, List<String>) _entries(
  Object? mount,
) => switch (mount) {
  {
    'islands': final Map<String, Object?> islands,
    'kept': final List<Object?> kept,
  } =>
    (
      {
        for (final MapEntry(:key, :value) in islands.entries)
          if (value case {'widget': final String widget})
            key: (
              widget: widget,
              token: (value as Map<String, Object?>)['token'] as String?,
            ),
      },
      kept.cast<String>(),
    ),
  _ => (const {}, const []),
};

// [from] less one of each entry of [take].
List<String> _minus(List<String> from, List<String> take) {
  final left = [...take];
  return [
    for (final item in from)
      if (!left.remove(item)) item,
  ];
}

/// The line above a report's changes.
const buildReportChangesHeading = 'Changes since $buildReportBaselineName:';

/// The line for a build that matches its baseline.
const buildReportUnchangedSentence =
    'The widgets that render from the app and the wrappers kept for every '
    'design match $buildReportBaselineName.';

/// The line for a package with no baseline.
const buildReportNoBaselineSentence =
    'There is no $buildReportBaselineName to compare with. Try running '
    '`restage build report --accept` to record this build.';

/// The line after an accepted baseline.
const buildReportAcceptedSentence =
    'Recorded this build in $buildReportBaselineName.';

/// The line a failed check ends with.
const buildReportCheckSentence =
    'This build differs from $buildReportBaselineName. Try reviewing the '
    'changes above, then running `restage build report --accept`.';

/// What [readBuildReport] read.
@experimental
typedef BuildReportResult = ({
  BuildReport report,
  List<BuildReportChange>? changes,
  List<GeneratedPartError> broken,
});

/// The JSON form of [result], as `--json` and the MCP tool give it.
@experimental
Map<String, Object?> buildReportJson(BuildReportResult result) => {
  ...result.report.toJson(changes: result.changes),
  if (result.broken.isNotEmpty)
    'generatedErrors': [
      for (final part in result.broken)
        {...part.toJson(), 'sentence': generatedPartErrorSentence(part)},
    ],
};

/// Reads the last build of the package [from] is in and compares it with the
/// baseline; with [accept], records it as the baseline instead, and the
/// changes are empty. The changes are null when there is no baseline.
/// [broken] lists the generated parts that don't compile.
@experimental
Future<BuildReportResult> readBuildReport(
  Directory from, {
  bool accept = false,
  GeneratedPartAnalyzer? analyze,
}) async {
  final loaded = await loadRestageConfig(from: from);
  final root = loaded?.source.parent ?? from.absolute;
  final report = BuildReport.read(root);
  final broken = await generatedPartErrors(root, analyze: analyze);
  if (accept) {
    writeBuildReportBaseline(root, report);
    return (
      report: report,
      changes: const <BuildReportChange>[],
      broken: broken,
    );
  }
  final baseline = readBuildReportBaseline(root);
  return (
    report: report,
    changes: baseline == null ? null : report.changesSince(baseline),
    broken: broken,
  );
}
