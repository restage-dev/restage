import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/byte_data_wire.dart';
import 'package:restage_cli/src/measurement/page_views/overview_apps_view.dart';
import 'package:restage_cli/src/measurement/page_views/overview_view.dart';
import 'package:restage_cli/src/measurement/page_views/explore_view.dart';
import 'package:restage_cli/src/measurement/page_views/surface_view.dart';
import 'package:restage_cli/src/measurement/page_views/taps_view.dart';
import 'package:restage_cli/src/measurement/page_views/delivery_map_view.dart';
import 'package:restage_cli/src/measurement/page_views/health_view.dart';
import 'package:restage_cli/src/measurement/page_views/experiment_list_view.dart';
import 'package:restage_cli/src/measurement/page_views/experiment_results_view.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Days of history a read covers when the caller names no window.
const int kPageReadDefaultWindowDays = 30;

/// The kind of value a page-read parameter takes.
@experimental
enum PageParamKind {
  /// One string.
  string,

  /// One integer.
  integer,

  /// A list of strings.
  stringList,

  /// A switch, present or absent.
  flag,
}

/// One parameter of a page read beyond the target and the window.
@experimental
@immutable
class PageParam {
  /// Construct a parameter. [key] is the MCP argument name.
  const PageParam(
    this.key, {
    required this.cli,
    required this.kind,
    required this.help,
    this.required = false,
    this.allowed,
    this.positional = false,
    this.cliOnly = false,
    this.parse,
  });

  /// The MCP argument name and the key the read reads.
  final String key;

  /// The CLI flag name.
  final String cli;

  /// The value type.
  final PageParamKind kind;

  /// Help text, on the CLI and in the tool schema.
  final String help;

  /// Whether a value is required.
  final bool required;

  /// The accepted values, when closed.
  final List<String>? allowed;

  /// Whether the CLI takes it as the command's one argument, not a flag.
  final bool positional;

  /// Whether it shapes only the CLI's text, so no tool or request carries it.
  final bool cliOnly;

  /// Turns a string value into what the read sends; throws [FormatException].
  final Object Function(String value)? parse;
}

/// The half-open window one read covers, in microseconds since the epoch.
typedef PageWindowMicros = ({int start, int end});

/// What one read is asked to do, once its target and window are resolved.
@experimental
class PageRequest {
  /// Construct a request.
  const PageRequest({required this.target, required this.values, this.window});

  /// The exact target.
  final TargetCoordinate target;

  /// The supplied parameter values, keyed by [PageParam.key].
  final Map<String, Object?> values;

  /// The window, when the read has one.
  final PageWindowMicros? window;

  /// The window of a read that always has one.
  PageWindowMicros get span => window!;
}

/// One dashboard page read, defined once for the CLI and the MCP server.
@experimental
@immutable
class PageRead {
  /// Construct a page read.
  const PageRead({
    required this.cliPath,
    required this.mcpName,
    required this.method,
    required this.summary,
    required this.mcpDescription,
    required this.wire,
    required this.render,
    this.params = const [],
    this.optionalWindow = false,
    this.allApps,
    this.organizationWide = false,
    this.renderFor,
  });

  /// The CLI command path, such as `analytics overview`.
  final String cliPath;

  /// The MCP tool name.
  final String mcpName;

  /// The `measurementRead` method the read calls.
  final String method;

  /// The command's one-line summary.
  final String summary;

  /// The tool description: what each figure means and what it does not.
  final String mcpDescription;

  /// The parameters beyond the target and the window.
  final List<PageParam> params;

  /// Whether the read covers the whole run unless a window is named.
  final bool optionalWindow;

  /// The read that answers instead when the `allApps` flag is set.
  final PageRead? allApps;

  /// Whether the read spans every app, so its reply names only the
  /// organization, named environment and plane.
  final bool organizationWide;

  /// The read to run for [values]: [allApps] when that flag is set.
  PageRead select(Map<String, Object?> values) =>
      values['allApps'] == true && allApps != null ? allApps! : this;

  /// The service arguments for [request].
  final Map<String, Object?> Function(PageRequest request) wire;

  /// Writes the figures of one page document for a person.
  final void Function(StringSink out, Map<String, Object?> document) render;

  /// Writes the page with the values the caller gave, when they shape it.
  final void Function(
    StringSink out,
    Map<String, Object?> document,
    Map<String, Object?> values,
  )?
  renderFor;
}

