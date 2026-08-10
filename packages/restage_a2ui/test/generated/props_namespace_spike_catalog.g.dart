// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated-shaped output for the required-props executable feasibility spike.
// ignore_for_file: sort_child_properties_last

import 'props_namespace_spike_fixture.dart' as p0;
import 'package:flutter/widgets.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

const String propsNamespaceSpikeCatalogId =
    'restage:spike/a2ui-required-props/v0.9.1';

Catalog buildPropsNamespaceSpikeCatalog() => Catalog(
      buildPropsNamespaceSpikeCatalogItems(),
      catalogId: propsNamespaceSpikeCatalogId,
      functions: const <ClientFunction>[_SpikeStringFunction()],
    );

List<CatalogItem> buildPropsNamespaceSpikeCatalogItems() => <CatalogItem>[
      CatalogItem(
        name: 'CustomerCard',
        dataSchema: _customerCardSchema,
        widgetBuilder: _buildCustomerCard,
      ),
      CatalogItem(
        name: 'SpikeLeaf',
        dataSchema: S.object(
          properties: <String, Schema>{
            'props': S.object(
              properties: <String, Schema>{'label': S.string()},
              required: <String>['label'],
            ),
          },
          required: <String>['props'],
        ),
        widgetBuilder: (itemContext) {
          final props = _props(itemContext);
          return p0.PropsNamespaceLeaf(label: props['label']! as String);
        },
      ),
      _ordinaryExternalCatalogItem,
    ];

final Schema _dynamicString = S.combined(
  oneOf: <Schema>[
    S.string(),
    S.object(
      properties: <String, Schema>{'path': S.string()},
      required: <String>['path'],
    ),
    S.object(
      properties: <String, Schema>{
        'call': S.string(),
        'args': S.object(additionalProperties: true),
      },
      required: <String>['call'],
    ),
  ],
);

final Schema _dynamicBoolean = S.combined(
  oneOf: <Schema>[
    S.boolean(),
    S.object(
      properties: <String, Schema>{'path': S.string()},
      required: <String>['path'],
    ),
    S.object(
      properties: <String, Schema>{
        'call': S.string(),
        'args': S.object(additionalProperties: true),
      },
      required: <String>['call'],
    ),
  ],
);

final Schema _customerCardSchema = S.combined(
  $ref: '#/\$defs/__a2ui_root__',
  $defs: <String, Schema>{
    'SpikeNode': S.object(
      properties: <String, Schema>{
        'label': S.string(),
        'child': S.combined(
          anyOf: <Schema>[
            S.combined($ref: '#/\$defs/SpikeNode'),
            S.nil(),
          ],
        ),
      },
      required: <String>['label'],
    ),
    '__a2ui_root__': S.object(
      properties: <String, Schema>{
        'props': S.object(
          properties: <String, Schema>{
            'id': S.string(),
            'component': S.string(),
            'catalogId': S.string(),
            'props': S.string(),
            'literalValue': _dynamicString,
            'pathValue': _dynamicString,
            'callValue': _dynamicString,
            'node': S.combined($ref: '#/\$defs/SpikeNode'),
            'counts': S.object(additionalProperties: S.integer()),
            'meta': S.object(
              properties: <String, Schema>{
                'label': S.string(),
                'count': S.integer(),
              },
              required: <String>['label', 'count'],
            ),
            'leading': S.string(),
            'children': S.list(items: S.string()),
            'enabled': _dynamicBoolean,
          },
          required: <String>[
            'id',
            'component',
            'catalogId',
            'props',
            'literalValue',
            'pathValue',
            'callValue',
            'node',
            'counts',
            'meta',
            'leading',
            'children',
            'enabled',
          ],
        ),
      },
      required: <String>['props'],
    ),
  },
);

Widget _buildCustomerCard(CatalogItemContext itemContext) {
  final props = _props(itemContext);
  return BoundString(
    dataContext: itemContext.dataContext,
    value: props['literalValue'],
    builder: (context, literalValue) => BoundString(
      dataContext: itemContext.dataContext,
      value: props['pathValue'],
      builder: (context, pathValue) => BoundString(
        dataContext: itemContext.dataContext,
        value: props['callValue'],
        builder: (context, callValue) => BoundBool(
          dataContext: itemContext.dataContext,
          value: props['enabled'],
          builder: (context, enabled) => p0.PropsNamespaceProbe(
            id: props['id']! as String,
            component: props['component']! as String,
            catalogId: props['catalogId']! as String,
            props: props['props']! as String,
            literalValue: literalValue ?? '',
            pathValue: pathValue ?? '',
            callValue: callValue ?? '',
            node: _buildNode(props['node']),
            counts: _buildCounts(props['counts']),
            meta: _buildMeta(props['meta']),
            leading: itemContext.buildChild(props['leading']! as String),
            children: <Widget>[
              for (final childId in (props['children']! as List<Object?>))
                itemContext.buildChild(childId! as String),
            ],
            enabled: enabled ?? false,
            onAction: () => itemContext.dispatchEvent(
              UserActionEvent(
                name: 'onAction',
                sourceComponentId: itemContext.id,
              ),
            ),
            onEnabledChanged: (next) {
              final source = props['enabled'];
              if (source is Map && source['path'] is String) {
                itemContext.dataContext.update(
                  DataPath(source['path']! as String),
                  next,
                );
              }
            },
          ),
        ),
      ),
    ),
  );
}

Map<String, Object?> _props(CatalogItemContext itemContext) =>
    ((itemContext.data as Map<String, Object?>)['props']! as Map)
        .cast<String, Object?>();

p0.SpikeNode _buildNode(Object? value) {
  final map = (value! as Map).cast<String, Object?>();
  return p0.SpikeNode(
    label: map['label']! as String,
    child: map['child'] == null ? null : _buildNode(map['child']),
  );
}

Map<String, int> _buildCounts(Object? value) =>
    (value! as Map).map<String, int>(
      (key, count) => MapEntry<String, int>(key as String, (count! as num).toInt()),
    );

p0.SpikeMeta _buildMeta(Object? value) {
  final map = (value! as Map).cast<String, Object?>();
  return (label: map['label']! as String, count: (map['count']! as num).toInt());
}

final CatalogItem _ordinaryExternalCatalogItem = CatalogItem(
  name: 'ExternalPropsCard',
  dataSchema: S.object(
    properties: <String, Schema>{
      'props': S.object(
        properties: <String, Schema>{'label': S.string()},
        required: <String>['label'],
      ),
    },
    required: <String>['props'],
  ),
  widgetBuilder: _buildExternalPropsCard,
);

Widget _buildExternalPropsCard(CatalogItemContext itemContext) {
  final props = _props(itemContext);
  return Text('external:${props['label']}');
}

final class _SpikeStringFunction extends SynchronousClientFunction {
  const _SpikeStringFunction();

  @override
  String get name => 'spikeString';

  @override
  String get description => 'Returns a spike string literal.';

  @override
  Schema get argumentSchema => S.object(properties: const <String, Schema>{});

  @override
  ClientFunctionReturnType get returnType => ClientFunctionReturnType.string;

  @override
  Object? executeSync(JsonMap args, ExecutionContext context) => 'from-call';
}
