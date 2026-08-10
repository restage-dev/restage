import 'dart:convert';
import 'dart:io';

/// Shared support for the A2UI full-chain proofs. Keeps the generated-artifact
/// path, the A2UI envelope shape, and the golden component graph in ONE place so
/// the render proof and the structural-sufficiency proof cannot drift.

/// The committed A2UI structural stamp path (test cwd = package root). A single
/// definition so a generated-artifact rename touches exactly one line.
const stampPath = 'lib/generated/restage_a2ui_catalog.a2ui.json';

/// Reads + decodes the committed structural stamp.
Map<String, Object?> readStamp() =>
    jsonDecode(File(stampPath).readAsStringSync()) as Map<String, Object?>;

/// Wraps a flat [components] list in the two-message A2UI envelope the render
/// proofs feed to genui — an `updateComponents` carrying the components, then a
/// `createSurface` — in genui's v0.9 wire shape.
List<Object?> sidecarMessages(
  String surfaceId,
  String catalogId,
  List<Map<String, Object?>> components,
) => [
  {
    'version': 'v0.9',
    'updateComponents': {'surfaceId': surfaceId, 'components': components},
  },
  {
    'version': 'v0.9',
    'createSurface': {'surfaceId': surfaceId, 'catalogId': catalogId},
  },
];

/// The golden happy-path component graph the full-surface render proof renders.
/// Every component keeps protocol-owned `id`/`component` at the envelope and
/// nests its exact constructor inputs under the required `props` object. The
/// `ComparisonPanel` exercises three independently named child-bearing inputs;
/// `Callout.detail` proves the same rule on another component. The structural-
/// sufficiency proof derives its authorable-property set from THIS list, so the
/// two proofs cannot drift.
const goldenLessonComponents = <Map<String, Object?>>[
  {
    'id': 'root',
    'component': 'ComparisonPanel',
    'props': {
      'heading': 'Grammar showcase',
      'introduction': 'header',
      'examples': ['callout', 'quiz'],
      'conclusion': 'summary',
    },
  },
  {
    'id': 'header',
    'component': 'SectionHeader',
    'props': {'title': 'Present tense'},
  },
  {
    'id': 'callout',
    'component': 'Callout',
    'props': {'message': 'Watch the ending', 'detail': 'callout-body'},
  },
  {
    'id': 'callout-body',
    'component': 'SectionHeader',
    'props': {'title': 'Details'},
  },
  {
    'id': 'quiz',
    'component': 'QuizCheck',
    'props': {'prompt': 'Is this right?', 'selected': false},
  },
  {
    'id': 'summary',
    'component': 'SectionHeader',
    'props': {'title': 'Summary'},
  },
];
