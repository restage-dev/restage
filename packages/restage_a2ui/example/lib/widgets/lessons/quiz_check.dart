import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A lesson quiz checkbox: a [prompt], a bound [selected] bool, and an
/// [onSelected] callback bound back to `selected` via an EXPLICIT
/// `@RestageProperty(writeBackValue:)` — the explicit write-back pairing (as
/// opposed to `RatingPicker`'s same-type auto-pairing).
@RestageA2uiExample(
  name: 'Interaction',
  asset: 'lib/a2ui_examples/quiz_check/interaction.json',
)
@RestageWidget(
  name: 'QuizCheck',
  library: WidgetLibrary.custom('acme.lessons'),
  category: WidgetCategory.input,
  description: 'A prompt with a checkable answer bound to a boolean value.',
  fires: [WidgetEventName.onChanged],
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
  @RestageProperty(
    description: 'Reports the toggled answer.',
    writeBackValue: 'selected',
  )
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
