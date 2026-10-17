import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  test('a screen publication line digest is pinned', () {
    expect(
      publicationLineDigestV1(
        surface: 'onboarding',
        slug: 'welcome',
        sourceKind: 'screen',
        contractVersion: 3,
      ),
      'bfed7da133b84d189bc2d3b64c745954f9450f43873c505dd2a4652943b60a25',
    );
  });

  test('a flow publication line digest is pinned', () {
    expect(
      publicationLineDigestV1(
        surface: 'survey',
        slug: 'nps',
        sourceKind: 'flowGraph',
      ),
      'a63ae3f1853fc1fff53c4e9f9a28fffb4f68cb86b0eb8901a8a9befed138c504',
    );
  });

  test('artifact definition digests are pinned', () {
    expect(
      artifactDefinitionDigestV1(
        surface: 'onboarding',
        slug: 'welcome',
        sourceKind: 'screen',
        contractVersion: 3,
        artifactRole: 'screenBlob',
        artifactId: 'intro',
      ),
      '88172739cd2768280be92c66176283d1fd502a2ba1da247f37650fc97597f3fc',
    );
    expect(
      artifactDefinitionDigestV1(
        surface: 'survey',
        slug: 'nps',
        sourceKind: 'flowGraph',
        artifactRole: 'flowDocument',
      ),
      '3649c020fa617ca3601bd80fdb7671a98c8b8c0d351d127601083892d8f34f56',
    );
  });

  test('the declared artifact bytes digest is pinned', () {
    expect(
      declaredArtifactBytesDigestV1([
        {'contentHash': 'sha256:${'a' * 64}', 'path': 'lib/x.rfw'},
        {'path': 'lib/y.json', 'contentHash': 'sha256:${'b' * 64}'},
      ]),
      'eb3b8fe37c516a2d1b5920a593e604a5b9cec6604b4b270cb52fcacf9af075db',
    );
  });
}
