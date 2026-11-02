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

/// Complete v1 bundle, with inline components on createSurface.
List<Object?> sidecarMessages(
  String surfaceId,
  String catalogId,
  List<Map<String, Object?>> components,
) => [
  {
    'version': 'v1.0',
    'createSurface': {
      'surfaceId': surfaceId,
      'catalogId': catalogId,
      'components': components,
    },
  },
];

/// The shared graph exercises arbitrary single and list child inputs.
const goldenLessonComponents = <Map<String, Object?>>[
  {
    'id': 'root',
    'component': 'ComparisonPanel',

    'props_heading': 'Grammar showcase',
    'props_introduction': 'header',
    'props_examples': ['callout', 'quiz'],
    'props_conclusion': 'summary',
  },
  {
    'id': 'header',
    'component': 'SectionHeader',
    'props_title': 'Present tense',
  },
  {
    'id': 'callout',
    'component': 'Callout',
    'props_message': 'Watch the ending',
    'props_detail': 'callout_body',
  },
  {
    'id': 'callout_body',
    'component': 'SectionHeader',
    'props_title': 'Details',
  },
  {
    'id': 'quiz',
    'component': 'QuizCheck',
    'props_prompt': 'Is this right?',
    'props_selected': false,
  },
  {'id': 'summary', 'component': 'SectionHeader', 'props_title': 'Summary'},
];
