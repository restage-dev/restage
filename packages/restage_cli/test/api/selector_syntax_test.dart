import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:test/test.dart';

void main() {
  const publish = FollowUp('surface publish', 'restage_publish_surface', [
    FollowUpArg('surfaceSlug', 'welcome'),
    FollowUpArg('surfaceType', 'onboarding', flag: 'type', mcpOnly: true),
    FollowUpArg('revision', '3', flag: 'revision'),
    FollowUpArg('all', null, flag: 'all', cliOnly: true),
  ]);

  test('the CLI reads a command line', () {
    expect(
      SelectorSyntax.cli.command(publish),
      '`restage surface publish welcome --revision 3 --all`',
    );
  });

  test('the console reads a line for its command line', () {
    expect(
      SelectorSyntax.console.command(publish),
      '`/restage surface publish welcome --revision 3 --all`',
    );
  });

  test('the MCP server reads a tool call', () {
    expect(
      SelectorSyntax.mcp.command(publish),
      'restage_publish_surface with surfaceSlug: welcome, surfaceType: '
      'onboarding, revision: 3',
    );
  });

  test('shared sentences name each caller its own way', () {
    expect(
      noProjectContextSentence(SelectorSyntax.cli),
      'No project / app context. Run `restage init`, or pass '
      '--project <slug> and --app <slug>.',
    );
    expect(
      noProjectContextSentence(SelectorSyntax.mcp),
      'No project / app context. Call restage_init, or pass projectSlug and '
      'appSlug.',
    );
    expect(
      notSignedInSentence(SelectorSyntax.mcp),
      'Not signed in. Call restage_login.',
    );
  });
}