/// The window a read covers, or null when it covers the whole run.
///
/// A window that names only an end starts [kPageReadDefaultWindowDays] before
/// it; one that names neither ends at [now].
@experimental
PageWindowMicros? resolvePageWindow(
  PageRead read, {
  required int? startMicros,
  required int? endMicros,
  required DateTime now,
}) {
  if (read.optionalWindow && startMicros == null && endMicros == null) {
    return null;
  }
  final end = endMicros ?? now.toUtc().microsecondsSinceEpoch;
  final start =
      startMicros ??
      end - const Duration(days: kPageReadDefaultWindowDays).inMicroseconds;
  if (start >= end) {
    throw const FormatException('The window must end after it starts.');
  }
  return (start: start, end: end);
}

/// The service arguments that name [target].
Map<String, Object?> pageTargetArgs(TargetCoordinate target) => {
  'organizationId': target.organizationId.value,
  'appId': target.appId.value,
  'environmentTargetId': target.environmentTargetId.value,
  'namedEnvironmentId': target.namedEnvironmentId.value,
  'runtimePlane': target.runtimePlane.wireName,
};

/// The bucket width a window is read at: whole days when it is whole days,
/// else the window itself.
int pageBucketWidthMicros(PageWindowMicros window) {
  final span = window.end - window.start;
  const day = Duration.microsecondsPerDay;
  return span % day == 0 ? day : span;
}

/// The default series granularity.
const String kPageDefaultGranularity = 'day';

const _granularities = ['day', 'week', 'month'];

const _granularity = PageParam(
  'granularity',
  cli: 'granularity',
  kind: PageParamKind.string,
  allowed: _granularities,
  help: 'Bucket size of the series: day, week or month.',
);

const _surface = PageParam(
  'surfaceId',
  cli: 'surface',
  kind: PageParamKind.string,
  required: true,
  help: 'The surface slug or measurement id.',
);

/// The dimensions Explore can split by.
const List<String> kExploreDimensions = [
  'arm',
  'publishedVersion',
  'sdkVersion',
  'country',
  'platform',
  'appBuildOrdinal',
  'deviceClass',
  'countryPlatform',
];

const int _overviewSurfaceLimit = 50;
const int _overviewAttentionLimit = 3;
const int _experimentListLimit = 50;
const int _experimentHistoryPageSize = 50;
const int _assignmentApiLevel = 3;

/// A roster query over the window, in canonical bytes on the service wire.
String _rosterQuery({required int limit, PageWindowMicros? attentionWindow}) =>
    encodeByteDataWire(
      CanonicalJsonCodec.encode({
        'kind': 'measurementRosterQueryV1',
        'search': '',
        'sort': 'createdNewest',
        'archive': 'active',
        'lifecycle': null,
        'surfaceType': null,
        'surfaceId': null,
        'attentionOnly': false,
        if (attentionWindow != null)
          'attentionWindow': {
            'kind': 'halfOpenTimeWindow',
            'startMicros': attentionWindow.start,
            'endExclusiveMicros': attentionWindow.end,
          },
        'limit': limit,
        'cursor': null,
      }),
    );

/// The UTC day bounds a policy reading covers, from [window].
({int start, int end}) _dayWindow(PageWindowMicros window) {
  const day = Duration.microsecondsPerDay;
  final start = window.start - window.start.remainder(day);
  var end = window.end - window.end.remainder(day);
  if (end < window.end || end <= start) end += day;
  return (start: start, end: end);
}

Map<String, Object?> _windowArgs(PageRequest r) => {
  'windowStartMicros': r.span.start,
  'windowEndExclusiveMicros': r.span.end,
};

