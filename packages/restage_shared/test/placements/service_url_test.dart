import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  test('a service URL has one canonical form', () {
    for (final url in [
      'https://api.example.com',
      'https://api.example.com/',
      ' https://api.example.com// ',
    ]) {
      expect(canonicalServiceUrl(url), 'https://api.example.com');
      expect(
        placementResolveUrl(url).toString(),
        'https://api.example.com/sdk/v1/placements/resolve',
      );
    }
    expect(
        canonicalServiceUrl('https://x.example/api/'), 'https://x.example/api');
    expect(canonicalServiceUrl(' / '), '');
  });
}
