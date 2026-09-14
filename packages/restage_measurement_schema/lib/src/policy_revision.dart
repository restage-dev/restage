/// The revision number a policy id names within [family], or null when the id
/// does not belong to that family or is not a numbered revision of it.
int? policyRevisionWithinFamily(String id, String family) {
  final prefix = '$family.v';
  if (!id.startsWith(prefix)) return null;
  final suffix = id.substring(prefix.length);
  if (!_revisionNumber.hasMatch(suffix)) return null;
  return int.tryParse(suffix);
}

/// Whether [id] names a revision of [family] at or above [floor].
bool policyRevisionAtOrAbove(String id, String family, int floor) {
  final revision = policyRevisionWithinFamily(id, family);
  return revision != null && revision >= floor;
}

final RegExp _revisionNumber = RegExp(r'^[1-9][0-9]*$');

/// The recognized manifest privacy policy family.
const String manifestPrivacyPolicyFamily = 'restage.manifest-privacy';

/// The recognized collection budget family.
const String collectionBudgetFamily = 'restage.collection-budget';

/// The minimum manifest privacy revision for collection.
const int collectionPrivacyPolicyFloor = 1;

/// The minimum collection budget revision for collection.
const int collectionBudgetPolicyFloor = 2;

/// The minimum manifest privacy revision for SDK sessions.
const int sdkSessionPrivacyPolicyFloor = 2;

/// The minimum collection budget revision for SDK sessions.
const int sdkSessionCollectionBudgetFloor = 3;

/// The minimum manifest privacy revision for presentation metadata.
const int presentationMetadataPrivacyPolicyFloor = 3;

/// The minimum collection budget revision for presentation metadata.
const int presentationMetadataCollectionBudgetFloor = 3;

/// The single recognized privacy classification revision.
const String privacyClassificationRevisionId =
    'restage.privacy-classification.v1';
