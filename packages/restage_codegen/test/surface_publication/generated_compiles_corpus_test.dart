// An app's pages through the generator: every page generates Dart that
// compiles.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/generated_compiles.dart';

const _pages = 'test/fixtures/app_pages_corpus';

// An app's pages with its design system, state and models stood in for by one
// kit library; each page is declared a screen, its paywall a paywall.
Map<String, String> _page(String file, String source) {
  final stem = p.basenameWithoutExtension(file);
  var text = source
      .replaceAll(
        RegExp(
          r"^import 'package:(sample_app|kit_ui|state_kit)/[^']*';\n",
          multiLine: true,
        ),
        '',
      )
      .replaceAll(
        RegExp(r'^@(Screen|Paywall)\([^\n]*\)\n', multiLine: true),
        '',
      );
  final imports = [
    "import 'app_kit.dart';",
    if (!text.contains('package:restage/restage.dart'))
      "import 'package:restage/restage.dart';",
  ];
  text = text.replaceFirst(
    "import 'package:flutter/widgets.dart';\n",
    "import 'package:flutter/widgets.dart';\n${imports.join('\n')}\n",
  );
  if (!text.contains("part 'restage.generated/")) {
    final lines = text.split('\n');
    final last = lines.lastIndexWhere((line) => line.startsWith('import '));
    lines.insert(last + 1, "\npart 'restage.generated/$stem.restage.g.dart';");
    text = lines.join('\n');
  }
  text = text.replaceAllMapped(
    RegExp(
      r'^class (\w*(?:Page|PaywallScreen)) extends (StatelessWidget|StatefulWidget)',
      multiLine: true,
    ),
    (m) =>
        '${m[1] == 'PaywallScreen' ? "@Paywall(id: 'plus_paywall')" : "@Screen(id: 'onboarding_${stem.replaceAll('_page', '')}', surface: Surface.onboarding)"}\n'
        '${m[0]}',
  );
  return {'lib/pages/$stem.dart': text};
}

// The time page with a private widget passed straight into a banner's widget
// parameter.
String _withReminderWidget(String time) => time
    .replaceFirst(
      RegExp(r'rich: Text\.rich\([\s\S]*?\n                  \),\n'),
      'rich: _FirstReminder(firstReminderText(now, state.time)),\n',
    )
    .replaceFirst(
      '/// "tomorrow at',
      '''
class _FirstReminder extends StatelessWidget {
  const _FirstReminder(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      text: 'First reminder: ',
      children: [
        TextSpan(text: text, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

/// "tomorrow at''',
    );

void main() {
  test(
    'every app page generates code that compiles',
    () async {
      final kit = File('$_pages/app_kit.dart.txt').readAsStringSync();
      final pages = {
        for (final file in Directory(
          '$_pages/pages',
        ).listSync().whereType<File>())
          p.basename(file.path).replaceAll('.txt', ''): file.readAsStringSync(),
      };
      pages['time_reminder_page.dart'] = _withReminderWidget(
        pages['time_page.dart']!,
      );
      expect(
        pages['time_reminder_page.dart'],
        contains('rich: _FirstReminder('),
      );
      final outcomes = await expectGeneratedCompiles({
        for (final MapEntry(:key, :value) in pages.entries)
          key: {'lib/pages/app_kit.dart': kit, ..._page(key, value)},
      });
      printOutcomes(outcomes);
      // No page is refused, and each one's generated code compiles.
      expect(outcomes.values.where((o) => !o.compiled), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
