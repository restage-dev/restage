import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/hosted_measurement_construction_profile_read_port.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

void main() {
  for (final (privacy, budget, classification, collection, session) in [
    (
      'restage.manifest-privacy.v1',
      'restage.collection-budget.v2',
      privacyClassificationRevisionId,
      true,
      false
    ),
    (
      'restage.manifest-privacy.v2',
      'restage.collection-budget.v3',
      privacyClassificationRevisionId,
      true,
      true
    ),
    (
      'restage.manifest-privacy.v4',
      'restage.collection-budget.v5',
      privacyClassificationRevisionId,
      true,
      true
    ),
    (
      'restage.manifest-privacy.v1',
      'restage.collection-budget.v1',
      privacyClassificationRevisionId,
      false,
      false
    ),
    (
      'restage.something-else.v9',
      'restage.collection-budget.v5',
      privacyClassificationRevisionId,
      false,
      false
    ),
    (
      'restage.manifest-privacy.vnext',
      'restage.collection-budget.v5',
      privacyClassificationRevisionId,
      false,
      false
    ),
    (
      'restage.manifest-privacy.v0',
      'restage.collection-budget.v5',
      privacyClassificationRevisionId,
      false,
      false
    ),
    (
      'restage.manifest-privacy.v',
      'restage.collection-budget.v5',
      privacyClassificationRevisionId,
      false,
      false
    ),
    (
      'restage.manifest-privacy.v01',
      'restage.collection-budget.v5',
      privacyClassificationRevisionId,
      false,
      false
    ),
    (
      'restage.manifest-privacy.v4',
      'restage.collection-budget.v5',
      'restage.privacy-classification.v2',
      false,
      false
    ),
  ]) {
    test('$privacy / $budget / $classification floor rules', () {
      final collectionAdmitted = measurementCollectionAdmittedByPolicy(
        privacyPolicyRevisionId: privacy,
        collectionBudgetRevisionId: budget,
        classificationRevisionId: classification,
      );
      final sessionAdmitted = collectionAdmitted &&
          sdkRuntimeSessionAdmittedByPolicy(
            privacyPolicyRevisionId: privacy,
            collectionBudgetRevisionId: budget,
          );
      expect(collectionAdmitted, collection);
      expect(sessionAdmitted, session);
    });
  }
}
