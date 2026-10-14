import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart'
    show decodeLibraryBlob, encodeLibraryBlob, parseLibraryFile;
import 'package:test/test.dart';

Uint8List _library(String source) =>
    encodeLibraryBlob(parseLibraryFile(source));

BlobSurfacePayload _draft(Uint8List blob, {Uint8List? editorState}) =>
    BlobSurfacePayload(
      minClient: kBaselineCatalogVersion,
      blob: blob,
      requiredLibraries: const [
        LibraryRequirement(namespace: 'app.widgets', minVersion: 2),
      ],
      editorState: editorState,
    );

FlowSurfacePayload _flowDraft(
  Map<String, Uint8List> screens, {
  Uint8List? editorState,
}) {
  final ids = screens.keys.toList();
  return FlowSurfacePayload(
    flowDocument: FlowDocument(
      flow: 'tour',
      version: 1,
      schemaVersion: 1,
      minClient: 1,
      initial: ids.first,
      screenArtifacts: {
        for (final id in ids)
          id: ScreenArtifact(
            path: '$id.rfw',
            version: 1,
            schemaVersion: 1,
            minClient: 1,
            contentHash: FlowContentHash.compute(screens[id]!),
          ),
      },
      states: {
        for (var i = 0; i < ids.length; i++)
          ids[i]: ScreenFlowState(
            screen: ids[i],
            on: {
              'act': FlowTransition.goto(
                i + 1 < ids.length ? ids[i + 1] : 'done',
              ),
            },
          ),
        'done': const EndFlowState(result: {}),
      },
    ),
    screenBlobs: screens,
    editorState: editorState,
  );
}

void main() {
  final editorState = SurfaceEditorState(
    meta: const <String, Object?>{'k': 1},
  ).encode();

  test('drops editor state and parked components, keeps the envelope', () {
    final draft = _draft(
      _library('''
import core;
widget main = Column(children: [card()]);
widget card = Text(text: "Hi");
widget parked = Text(text: "Unused");
'''),
      editorState: editorState,
    );

    final published = publishableDraftPayload(draft) as BlobSurfacePayload;

    expect(published.editorState, isNull);
    expect(
      decodeLibraryBlob(published.blob).widgets.map((w) => w.name),
      ['main', 'card'],
    );
    expect(published.minClient, draft.minClient);
    expect(published.requiredLibraries, draft.requiredLibraries);
    expect(draft.editorState, editorState);
    expect(
      decodeLibraryBlob(draft.blob).widgets.map((w) => w.name),
      contains('parked'),
    );
  });

  test('a code-written draft with nothing to trim is unchanged', () {
    final draft =
        _draft(_library('import core;\nwidget Paywall = Text(text: "A");'));
    expect(identical(publishableDraftPayload(draft), draft), isTrue);
  });

  test('editor state alone is removed byte for byte', () {
    final plain =
        _draft(_library('import core;\nwidget Paywall = Text(text: "A");'));
    final withState = _draft(plain.blob, editorState: editorState);
    expect(
      publishableDraftPayload(withState).canonicalBytes,
      plain.canonicalBytes,
    );
  });

  test('a flow drops editor state and trims each screen, rebinding hashes', () {
    final plain = _library(
      'import core;\nwidget OnboardingScreen = Text(text: "A");',
    );
    final parked = _library('''
import core;
widget OnboardingScreen = Text(text: "B");
widget component_1 = Text(text: "Unused");
''');
    final draft = _flowDraft(
      {'a': plain, 'b': parked},
      editorState: editorState,
    );

    final published = publishableDraftPayload(draft) as FlowSurfacePayload;

    expect(published.editorState, isNull);
    expect(published.screenBlobs['a'], plain);
    expect(
      decodeLibraryBlob(published.screenBlobs['b']!).widgets.map((w) => w.name),
      ['OnboardingScreen'],
    );
    expect(
      published.flowDocument.screenArtifacts['b']!.contentHash,
      FlowContentHash.compute(published.screenBlobs['b']!),
    );
    expect(
      published.flowDocument.screenArtifacts['a']!.contentHash,
      draft.flowDocument.screenArtifacts['a']!.contentHash,
    );
  });

  test('a flow with nothing to strip or trim is unchanged', () {
    final draft = _flowDraft({
      'a': _library('import core;\nwidget OnboardingScreen = Text(text: "A");'),
    });
    expect(identical(publishableDraftPayload(draft), draft), isTrue);
  });

  test('a library with no recognizable root is left whole', () {
    final draft = _draft(
      _library('import core;\nwidget a = Text(text: "A");\nwidget b = a();'),
    );
    expect(identical(publishableDraftPayload(draft), draft), isTrue);
  });

  test('a generated screen with an inlined widget trims parked components', () {
    final draft = _draft(
      _library('''
import core;
widget OnboardingScreen = Column(children: [StatBadge()]);
widget StatBadge = Text(text: "7");
widget component_1 = Text(text: "Unused");
'''),
    );
    final published = publishableDraftPayload(draft) as BlobSurfacePayload;
    expect(
      decodeLibraryBlob(published.blob).widgets.map((w) => w.name),
      ['OnboardingScreen', 'StatBadge'],
    );
  });

  test(
      'the root is main, else Paywall, else OnboardingScreen, else the '
      'single declaration', () {
    expect(surfaceRootWidgetName(['card', 'main', 'Paywall']), 'main');
    expect(surfaceRootWidgetName(['Paywall', 'card']), 'Paywall');
    expect(
      surfaceRootWidgetName(['DayTile', 'HabitRow', 'OnboardingScreen']),
      'OnboardingScreen',
    );
    expect(surfaceRootWidgetName(['Paywall', 'OnboardingScreen']), 'Paywall');
    expect(surfaceRootWidgetName(['Custom']), 'Custom');
    expect(surfaceRootWidgetName(['Custom', 'component_1']), isNull);
    expect(surfaceRootWidgetName(['Paywall', 'Paywall']), isNull);
    expect(
      () => surfaceRootWidgetName(['main', 'main']),
      throwsFormatException,
    );
  });

  test('adding a declaration never moves a named root', () {
    for (final root in kSurfaceRootWidgetNames) {
      expect(surfaceRootWidgetName([root]), root);
      expect(surfaceRootWidgetName([root, 'component_1']), root);
      expect(surfaceRootWidgetName(['component_1', root, 'component_2']), root);
    }
  });
}
