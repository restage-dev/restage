import 'package:flutter/material.dart' hide Switch;
import 'package:rfw/rfw.dart';

/// A widget a preview draws as a placeholder: it is not in this build, or its
/// builder could not build it.
@immutable
final class RenderPlaceholder {
  /// Describes the placeholder for [widgetName].
  const RenderPlaceholder({required this.widgetName, this.missingInput});

  /// The widget the document asked for.
  final String widgetName;

  /// The required input the widget was built without, when known.
  final String? missingInput;

  /// The one line a placeholder shows, such as `StreakBadge.days`.
  String get label =>
      missingInput == null ? widgetName : '$widgetName.$missingInput';

  @override
  bool operator ==(Object other) =>
      other is RenderPlaceholder &&
      other.widgetName == widgetName &&
      other.missingInput == missingInput;

  @override
  int get hashCode => Object.hash(widgetName, missingInput);
}

/// Draws [placeholder] to fill the size the preview gives it.
typedef RenderPlaceholderBuilder = Widget Function(
  BuildContext context,
  RenderPlaceholder placeholder,
);

/// Width a placeholder takes when its parent leaves width open.
const double kRenderPlaceholderWidth = 160;

/// Height a placeholder takes when its parent leaves height open.
const double kRenderPlaceholderHeight = 56;

/// [placeholder] drawn by [builder] at a finite size within its constraints.
Widget buildBoundedRenderPlaceholder(
  BuildContext context,
  RenderPlaceholder placeholder,
  RenderPlaceholderBuilder? builder,
) =>
    SizedBox(
      width: kRenderPlaceholderWidth,
      height: kRenderPlaceholderHeight,
      child: builder == null
          ? DefaultRenderPlaceholder(placeholder: placeholder)
          : builder(context, placeholder),
    );

/// The muted box a render host draws when its embedder supplies none.
class DefaultRenderPlaceholder extends StatelessWidget {
  /// Draws [placeholder].
  const DefaultRenderPlaceholder({required this.placeholder, super.key});

  /// What to name.
  final RenderPlaceholder placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Text(
            placeholder.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

final _requiredInputPattern = RegExp(r'^[^.\s]+\.([^.\s]+) is required\.$');

/// The input a builder error names as required, or null.
String? missingInputOf(Object error) {
  final message = switch (error) {
    ArgumentError(:final message) => '$message',
    _ => '$error',
  };
  return _requiredInputPattern.firstMatch(message)?.group(1);
}

/// Wraps [builder] so a throw draws [placeholder] naming [name].
LocalWidgetBuilder guardRenderBuilder(
  String name,
  LocalWidgetBuilder builder,
  RenderPlaceholderBuilder placeholder,
) =>
    (context, source) {
      try {
        return builder(context, source);
      } on Object catch (error) {
        return placeholder(
          context,
          RenderPlaceholder(
            widgetName: name,
            missingInput: missingInputOf(error),
          ),
        );
      }
    };

/// Every constructor [document] calls that neither it nor any library it
/// imports provides, given the constructors each installed library holds.
Set<String> absentConstructors(
  RemoteWidgetLibrary document,
  Map<String, Set<String>> installed,
) {
  final called = <String>{};
  for (final declaration in document.widgets) {
    _collectCalls(declaration.initialState, called);
    _collectCalls(declaration.root, called);
  }
  called.removeAll(document.widgets.map((declaration) => declaration.name));
  for (final import in document.imports) {
    final names = installed[import.name.parts.join('.')];
    if (names != null) called.removeAll(names);
  }
  return called;
}

void _collectCalls(Object? value, Set<String> into) {
  switch (value) {
    case ConstructorCall(:final name, :final arguments):
      into.add(name);
      _collectCalls(arguments, into);
    case WidgetBuilderDeclaration(:final widget):
      _collectCalls(widget, into);
    case Loop(:final input, :final output):
      _collectCalls(input, into);
      _collectCalls(output, into);
    case Switch(:final input, :final outputs):
      _collectCalls(input, into);
      for (final entry in outputs.entries) {
        _collectCalls(entry.key, into);
        _collectCalls(entry.value, into);
      }
    case EventHandler(:final eventArguments):
      _collectCalls(eventArguments, into);
    case SetStateHandler(:final value):
      _collectCalls(value, into);
    case BoundArgsReference(:final arguments):
      _collectCalls(arguments, into);
    case BoundLoopReference(:final value):
      _collectCalls(value, into);
    case final Map<Object?, Object?> map:
      for (final entry in map.entries) {
        _collectCalls(entry.key, into);
        _collectCalls(entry.value, into);
      }
    case final Iterable<Object?> list:
      for (final item in list) {
        _collectCalls(item, into);
      }
  }
}
