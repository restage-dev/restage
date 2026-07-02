import 'package:restage_cli/src/api/discovery_api.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/io/interactive.dart';

/// Resolve which organization the command should operate in.
///
/// Returns null after writing a user-facing error when the organization cannot
/// be resolved without prompting in non-interactive mode.
Future<OrganizationSummary?> resolveActiveOrganization({
  required DiscoveryApi api,
  required Interactive interactive,
  required StringSink stderr,
  String? preferredSlug,
}) async {
  final organizations = await api.listOrganizations();
  if (organizations.isEmpty) {
    stderr.writeln('No organizations found for this account.');
    return null;
  }
  if (preferredSlug != null && preferredSlug.isNotEmpty) {
    for (final organization in organizations) {
      if (organization.slug == preferredSlug) return organization;
    }
    stderr.writeln(
      'No organization found for --organization <slug>: $preferredSlug.',
    );
    return null;
  }
  if (organizations.length == 1) return organizations.single;
  if (!interactive.isInteractive) {
    stderr.writeln(
      'You belong to multiple organizations. Pass --organization <slug>.',
    );
    return null;
  }
  return interactive.select<OrganizationSummary>('Which organization?', [
    for (final organization in organizations)
      (
        label: '${organization.name} (${organization.slug})',
        value: organization,
      ),
  ]);
}

/// Auto-select a sole option, otherwise ask the user to pick one.
///
/// Returns null after writing a user-facing error when the value cannot be
/// resolved without prompting in non-interactive mode.
Future<T?> pickOne<T>({
  required Interactive interactive,
  required StringSink stderr,
  required String prompt,
  required List<({String label, T value})> options,
  required String missingFlag,
  String? emptyMessage,
  bool allowEmpty = false,
}) async {
  if (options.isEmpty) {
    if (allowEmpty) return null;
    stderr.writeln(emptyMessage ?? 'Nothing to choose from for "$prompt".');
    return null;
  }
  if (options.length == 1) return options.single.value;
  if (!interactive.isInteractive) {
    stderr.writeln('Multiple options. Pass $missingFlag.');
    return null;
  }
  return interactive.select<T>(prompt, options);
}
