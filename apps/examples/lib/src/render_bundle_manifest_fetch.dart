import 'dart:typed_data';

/// Exact browser request used to load the immutable bundle manifest sidecar.
final class RenderBundleManifestFetchRequest {
  const RenderBundleManifestFetchRequest({required this.uri});

  final Uri uri;
  final String method = 'GET';
  final String credentials = 'same-origin';
  final String cache = 'no-store';
  final String mode = 'same-origin';
  final String redirect = 'error';
}

typedef RenderBundleManifestFetchResponse = ({
  int status,
  Uint8List bytes,
});

typedef RenderBundleManifestFetcher = Future<RenderBundleManifestFetchResponse>
    Function(
  RenderBundleManifestFetchRequest request,
);
