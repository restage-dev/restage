import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  ({String docs, String? dashboard}) sites(String endpoint) =>
      backendSites(Uri.parse(endpoint));

  test('Restage Cloud pairs with the published docs and dashboard', () {
    final cloud = sites('https://api.restage.dev/');
    expect(cloud.docs, 'https://docs.restage.dev');
    expect(cloud.dashboard, 'https://app.restage.dev');
  });

  test('a suffixed Cloud API pairs with the same suffix', () {
    final preview = sites('https://api-preview.restage.dev');
    expect(preview.docs, 'https://docs-preview.restage.dev');
    expect(preview.dashboard, 'https://app-preview.restage.dev');
  });

  test('any other server reads the published docs', () {
    for (final endpoint in [
      'https://api.example.com/',
      'https://api.restage.dev.example.com/',
      'http://api.restage.dev/',
      'http://localhost:8080/',
    ]) {
      final other = sites(endpoint);
      expect(other.docs, 'https://docs.restage.dev', reason: endpoint);
      expect(other.dashboard, isNull, reason: endpoint);
    }
  });
}
