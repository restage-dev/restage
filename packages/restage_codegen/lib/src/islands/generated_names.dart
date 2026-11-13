// The `_restage` names generated surface code declares, so an author's own
// `_restage` name collides only when it is one of them.

const Set<String> _generatedNames = {
  '_restage',
  '_restageAnalytics',
  '_restageApiKey',
  '_restageArg',
  '_restageArgs',
  '_restageArgument',
  '_restageBaseUrl',
  '_restageBinding',
  '_restageBindings',
  '_restageBody',
  '_restageBuild',
  '_restageBuilt',
  '_restageChannel',
  '_restageChild',
  '_restageConfigureSource',
  '_restageContext',
  '_restageDeliveryKeys',
  '_restageDesign',
  '_restageDidUpdateWidget',
  '_restageIsland',
  '_restageItem',
  '_restageLibraryOrigin',
  '_restageOldWidget',
  '_restageOrigin',
  '_restageOriginal',
  '_restagePackages',
  '_restagePlacementName',
  '_restagePresent',
  '_restagePrevious',
  '_restageRecording',
  '_restageRender',
  '_restageRuntimePrefix',
  '_restageRuntimeUri',
  '_restageSdkOrigin',
  '_restageSdkVersion',
  '_restageSharedOrigin',
  '_restageSheet',
  '_restageSlotRecording',
  '_restageSource',
  '_restageStepOwner',
  '_restageStepWidget',
  '_restageStored',
  '_restageSurface',
  '_restageSurfaces',
  '_restageTop',
  '_restageTopC',
  '_restageTopG',
  '_restageWidget',
};

// Stems the generators complete with an argument, item or sheet name.
const List<String> _generatedStems = [
  '_restageA2ui',
  '_restageArg',
  '_restageItem',
  '_restagePresent',
  '_restageSheet',
  '_restageStored',
  '_restage_',
];

final RegExp _allocatedSuffix = RegExp(r'\d+$');
final RegExp _mountMember = RegExp(r'^_restage[A-Z]\w*(Contract|Native)$');

/// Whether generated surface code can declare [name].
bool isGeneratedRestageName(String name) {
  if (!name.startsWith('_restage')) return false;
  final stem = name.replaceFirst(_allocatedSuffix, '');
  return _generatedNames.contains(stem) ||
      name.contains(r'$') ||
      _generatedStems.any(name.startsWith) ||
      _mountMember.hasMatch(stem);
}
