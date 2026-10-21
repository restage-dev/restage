/// The published Restage documentation.
const defaultDocsOrigin = 'https://docs.restage.dev';

final _cloudApiHost = RegExp(r'^api((?:-[a-z0-9]+)*)\.restage\.dev$');

/// The docs and dashboard that belong to the backend at [endpoint].
///
/// A Restage Cloud API at `api<suffix>.restage.dev` pairs with
/// `docs<suffix>.restage.dev` and `app<suffix>.restage.dev`. Any other server
/// reads the published docs and has no known dashboard.
({String docs, String? dashboard}) backendSites(Uri endpoint) {
  final match = _cloudApiHost.firstMatch(endpoint.host);
  if (match == null || endpoint.scheme != 'https') {
    return (docs: defaultDocsOrigin, dashboard: null);
  }
  final suffix = match.group(1)!;
  return (
    docs: 'https://docs$suffix.restage.dev',
    dashboard: 'https://app$suffix.restage.dev',
  );
}
