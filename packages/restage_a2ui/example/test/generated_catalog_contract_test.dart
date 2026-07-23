import 'dart:async';
import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart'
    show CreateSurfaceMessage, UpdateComponentsMessage;
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:restage_a2ui_example/restage_a2ui_catalog.g.dart';

import 'a2ui_proof_support.dart';

Map<String, Object?> _standaloneCatalog() =>
    (readStamp()['a2uiCatalog']! as Map).cast<String, Object?>();

Map<String, Object?> _objectAt(Map<String, Object?> object, String key) =>
    (object[key]! as Map).cast<String, Object?>();

/// Removes ONLY the exact default-elision `additionalProperties: true`,
/// recursively, leaving every other key — including a schema-valued
/// `additionalProperties` (e.g. a typed map) — untouched for deep equality.
///
/// json_schema_builder 0.1.6 serializes the JSON-schema DEFAULT
/// (`additionalProperties: true`) explicitly on `Schema.value` at RUNTIME,
/// whereas the build-time emitter that writes the standalone `.a2ui.json`
/// document omits it. An absent `additionalProperties` IS `true`, so the two are
/// structurally identical; this drops only that one default so the runtime
/// catalog and the emitted document compare equal on everything else.
Object? _normalizeSchema(Object? node) {
  if (node is Map) {
    return <String, Object?>{
      for (final entry in node.entries)
        if (!(entry.key == 'additionalProperties' && entry.value == true))
          entry.key as String: _normalizeSchema(entry.value),
    };
  }
  if (node is List) return node.map(_normalizeSchema).toList();
  return node;
}

void _expectDescription(Map<String, Object?> object, String description) {
  expect(object['description'], description);
}

