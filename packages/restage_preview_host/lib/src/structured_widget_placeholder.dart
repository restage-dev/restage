import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'manifest.dart';

/// Completes manifest-declared customer libraries with inert placeholders.
///
/// Real runtime registrations always win. A manifest declaration that is
/// absent from the runtime is still renderable as a visibly labeled,
/// noninteractive placeholder instead of becoming an RFW constructor error.
List<RestageWidgetLibraryRegistration> completeManifestWidgetRegistrations({
  required RenderBundleManifest manifest,
  required Iterable<RestageWidgetLibraryRegistration> registrations,
}) {
  final byNamespace = <String, _MutableRegistration>{};
  for (final registration in registrations) {
    final namespace = registration.library.namespace;
    if (_isIneligibleNamespace(namespace)) continue;
    final mutable = byNamespace.putIfAbsent(
      namespace,
      () => _MutableRegistration(
        library: registration.library,
        capabilityVersion: registration.capabilityVersion,
      ),
    );
    for (final widget in registration.widgets) {
      mutable.widgets.putIfAbsent(widget.name, () => widget);
    }
  }

  final rawWidgets = manifest.catalog['widgets'];
  if (rawWidgets is List<Object?>) {
    for (final rawWidget in rawWidgets) {
      final widget = _stringMap(rawWidget);
      if (widget == null) continue;
      final namespace = widget['library'];
      final name = widget['name'];
      if (namespace is! String ||
          name is! String ||
          _isIneligibleNamespace(namespace)) {
        continue;
      }
      final propertyNames = _propertyNames(widget);
      final mutable = byNamespace.putIfAbsent(
        namespace,
        () => _MutableRegistration(
          library: WidgetLibrary.custom(namespace),
        ),
      );
      mutable.widgets.putIfAbsent(
        name,
        () => RestageWidgetFactory(
          name: name,
          builder: (context, source) => StructuredWidgetPlaceholder(
            widgetName: name,
            propertyNames: propertyNames,
          ),
        ),
      );
    }
  }

  return List<RestageWidgetLibraryRegistration>.unmodifiable(
    byNamespace.values.map(
      (registration) => RestageWidgetLibraryRegistration(
        library: registration.library,
        widgets: registration.widgets.values,
        capabilityVersion: registration.capabilityVersion,
      ),
    ),
  );
}

/// Shared visible fallback for a customer widget unavailable in this runtime.
class StructuredWidgetPlaceholder extends StatelessWidget {
  const StructuredWidgetPlaceholder({
    required this.widgetName,
    required this.propertyNames,
    this.fullBleed = false,
    super.key,
  });

  final String widgetName;
  final Iterable<String> propertyNames;
  final bool fullBleed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final propertySummary = propertyNames.take(4).join(', ');
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          Icons.extension_outlined,
          size: 20,
          color: colors.onSurfaceVariant,
        ),
        const SizedBox(height: 6),
        Text(
          widgetName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 2),
        Text(
          'Custom widget · renders in your app',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        if (propertySummary.isNotEmpty) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            propertySummary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
    if (fullBleed) {
      return ColoredBox(
        color: colors.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Center(child: content),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: content,
    );
  }
}

final class _MutableRegistration {
  _MutableRegistration({
    required this.library,
    this.capabilityVersion,
  });

  final WidgetLibrary library;
  final int? capabilityVersion;
  final Map<String, RestageWidgetFactory> widgets =
      <String, RestageWidgetFactory>{};
}

bool _isIneligibleNamespace(String namespace) =>
    namespace == kReservedPreviewLibraryName ||
    WidgetLibrary.builtInByNamespace(namespace) != null;

List<String> _propertyNames(Map<String, Object?> widget) {
  final result = <String>[];
  final rawProperties = widget['properties'];
  if (rawProperties is! List<Object?>) return result;
  for (final rawProperty in rawProperties) {
    final property = _stringMap(rawProperty);
    final name = property?['name'];
    if (name is String && name.isNotEmpty) result.add(name);
  }
  return result;
}

Map<String, Object?>? _stringMap(Object? value) {
  if (value is! Map<Object?, Object?>) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) return null;
    result[key] = entry.value;
  }
  return result;
}