/// The seven page reads, in CLI order.
@experimental
final List<PageRead> pageReads = [
  PageRead(
    cliPath: 'analytics overview',
    mcpName: 'restage_read_analytics_overview',
    method: 'readOverviewPage',
    summary: 'Totals for one app and period.',
    mcpDescription:
        'Read the Analytics overview for one exact target and window: views '
        'and users for the window and the window before it, the surfaces '
        'with their own views and versions, the surfaces that need '
        'attention, and the experiments with their status. Views are '
        'presentations of a surface. Users are anonymous sessions on a '
        'device. A rate is a decimal beside the exact '
        'numerator and denominator it came from. A count under the '
        'disclosure floor of 5 is absent and reads "<5"; a figure the '
        'service withholds states why. The reply names the window and the '
        'publication it was read at. Set allApps to read every app in the '
        'environment together instead: the three at-a-glance figures '
        '(app sessions that saw a surface, onboarding and surveys finished, '
        'revenue from surfaces) as a total and per app, with the finish '
        'rate per app (finished over eligible views). A figure is exact, '
        'approximate, at least a number, held under the floor of 5, or '
        'unavailable. The figures are the dashboard\'s own and are '
        'returned unchanged.',
    params: const [
      _granularity,
      PageParam(
        'allApps',
        cli: 'all-apps',
        kind: PageParamKind.flag,
        help: 'Every app in the organization, in this app\'s environment.',
      ),
    ],
    allApps: PageRead(
      cliPath: 'analytics overview',
      mcpName: 'restage_read_analytics_overview',
      method: 'readOverviewAppsPage',
      summary: 'Totals for every app and period.',
      mcpDescription: '',
      organizationWide: true,
      params: const [_granularity],
      wire: (r) => {
        'organizationId': r.target.organizationId.value,
        'namedEnvironmentId': r.target.namedEnvironmentId.value,
        'runtimePlane': r.target.runtimePlane.wireName,
        ..._windowArgs(r),
        'granularity': r.values['granularity'] ?? kPageDefaultGranularity,
      },
      render: renderOverviewAppsPage,
    ),
    wire: (r) => {
      ...pageTargetArgs(r.target),
      'queryBytes': _rosterQuery(
        limit: _overviewSurfaceLimit,
        attentionWindow: r.span,
      ),
      ..._windowArgs(r),
      'bucketWidthMicros': pageBucketWidthMicros(r.span),
      'granularity': r.values['granularity'] ?? kPageDefaultGranularity,
      'attentionLimit': _overviewAttentionLimit,
    },
    render: renderOverviewPage,
  ),
  PageRead(
    cliPath: 'analytics explore',
    mcpName: 'restage_read_explore',
    method: 'readExplorePage',
    summary: 'Views and users by one dimension.',
    mcpDescription:
        'Read views and users for one exact target and window, split by one '
        'dimension: variant, published version, SDK version, country, '
        'platform, app build, device class or country and platform. Views '
        'are presentations of a surface. Users are anonymous sessions. '
        'Each split row states its count beside the whole; a '
        'count under the disclosure floor of 5 is absent and reads "<5", '
        'and splits held whole are counted in hiddenSplitCount. Name a '
        'surface to read that one surface. The figures are the '
        'dashboard\'s own and are returned unchanged.',
    params: const [
      PageParam(
        'dimension',
        cli: 'dimension',
        kind: PageParamKind.string,
        required: true,
        allowed: kExploreDimensions,
        help: 'What to split by.',
      ),
      PageParam(
        'surfaceId',
        cli: 'surface',
        kind: PageParamKind.string,
        help: 'Read only this surface. Omit for every surface.',
      ),
      _granularity,
    ],
    wire: (r) => {
      ...pageTargetArgs(r.target),
      'dimension': r.values['dimension'],
      ..._windowArgs(r),
      'bucketWidthMicros': pageBucketWidthMicros(r.span),
      'surfaceId': ?r.values['surfaceId'],
      'granularity': ?r.values['granularity'],
    },
    render: renderExplorePage,
  ),
  PageRead(
    cliPath: 'analytics surface',
    mcpName: 'restage_read_surface_analytics',
    method: 'readSurfaceAnalyticsPage',
    summary: 'One surface’s versions, steps and metrics.',
    mcpDescription:
        'Read one surface\'s analytics for one exact target and window: its '
        'views and users, its metrics per published version with the '
        'window before for comparison, the comparison between versions, '
        'its experiments, and where it is delivered. Views are '
        'presentations of the surface. A paywall also states first purchases '
        'and the purchase rate per version, and a funnel states its steps '
        'with the users who reached each. A rate is a decimal beside the exact numerator and '
        'denominator it came from. A count under the disclosure floor of 5 '
        'is absent and reads "<5". A metric the service cannot state '
        'carries the reason. Name versions to read only those. The figures '
        'are the dashboard\'s own and are returned unchanged.',
    params: const [
      _surface,
      PageParam(
        'surfaceRevisionIds',
        cli: 'version',
        kind: PageParamKind.stringList,
        help:
            'Read only this published version, by its version identity. '
            'Repeat to name several. Omit for every version.',
      ),
      _granularity,
    ],
    wire: (r) => {
      ...pageTargetArgs(r.target),
      'surfaceId': r.values['surfaceId'],
      ..._windowArgs(r),
      'bucketWidthMicros': pageBucketWidthMicros(r.span),
      'surfaceRevisionIds': ?r.values['surfaceRevisionIds'],
      'granularity': ?r.values['granularity'],
    },
    render: renderSurfaceAnalyticsPage,
  ),
  PageRead(
    cliPath: 'analytics taps',
    mcpName: 'restage_read_surface_taps',
    method: 'readSurfaceVersionTaps',
    summary: 'Taps per element on one published version.',
    mcpDescription:
        'Read the screens and taps of one published version of a surface for '
        'one exact target and window, by the ordinal the version was '
        'served at. Counts are presentations of the surface. A '
        'count under the disclosure floor of 5 is absent and reads "<5"; a '
        'version or element held whole keeps its identity and states no '
        'counts. The figures are the dashboard\'s own and are returned '
        'unchanged.',
    params: const [
      _surface,
      PageParam(
        'revisionOrdinal',
        cli: 'version',
        kind: PageParamKind.integer,
        required: true,
        help: 'The version ordinal, counting from 1.',
      ),
    ],
    wire: (r) => {
      ...pageTargetArgs(r.target),
      'surfaceId': r.values['surfaceId'],
      'revisionOrdinal': r.values['revisionOrdinal'],
      ..._windowArgs(r),
    },
    render: renderSurfaceTapsPage,
  ),
  PageRead(
    cliPath: 'analytics health',
    mcpName: 'restage_read_data_health',
    method: 'readDataHealthPage',
    summary: 'What the app is sending.',
    mcpDescription:
        'Read what the app is sending for one exact target and window: '
        'sessions and views received, the published manifests, the surface '
        'types seen, and whether the collection policy in force is '
        'compatible with the one the current SDK asks for. Sessions are '
        'anonymous SDK runtimes. A '
        'population that is lost states why and for how long. A count '
        'under the disclosure floor of 5 is absent and reads "<5". The '
        'figures are the dashboard\'s own and are returned unchanged.',
    wire: (r) {
      final days = _dayWindow(r.span);
      return {
        ...pageTargetArgs(r.target),
        'sessionQueryBytes': encodeByteDataWire(
          CanonicalJsonCodec.encode({
            'kind': 'sessionSummaryQueryV1',
            'fromMicros': r.span.start,
            'untilMicros': r.span.end,
            'surfaceIds': <String>[],
            'surfaceRevisionIds': <String>[],
            'placements': <Object?>[],
            'experimentId': null,
          }),
        ),
        'proposedPrivacyPolicyRevisionId':
            '$manifestPrivacyPolicyFamily.v$presentationMetadataPrivacyPolicyFloor',
        'proposedCollectionBudgetRevisionId':
            '$collectionBudgetFamily.v$presentationMetadataCollectionBudgetFloor',
        'proposedAssignmentApiLevel': _assignmentApiLevel,
        'windowStartDayUtc': days.start,
        'windowEndDayExclusiveUtc': days.end,
      };
    },
    render: renderDataHealthPage,
  ),
  PageRead(
    cliPath: 'experiment list',
    mcpName: 'restage_read_experiments',
    method: 'readExperimentListPage',
    summary: 'Experiments with their status.',
    mcpDescription:
        'List the experiments at one exact target with their status. Each '
        'row states its lifecycle (draft, active, paused or concluded), '
        'its variants, its primary and safety metrics, its enrollment '
        'progress, and the identity of the result it reads. The roster '
        'states its total and how many rows need attention. Experiment '
        'figures are users assigned to a variant. A count '
        'under the disclosure floor of 5 is absent and reads "<5". The '
        'figures are the dashboard\'s own and are returned unchanged.',
    wire: (r) => {
      ...pageTargetArgs(r.target),
      'queryBytes': _rosterQuery(limit: _experimentListLimit),
      ..._windowArgs(r),
    },
    render: renderExperimentListPage,
  ),
  PageRead(
    cliPath: 'experiment results',
    mcpName: 'restage_read_experiment',
    method: 'readExperimentResultsPage',
    summary: 'One experiment’s summary, variants and safety metrics.',
    mcpDescription:
        'Read one experiment\'s results at one exact target: its status and '
        'whether it has reached its decision, the epoch the figures belong '
        'to, the observed difference per variant, the safety metrics, '
        'the history of decisions, and the app builds that could not show a '
        'variant. Without a window the read covers the '
        'experiment\'s whole run. Figures are users assigned to a variant. '
        'A rate, effect and interval end is a decimal beside '
        'the exact numerator and denominator it came from. A result with '
        'fewer than 5 users, successes or failures in any variant is held '
        'for privacy: it states no figures. The figures are the '
        'dashboard\'s own and are returned unchanged.',
    optionalWindow: true,
    params: const [
      PageParam(
        'experimentId',
        cli: 'experiment',
        kind: PageParamKind.string,
        required: true,
        help: 'The experiment identity.',
      ),
    ],
    wire: (r) => {
      ...pageTargetArgs(r.target),
      'experimentId': r.values['experimentId'],
      if (r.window case final window?) ...{
        'windowStartMicros': window.start,
        'windowEndExclusiveMicros': window.end,
      },
      'historyPageSize': _experimentHistoryPageSize,
    },
    render: renderExperimentResultsPage,
  ),
  PageRead(
    cliPath: 'delivery map',
    mcpName: 'restage_read_delivery_map',
    method: 'readDeliveryMapPage',
    summary: 'What is live where, and what builds painted.',
    mcpDescription:
        'Read the delivery map for one exact target and window: every '
        'placement, the surfaces its rules send requests to and the versions '
        'each serves, with routed requests and paints by app build. Routed '
        'counts are fresh resolutions the rules sent there, whatever was '
        'drawn; paints are what builds drew. A rule\'s split is exact from '
        'its policy. Flags name a build that cannot render a version, a '
        'build still painting a version no rule sends, or a destination '
        'requests reached and nothing painted. A count the service never '
        'measured reads unknown, never 0; a held count reads held. It also '
        'states each placement\'s schedule, where a rule carries its name '
        'when it has one, and fit by build, views by country, '
        'the release history with upcoming changes first, and surfaces no '
        'build has placed. Set allEnvironments to read every environment of '
        'the app. The reply carries both the placement and the surface '
        'grouping. The figures are the dashboard\'s own and are returned '
        'unchanged.',
    params: const [
      PageParam(
        'allEnvironments',
        cli: 'all-environments',
        kind: PageParamKind.flag,
        help: 'Every environment of the app.',
      ),
      PageParam(
        'placement',
        cli: 'placement',
        kind: PageParamKind.string,
        help:
            'Only this placement, as named:<slug> or '
            'default:<surface-type>:<slug>.',
      ),
      PageParam(
        'surfaceSlug',
        cli: 'surface',
        kind: PageParamKind.string,
        help: 'Only the placements that can show this surface.',
      ),
      PageParam(
        'by',
        cli: 'by',
        kind: PageParamKind.string,
        allowed: ['placement', 'surface'],
        cliOnly: true,
        help: 'Group by placement or by surface.',
      ),
    ],
    wire: (r) => {
      ...pageTargetArgs(r.target),
      ..._windowArgs(r),
      'allEnvironments': ?r.values['allEnvironments'],
      'placement': ?r.values['placement'],
      'surfaceSlug': ?r.values['surfaceSlug'],
    },
    render: (out, document) => renderDeliveryMapPage(out, document),
    renderFor: (out, document, values) => renderDeliveryMapPage(
      out,
      document,
      bySurface: values['by'] == 'surface',
    ),
  ),
  PageRead(
    cliPath: 'where',
    mcpName: 'restage_where',
    method: 'readDeliveryMapPage',
    summary: 'Every placement one surface serves.',
    mcpDescription:
        'Read where one surface, or one of its versions, is live across '
        'every environment of the app: each placement it serves, the rules '
        'that send requests to it, its routed requests and paints by app '
        'build, and its flags. Name the surface by slug, with @v and a '
        'version to narrow it, such as daily-check-in@v2. Counts and flags '
        'read as in the delivery map. The figures are the dashboard\'s own '
        'and are returned unchanged.',
    params: [
      PageParam(
        'surface',
        cli: 'surface',
        kind: PageParamKind.string,
        required: true,
        positional: true,
        parse: parseSurfaceVersion,
        help: 'The surface slug, with @v and a version to narrow it.',
      ),
    ],
    wire: (r) {
      final (:slug, :version) = r.values['surface']! as SurfaceVersionArg;
      return {
        ...pageTargetArgs(r.target),
        ..._windowArgs(r),
        'allEnvironments': true,
        'surfaceSlug': slug,
        'version': ?version,
      };
    },
    render: (out, document) => renderDeliveryMapPage(out, document),
    renderFor: (out, document, values) => renderDeliveryMapPage(
      out,
      document,
      bySurface: true,
      only: values['surface'] as SurfaceVersionArg?,
    ),
  ),
];

/// A surface named on the command line, with an optional version.
typedef SurfaceVersionArg = ({String slug, int? version});

/// Reads `slug` or `slug@version`.
SurfaceVersionArg parseSurfaceVersion(String value) {
  final at = value.indexOf('@');
  final slug = at < 0 ? value : value.substring(0, at);
  final named = at < 0 ? null : value.substring(at + 1);
  final version = named == null
      ? null
      : int.tryParse(named.startsWith('v') ? named.substring(1) : named);
  if (slug.isEmpty || (at >= 0 && (version == null || version < 1))) {
    throw const FormatException(
      'Name a surface as <slug> or <slug>@v<version>.',
    );
  }
  return (slug: slug, version: version);
}
