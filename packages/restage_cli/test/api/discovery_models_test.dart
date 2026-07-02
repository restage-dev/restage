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
}
