import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:test/test.dart';

void main() {
  test('OrganizationSummary.fromJson decodes id + slug + name', () {
    final organization = OrganizationSummary.fromJson({
      'organizationId': 7,
      'slug': 'default',
      'name': 'Default',
      'role': 'owner',
      '__className__': 'OrganizationMembershipView',
    });

    expect(organization.organizationId, 7);
    expect(organization.slug, 'default');
    expect(organization.name, 'Default');
  });

  test(
    'ProjectSummary / AppSummary decode slug + name; Environment slug only',
    () {
      expect(ProjectSummary.fromJson({'slug': 'p', 'name': 'P'}).slug, 'p');
      expect(AppSummary.fromJson({'slug': 'a', 'name': 'A'}).name, 'A');
      expect(EnvironmentSummary.fromJson({'slug': 'staging'}).slug, 'staging');
    },
  );

  test('WorkspaceExperienceSummary decodes only status-safe fields', () {
    final workspace = WorkspaceExperienceSummary.fromJson({
      'organizationId': 7,
      'provenance': 'sample',
      'sampleGeneration': 3,
      'seedVersion': 'northwind-v1',
      'hostedAccessState': 'sandbox',
      'productionAllowed': false,
      'canRequestProduction': false,
      'canResetSample': true,
      'canDeleteSample': true,
      'pairedOrganizationId': 8,
      'futureServerField': 'ignored',
    });

    expect(workspace.organizationId, 7);
    expect(workspace.provenance, 'sample');
    expect(workspace.hostedAccessState, 'sandbox');
    expect(workspace.productionAllowed, isFalse);
  });

  test('EnvironmentTargetSummary decodes the exact target coordinate', () {
    final target = EnvironmentTargetSummary.fromJson({
      'environmentTargetId': 42,
      'namedEnvironmentId': 9,
      'environmentSlug': 'production',
      'runtimePlane': 'sandbox',
      '__className__': 'EnvironmentTargetRef',
    });

    expect(target.environmentTargetId, 42);
    expect(target.namedEnvironmentId, 9);
    expect(target.environmentSlug, 'production');
    expect(target.runtimePlane, RuntimePlane.sandbox);
  });
}
