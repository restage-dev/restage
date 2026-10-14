import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/onboarding/flow_definition_frontend.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _screens = {
  'apps_examples|lib/message/screens/notice.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/notice.restage.g.dart';

@Screen()
final class NoticeScreen extends StatelessWidget {
  const NoticeScreen({super.key});

  static const done = SurfaceEvent<void>('done');
  static const privacy = SurfaceEvent<void>('privacy');
  static const share = SurfaceEvent<Map<String, Object?>>('share');

  @override
  Widget build(BuildContext context) => const Text('Notice');
}
''',
};

String _flow(String outbound) => '''
import 'package:restage/restage.dart';

import '../screens/notice.dart';

part 'restage.generated/notice_flow.restage.g.dart';

const seen = FlowStateRef<bool>('seen');

@FlowGraph(surface: Surface.message)
const noticeFlow = FlowDefinition(
  start: NoticeScreen,
  state: [seen],
  transitions: [Transition.complete(NoticeScreen.done)],
  outbound: FlowOutboundPolicy($outbound),
);
''';

void main() {
  group('compact flow custom events', () {
    test('emits declared custom events into the flow document', () async {
      final result = await _inspect(
        _flow(
          '''
    customEvents: {
      'privacy': FlowOutboundPayloadDeclaration(),
      'share': FlowOutboundPayloadDeclaration(
        fields: {
          'channel': FlowOutboundField(
            type: FlowDataType.string,
            ref: EventFlowOutboundRef(key: 'channel'),
          ),
        },
      ),
    },
''',
        ),
      );

      expect(result.issues, isEmpty, reason: _issues(result));
      final outbound = result.flows.single.graph!.outbound;
      expect(outbound.customEvents.keys, ['privacy', 'share']);
      expect(outbound.customEvents['privacy']!.fields, isEmpty);
      final channel = outbound.customEvents['share']!.fields['channel']!;
      expect(channel.type, FlowDataType.string);
      expect(channel.ref, isA<EventFlowOutboundRef>());
      expect(channel.ref.key, 'channel');

      final json = jsonDecode(
        utf8.decode(
          FlowDocumentCodec.encodeCanonicalJson(
            result.flows.single.graph!.toDocument({
              'notice': ScreenArtifact(
                path: 'notice.rfw',
                version: 1,
                schemaVersion: 1,
                minClient: 1,
                contentHash: FlowContentHash.parse('sha256:${'0' * 64}'),
              ),
            }),
          ),
        ),
      ) as Map<String, Object?>;
      expect(
        (json['outbound']! as Map<String, Object?>)['customEvents'],
        {
          'privacy': {'fields': <String, Object?>{}},
          'share': {
            'fields': {
              'channel': {
                'ref': {'event': 'channel'},
                'type': 'string',
              },
            },
          },
        },
      );
    });

    test('omits custom events by default', () async {
      final result = await _inspect(_flow(''));

      expect(result.issues, isEmpty, reason: _issues(result));
      expect(result.flows.single.graph!.outbound.customEvents, isEmpty);
    });

    test('refuses a duplicate event name as the builder form does', () async {
      final result = await _inspect(
        _flow(
          '''
    customEvents: {
      'privacy': FlowOutboundPayloadDeclaration(),
      'privacy': FlowOutboundPayloadDeclaration(),
    },
''',
        ),
      );

      expect(
        _issues(result),
        contains('unsupported outbound declaration: duplicate outbound '
            "declaration key 'privacy'."),
      );
    });

    test('refuses a non-literal event name as the builder form does', () async {
      final result = await _inspect(
        _flow(
          '''
    customEvents: {
      NoticeScreen.privacy: FlowOutboundPayloadDeclaration(),
    },
''',
        ),
      );

      expect(
        _issues(result),
        contains('unsupported outbound declaration: outbound declaration map '
            'keys must be string literals.'),
      );
    });

    test('refuses an event name that is not an identifier', () async {
      final result = await _inspect(
        _flow(
          '''
    customEvents: {
      'open privacy': FlowOutboundPayloadDeclaration(),
    },
''',
        ),
      );

      expect(_issues(result), contains('invalidIdentifier'));
    });

    test('refuses a field that reads flow state', () async {
      final result = await _inspect(
        _flow(
          '''
    customEvents: {
      'privacy': FlowOutboundPayloadDeclaration(
        fields: {
          'seen': FlowOutboundField(
            type: FlowDataType.bool,
            ref: StateFlowOutboundRef(key: 'seen'),
          ),
        },
      ),
    },
''',
        ),
      );

      expect(
        _issues(result),
        contains('customEventStateRef'),
      );
    });
  });
}

Future<FlowFrontendResult> _inspect(String flowSource) async {
  const target = 'lib/message/flows/notice_flow.dart';
  final sources = {
    ..._screens,
    'apps_examples|$target': flowSource,
  };
  final writer = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  for (final entry in sources.entries) {
    writer.testing.writeString(AssetId.parse(entry.key), entry.value);
  }

  FlowFrontendResult? inspected;
  await testBuilder(
    _ProbeBuilder((library, assetId) async {
      if (assetId.path != target) return;
      inspected = await inspectFlowDefinitions(library, assetId);
    }),
    sources,
    rootPackage: 'apps_examples',
    readerWriter: writer,
  );
  return inspected ?? (throw StateError('No frontend result for $target'));
}

String _issues(FlowFrontendResult result) =>
    result.issues.map((issue) => '${issue.code}: ${issue.message}').join('\n');

final class _ProbeBuilder implements Builder {
  _ProbeBuilder(this.onLibrary);

  final Future<void> Function(LibraryElement library, AssetId assetId)
      onLibrary;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.flow_definition_custom_events_probe'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    await onLibrary(await buildStep.inputLibrary, buildStep.inputId);
  }
}
