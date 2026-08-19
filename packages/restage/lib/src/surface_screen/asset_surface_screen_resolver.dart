import '../flow/flow_descriptors.dart';
import 'surface_screen_manifest.dart';
import 'surface_screen_types.dart';

/// Resolves an independently published screen from its generated asset closure.
final class AssetSurfaceScreenResolver implements BundledSurfaceScreenResolver {
  /// Creates the generated bundled-screen resolver.
  const AssetSurfaceScreenResolver();

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) async {
    final entry = await SurfaceScreenManifestRegistry.resolve(screen);
    return ResolvedSurfaceScreen.bundled(
      surface: entry.surface,
      slug: entry.slug,
      contractVersion: entry.contractVersion,
      sourceKind: entry.sourceKind,
      payloadKind: entry.payloadKind,
      capabilities: entry.capabilities,
      contractFingerprint: entry.contractFingerprint,
      eventContractHash: entry.eventContractHash,
      blob: entry.bundledBlob,
      contentHash: entry.contentHash,
    );
  }
}
