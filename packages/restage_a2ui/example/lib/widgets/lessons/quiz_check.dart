import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A lesson quiz checkbox: a [prompt], a bound [selected] bool, and an
/// [onSelected] callback bound back to `selected` via an EXPLICIT
/// `@a2ui.Config.writeBackValue('selected')` — the explicit write-back pairing (as
/// opposed to `RatingPicker`'s same-type auto-pairing).
@RestageWidget(
  name: 'QuizCheck',
  library: WidgetLibrary.custom('acme.lessons'),
  category: WidgetCategory.input,
  description: 'A prompt with a checkable answer bound to a boolean value.',
)
class QuizCheck extends StatelessWidget {
  /// Creates a quiz check showing [prompt], [selected], reporting [onSelected].
  const QuizCheck({
    required this.prompt,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// The question prompt.
  @RestageProperty(description: 'The quiz prompt.')
  final String prompt;

  /// The current answer state — the bound value.
  @RestageProperty(description: 'Whether the answer is selected.')
  final bool selected;

  /// Reports the new answer state; explicitly bound back to [selected].
  @a2ui.Config.writeBackValue('selected')
  @RestageProperty(description: 'Reports the toggled answer.')
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('quiz-check'),
      onTap: () => onSelected(!selected),
      child: Text('${selected ? '☑' : '☐'} $prompt'),
    );
  }
}
