/// Most bytes a render bundle's capability manifest may hold. The manifest
/// carries the app's merged widget catalog, built-ins included.
const int renderBundleMaxCapabilityManifestBytes = 1024 * 1024;

/// Most JSON nodes a render bundle's capability manifest may hold, sized well
/// above the built-in catalogs.
const int renderBundleMaxCapabilityManifestNodes = 100000;
