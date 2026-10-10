import 'package:restage_cli/src/api/discovery_api.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/config/restage_config.dart';

/// What [checkConfigTarget] found.
typedef ConfigTargetCheck = ({
  List<String> problems,
  OrganizationSummary? organization,
});

/// Check that the organization, project, app and environment [config] names
/// exist for the signed-in account. Returns one sentence per problem, naming
/// what does exist, and the organization the project resolves in.
Future<ConfigTargetCheck> checkConfigTarget(
  DiscoveryApi discovery,
  RestageConfig config, {
  SelectorSyntax? syntax,
}) async {
  syntax ??= currentSelectorSyntax;
  final project = config.project;
  final app = config.app;
  if (project == null || app == null) {
    return (
      problems: [
        if (project == null) missingConfigKeySentence('project', syntax),
        if (app == null) missingConfigKeySentence('app', syntax),
      ],
      organization: null,
    );
  }
  final organizations = await discovery.listOrganizations();
  if (organizations.isEmpty) {
    return (
      problems: const ['No organizations found for this account.'],
      organization: null,
    );
  }
  final problems = <String>[];
  final configured = config.organization;
  final List<OrganizationSummary> candidates;
  if (configured != null && configured.isNotEmpty) {
    candidates = [
      for (final organization in organizations)
        if (organization.slug == configured) organization,
    ];
    if (candidates.isEmpty) {
      return (
        problems: [
          'restage_config.yaml names organization `$configured`, which is '
              'not one of yours. Your organizations: '
              '${_organizationList(organizations)}.',
        ],
        organization: null,
      );
    }
  } else {
    candidates = organizations;
  }

  final withProject = <OrganizationSummary>[];
  final projectsByOrganization = <OrganizationSummary, List<String>>{};
  for (final organization in candidates) {
    final projects = await discovery.listProjects(organization.organizationId);
    projectsByOrganization[organization] = [
      for (final project in projects) project.slug,
    ];
    if (projects.any((candidate) => candidate.slug == project)) {
      withProject.add(organization);
    }
  }

  if (candidates.length > 1 && withProject.length != 1) {
    problems.add(ambiguousOrganizationSentence(organizations, syntax));
  }
  if (withProject.isEmpty) {
    problems.add(
      'restage_config.yaml names project `$project`, which does not '
      'exist in ${_where(candidates)}. Projects: '
      '${_perOrganization(projectsByOrganization)}.',
    );
    return (problems: problems, organization: null);
  }
  if (withProject.length > 1) return (problems: problems, organization: null);

  final organization = withProject.single;
  final apps = await discovery.listApps(
    organizationId: organization.organizationId,
    projectSlug: project,
  );
  if (!apps.any((candidate) => candidate.slug == app)) {
    problems.add(
      'restage_config.yaml names app `$app`, which does not exist in '
      'project `$project` of `${organization.slug}`. Apps there: '
      '${_list([for (final app in apps) app.slug])}.',
    );
  }
  final environment = config.defaultEnvironment;
  if (environment != null && environment.isNotEmpty) {
    final environments = await discovery.listEnvironments(
      organizationId: organization.organizationId,
      projectSlug: project,
    );
    final slugs = {for (final environment in environments) environment.slug};
    if (!slugs.contains(environment)) {
      problems.add(
        'restage_config.yaml names environment `$environment`, which does '
        'not exist in project `$project`. Environments there: '
        '${_list(slugs.toList()..sort())}.',
      );
    }
  }
  return (problems: problems, organization: organization);
}

/// What [checkConfigTarget] confirmed for [config] when it found no problem.
String configTargetConfirmed(RestageConfig config) {
  final environment = config.defaultEnvironment;
  return environment == null || environment.isEmpty
      ? 'project `${config.project}` and app `${config.app}` exist'
      : 'project `${config.project}`, app `${config.app}` and environment '
            '`$environment` exist';
}

/// The sentence for an account in several organizations when nothing names
/// one: which exist, and how to choose.
String ambiguousOrganizationSentence(
  List<OrganizationSummary> organizations, [
  SelectorSyntax? syntax,
]) {
  syntax ??= currentSelectorSyntax;
  return 'You belong to ${organizations.length} organizations: '
      '${_organizationList(organizations)}. Set `organization: <slug>` in '
      'restage_config.yaml, or pass ${syntax.organization} on each call.';
}

String _organizationList(List<OrganizationSummary> organizations) =>
    organizations
        .map((organization) {
          return '${organization.slug} (id ${organization.organizationId})';
        })
        .join(', ');

String _where(List<OrganizationSummary> organizations) =>
    organizations.length == 1
    ? '`${organizations.single.slug}`'
    : 'any of your organizations';

String _perOrganization(Map<OrganizationSummary, List<String>> projects) =>
    projects.length == 1
    ? _list(projects.values.single)
    : [
        for (final MapEntry(key: organization, value: slugs)
            in projects.entries)
          '${_list(slugs)} in `${organization.slug}`',
      ].join('; ');

String _list(List<String> slugs) =>
    slugs.isEmpty ? 'none' : slugs.map((slug) => '`$slug`').join(', ');
