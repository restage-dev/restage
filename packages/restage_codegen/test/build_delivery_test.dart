import 'package:build/build.dart';
import 'package:restage_codegen/src/build_delivery.dart';
import 'package:test/test.dart';

void main() {
  test('reads the root options only, with the URL in canonical form', () {
    const config = {
      'api_key': ' rs_pk_x ',
      'base_url': 'https://a.example/',
      'channel': 'beta',
    };
    expect(
      readBuildDeliveryOptions(const BuilderOptions(config, isRoot: true)),
      (apiKey: 'rs_pk_x', baseUrl: 'https://a.example', channel: 'beta'),
    );
    expect(
      readBuildDeliveryOptions(const BuilderOptions(config)),
      (apiKey: null, baseUrl: null, channel: null),
    );
  });

  test('a key and URL make a delivery; either alone does not', () {
    expect(
      completeBuildDelivery((apiKey: 'k', baseUrl: 'u', channel: null)),
      (apiKey: 'k', baseUrl: 'u', channel: null),
    );
    expect(
      completeBuildDelivery((apiKey: 'k', baseUrl: null, channel: 'c')),
      isNull,
    );
    expect(
      completeBuildDelivery((apiKey: null, baseUrl: 'u', channel: null)),
      isNull,
    );
  });

  test('the build line names what is missing, with a Try', () {
    expect(
      missingBuildDeliveryLine((apiKey: 'k', baseUrl: 'u', channel: null)),
      isNull,
    );
    expect(
      missingBuildDeliveryLine((apiKey: null, baseUrl: null, channel: null)),
      "The first-launch request isn't built in: no publishable key. "
      'Try `restage init --sdk-key rs_pk_...`.',
    );
    expect(
      missingBuildDeliveryLine((apiKey: 'k', baseUrl: null, channel: null)),
      "The first-launch request isn't built in, and the app runs offline: "
      'no service URL. Try setting `base_url` next to `api_key` under '
      'restage_codegen:user_factories in build.yaml, for example '
      '`base_url: https://api.restage.dev`.',
    );
  });
}