void main() {
  test(
    'generated runtime identity and schemas equal the standalone document',
    () {
      final catalog = buildRestageCatalog();
      final standalone = _standaloneCatalog();
      final standaloneComponents = _objectAt(standalone, 'components');
      final generatedItems = {
        for (final item in catalog.items) item.name: item,
      };

      expect(restageA2uiCatalogId, catalog.catalogId);
      expect(catalog.catalogId, standalone[r'$id']);
      expect(catalog.catalogId, standalone['catalogId']);
      expect(
        restageA2uiCatalogId,
        matches(RegExp(r'^restage:catalog/sha256/[0-9a-f]{64}$')),
      );
      expect(standaloneComponents.keys.toSet(), generatedItems.keys.toSet());
      for (final entry in generatedItems.entries) {
        expect(
          _normalizeSchema(entry.value.dataSchema.value),
          _normalizeSchema(standaloneComponents[entry.key]),
          reason: '${entry.key}: generated and standalone schemas must match',
        );
      }
    },
  );

  test(
    'the real prompt and conversation handoff carries one exact catalog ID',
    () async {
      final catalog = buildRestageCatalog();
      final prompt = PromptBuilder.chat(catalog: catalog).systemPromptJoined();
      // GenUI 0.10.1 no longer embeds `a2uiMessageSchema(catalog)` verbatim in
      // the system prompt (it builds the CATALOG SCHEMA / MESSAGE SCHEMA
      // sections from `catalog.fullSchema` + the embedded server-to-client
      // schema). Assert the load-bearing producer contract by shape instead:
      // the content-derived catalog ID and the component vocabulary are carried.
      expect(prompt, contains(restageA2uiCatalogId));
      expect(prompt, contains('ProductCard'));

      ChatMessage? captured;
      final transport = A2uiTransportAdapter(
        onSend: (message) async => captured = message,
      );
      final controller = SurfaceController(catalogs: [catalog]);
      final conversation = Conversation(
        controller: controller,
        transport: transport,
      );
      addTearDown(() {
        conversation.dispose();
        transport.dispose();
        controller.dispose();
      });

      final outbound = ChatMessage.system(prompt);
      await conversation.sendRequest(outbound);

      expect(captured, same(outbound));
      expect(captured!.role, ChatMessageRole.system);
      expect(captured!.text, prompt);
      expect(captured!.text, contains('ProductCard'));
      // GenUI 0.10.1 references the active catalog ID in more than one prompt
      // section, so the load-bearing claim is "exactly ONE distinct catalog ID"
      // (no divergent id), not a single literal occurrence.
      final catalogIds = RegExp(
        r'restage:catalog/sha256/[0-9a-f]{64}',
      ).allMatches(captured!.text).map((m) => m.group(0)).toSet();
      expect(catalogIds, {restageA2uiCatalogId});
    },
  );

  test('ProductCard preserves nested documentation in both schema views', () {
    final catalog = buildRestageCatalog();
    final generated = catalog.items
        .singleWhere((item) => item.name == 'ProductCard')
        .dataSchema
        .value;
    final standalone = _objectAt(
      _objectAt(_standaloneCatalog(), 'components'),
      'ProductCard',
    );
    expect(_normalizeSchema(generated), _normalizeSchema(standalone));

    final schema = standalone;
    final definitions = _objectAt(schema, r'$defs');
    final root = _objectAt(definitions, '__a2ui_root__');
    final rootProperties = _objectAt(root, 'properties');
    final productOccurrence = _objectAt(rootProperties, 'product');
    final product = _objectAt(definitions, 'Product');
    final productProperties = _objectAt(product, 'properties');
    final money = _objectAt(definitions, 'Money');
    final moneyProperties = _objectAt(money, 'properties');
    final features = _objectAt(productProperties, 'features');
    final feature = _objectAt(features, 'items');
    final featureProperties = _objectAt(feature, 'properties');

    _expectDescription(
      root,
      'Renders a structured product (nested price, tags, features, '
      'attributes, size).',
    );
    _expectDescription(productOccurrence, 'The product to display.');
    _expectDescription(
      product,
      'A product with pricing, feature, attribute, and display metadata.',
    );
    _expectDescription(
      _objectAt(productProperties, 'name'),
      'The customer-facing product name.',
    );
    _expectDescription(
      _objectAt(productProperties, 'price'),
      'The price — a nested data class.',
    );
    _expectDescription(money, 'A monetary amount in a specific currency.');
    _expectDescription(
      _objectAt(moneyProperties, 'amount'),
      'The numeric amount.',
    );
    _expectDescription(
      _objectAt(moneyProperties, 'currency'),
      "The ISO currency code (e.g. `'USD'`).",
    );
    _expectDescription(
      _objectAt(productProperties, 'tags'),
      'Marketing tags — a scalar list.',
    );
    _expectDescription(features, 'Feature rows — a list of objects.');
    _expectDescription(
      feature,
      'One feature included in or excluded from a product.',
    );
    _expectDescription(
      _objectAt(featureProperties, 'label'),
      'The feature label.',
    );
    _expectDescription(
      _objectAt(featureProperties, 'included'),
      'Whether this plan includes the feature.',
    );
    _expectDescription(
      _objectAt(productProperties, 'attributes'),
      'Arbitrary attributes — a String-keyed map.',
    );
    final size = _objectAt(productProperties, 'size');
    _expectDescription(size, 'The display size — a named record.');
    final sizeProperties = _objectAt(size, 'properties');
    expect(
      sizeProperties.values.cast<Map<Object?, Object?>>().every(
        (field) => !field.containsKey('description'),
      ),
      isTrue,
      reason: 'record labels must not invent documentation',
    );

    final encoded = jsonEncode(schema);
    for (final description in const [
      'The customer-facing product name.',
      'A product with pricing, feature, attribute, and display metadata.',
      'A monetary amount in a specific currency.',
      'One feature included in or excluded from a product.',
    ]) {
      expect(description.allMatches(encoded), hasLength(1));
    }
    expect(encoded, isNot(contains('The internal product name.')));
  });

  test(
    'the transport receive seam selects only the exact generated catalog',
    () async {
      final catalog = buildRestageCatalog();
      final transport = A2uiTransportAdapter();
      final controller = SurfaceController(catalogs: [catalog]);
      final conversation = Conversation(
        controller: controller,
        transport: transport,
      );
      addTearDown(() {
        conversation.dispose();
        transport.dispose();
        controller.dispose();
      });

      Future<void> receive(CreateSurfaceMessage message) async {
        final received = conversation.events.firstWhere(
          (event) =>
              event is ConversationSurfaceAdded &&
              event.surfaceId == message.surfaceId,
        );
        transport.addMessage(message);
        await received.timeout(const Duration(seconds: 5));
      }

      await receive(
        CreateSurfaceMessage(
          surfaceId: 'matching',
          catalogId: restageA2uiCatalogId,
        ),
      );
      final matching = controller.contextFor('matching');
      expect(matching.definition.value!.catalogId, restageA2uiCatalogId);
      expect(matching.catalog, same(catalog));

      final wrongCatalogId = '$restageA2uiCatalogId-wrong';
      await receive(
        CreateSurfaceMessage(surfaceId: 'wrong', catalogId: wrongCatalogId),
      );
      final wrong = controller.contextFor('wrong');
      expect(wrong.definition.value!.catalogId, wrongCatalogId);
      expect(wrong.catalog, isNull);
    },
  );

  test('default and inline capabilities use the same generated catalog', () {
    final catalog = buildRestageCatalog();

    final predefined = A2UiClientCapabilities.fromCatalogs([catalog]).toJson();
    expect(predefined, {
      'v0.9': {
        'supportedCatalogIds': [restageA2uiCatalogId],
      },
    });

    final inline = A2UiClientCapabilities.fromCatalogs([
      catalog,
    ], inlineHandling: InlineCatalogHandling.all).toJson();
    final inlineV09 = inline['v0.9']! as Map<String, Object?>;
    expect(inlineV09['supportedCatalogIds'], isEmpty);
    final inlineCatalogs = inlineV09['inlineCatalogs']! as List<Object?>;
    expect(inlineCatalogs.single, catalog.toCapabilitiesJson());

    // Default predefined-ID mode requires the server to register this exact
    // component/function contract under restageA2uiCatalogId. The separate
    // inline serialization proof does not claim GenUI 0.9.2 server
    // interoperability for inline catalogs.
  });

  test('GenUI 0.10.1 reports a required-property error for a missing title '
      '(report-only: the update event still fires)', () async {
    final catalog = buildRestageCatalog();
    final outbound = StreamController<ChatMessage>.broadcast();
    final transport = A2uiTransportAdapter(
      onSend: (message) async => outbound.add(message),
    );
    final controller = SurfaceController(catalogs: [catalog]);
    final conversation = Conversation(
      controller: controller,
      transport: transport,
    );
    addTearDown(() async {
      conversation.dispose();
      transport.dispose();
      controller.dispose();
      await outbound.close();
    });

    Future<void> createSurface(String surfaceId) async {
      final received = conversation.events.firstWhere(
        (event) =>
            event is ConversationSurfaceAdded && event.surfaceId == surfaceId,
      );
      transport.addMessage(
        CreateSurfaceMessage(
          surfaceId: surfaceId,
          catalogId: restageA2uiCatalogId,
        ),
      );
      await received.timeout(const Duration(seconds: 5));
    }

    Future<void> updateAccepted(String surfaceId, Object? title) async {
      final received = conversation.events.firstWhere(
        (event) =>
            event is ConversationComponentsUpdated &&
            event.surfaceId == surfaceId,
      );
      transport.addMessage(
        UpdateComponentsMessage(
          surfaceId: surfaceId,
          components: [
            {'id': 'root', 'component': 'SectionHeader', 'title': title},
          ],
        ),
      );
      await received.timeout(const Duration(seconds: 5));
    }

    await createSurface('missing');
    final errorSent = outbound.stream.first;
    transport.addMessage(
      UpdateComponentsMessage(
        surfaceId: 'missing',
        components: const [
          {'id': 'root', 'component': 'SectionHeader'},
        ],
      ),
    );
    final errorMessage = await errorSent.timeout(const Duration(seconds: 5));
    final interaction = errorMessage.parts.uiInteractionParts.single;
    final errorJson =
        jsonDecode(interaction.interaction) as Map<String, Object?>;
    final error = errorJson['error']! as Map<String, Object?>;
    expect(error['message'], contains('Required property "title" is missing'));

    // GenUI 0.10.1 validation is REPORT-ONLY: it surfaces an error but does not
    // roll back, so the components-updated event still fires. null and a
    // wrong-typed value now ALSO produce a validation error (0.9.2 accepted
    // them), yet the update is still applied — the event fires either way.
    await createSurface('null');
    await updateAccepted('null', null);
    await createSurface('wrong-type');
    await updateAccepted('wrong-type', 42);
  });
}
