import 'dart:async';

import 'package:nocterm/nocterm.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/tui/console_app.dart';
import 'package:restage_cli/src/tui/console_controller.dart';
import 'package:restage_cli/src/tui/console_models.dart';
import 'package:test/test.dart' hide isEmpty;

void main() {
  test('console renders the primary panels', () async {
    await testNocterm('console renders the primary panels', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      expect(tester.terminalState, containsText('Proj 1'));
      expect(tester.terminalState, containsText('Apps'));
      expect(tester.terminalState, containsText('Surfaces'));
      expect(tester.terminalState, containsText('Overview detail'));
      expect(tester.terminalState, containsText('Active surfaces'));
    });
  });

  test('console renders the B4 operator shell', () async {
    await testNocterm('console renders the B4 operator shell', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      expect(tester.terminalState, containsText('restage'));
      expect(tester.terminalState, containsText('default / default / staging'));
      expect(tester.terminalState, containsText('/ search surfaces, commands'));
      expect(tester.terminalState, containsText('Dashboard'));
      expect(tester.terminalState, containsText('Surfaces'));
      expect(tester.terminalState, containsText('Overview detail'));
      expect(tester.terminalState, containsText('30-day views'));
      expect(tester.terminalState, isNot(containsText('Command preview')));
    });
  });

  test('console footer advertises navigation keys', () async {
    await testNocterm('console footer advertises navigation keys', (
      tester,
    ) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      final footerLine = tester
          .renderToString()
          .split('\n')
          .firstWhere((line) => line.contains('tab panels'));

      expect(footerLine, contains('/ search'));
      expect(footerLine, contains('enter/space select'));
    });
  });

  test('console applies dashboard color tokens', () async {
    await testNocterm('console applies dashboard color tokens', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      const brand = Color.fromRGB(255, 126, 107);
      const focus = Color.fromRGB(52, 211, 153);

      expect(
        tester.terminalState,
        hasStyledText(
          'restage',
          const TextStyle(color: brand, fontWeight: FontWeight.bold),
        ),
      );
      expect(
        tester.terminalState,
        hasStyledText(
          'Dashboard',
          const TextStyle(color: focus, fontWeight: FontWeight.bold),
        ),
      );
      expect(
        tester.terminalState,
        hasStyledText('> Overview', const TextStyle(color: brand)),
      );
    });
  });

  test('overview detail renders dashboard metrics', () async {
    await testNocterm('overview detail renders metrics', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      expect(tester.terminalState, containsText('Overview detail'));
      expect(tester.terminalState, containsText('Active surfaces 3'));
      expect(tester.terminalState, containsText('30-day views -'));
      expect(tester.terminalState, containsText('Conversion rate -'));
      expect(tester.terminalState, containsText(r'MAR consumed $0 / $10k'));
      expect(tester.terminalState, isNot(containsText('Command preview')));
    });
  });

  test('detail panel renders selected surface version history', () async {
    await testNocterm('detail renders version history', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();

      expect(tester.terminalState, containsText('Detail: pro Actions'));
      expect(tester.terminalState, containsText('Version history'));
      expect(tester.terminalState, containsText('v2 active'));
      expect(tester.terminalState, containsText('sha-2'));
    });
  });

  test('detail panel labels history as status-backed', () async {
    await testNocterm('detail history label', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();

      expect(tester.terminalState, containsText('Status-backed history'));
      expect(tester.terminalState, isNot(containsText('Recent activity')));
    });
  });

  test('status-backed history stays inside the detail panel border', () async {
    await testNocterm('status history stays inside panel', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();

      final historyLine = tester
          .renderToString()
          .split('\n')
          .firstWhere((line) => line.contains('Status-backed history'));

      expect(historyLine, isNot(contains('└')));
    });
  });

  test('console shows adjustable panel affordances', () async {
    await testNocterm('console shows resize affordances', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      expect(tester.terminalState, containsText('drag resize'));
      expect(tester.terminalState, containsText('|'));
    });
  });

  test('dragging the surfaces divider widens the surfaces panel', () async {
    await testNocterm('dragging divider resizes surfaces', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();

      expect(tester.terminalState, isNot(containsText('delivery   v')));

      await tester.press(46, 11);
      await tester.sendMouseEvent(
        const MouseEvent(
          button: MouseButton.left,
          x: 58,
          y: 11,
          pressed: true,
          isMotion: true,
        ),
      );
      await tester.release(58, 11);
      await tester.pump();

      expect(tester.terminalState, containsText('delivery   v'));
    });
  });

  test('console keeps command preview compact in the B4 shell', () async {
    await testNocterm('console keeps command preview compact', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();

      expect(tester.terminalState, containsText('surface publish'));
      expect(tester.terminalState, containsText('p publish'));
      expect(
        tester.terminalState,
        isNot(containsText('restage surfaces status')),
      );
    });
  });

  test('arrow keys on left panel move dashboard nav, not surfaces', () async {
    await testNocterm('left panel arrows move nav', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();

      expect(controller.state.focusedPanel, ConsolePanel.projects);
      expect(controller.state.selectedSurface?.slug, 'pro');
      expect(tester.terminalState, containsText('> Surfaces'));
      expect(tester.terminalState, containsText('Detail: pro'));
    });
  });

  test('left nav skips duplicate lifecycle view', () async {
    await testNocterm('left nav skips lifecycle view', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.sendArrowDown();
      await tester.pump();

      expect(tester.terminalState, containsText('> Audit trail'));
      expect(tester.terminalState, containsText('Session activity'));
      expect(tester.terminalState, isNot(containsText('Lifecycle')));
      expect(tester.terminalState, isNot(containsText('[all] [pay] [onbd]')));
    });
  });

  test('detail panel renders selected action command preview', () async {
    await testNocterm('detail renders action preview', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();

      expect(tester.terminalState, containsText('> p publish'));
      expect(tester.terminalState, containsText('f freeze'));
      expect(tester.terminalState, containsText('u unfreeze'));
      expect(tester.terminalState, containsText('r rollback'));
      expect(tester.terminalState, containsText('k kill'));
      final lines = tester.renderToString().split('\n');
      int lineFor(String text) =>
          lines.indexWhere((line) => line.contains(text));
      expect(lineFor('> p publish'), greaterThanOrEqualTo(0));
      expect(lineFor('f freeze'), lineFor('> p publish') + 1);
      expect(lineFor('u unfreeze'), lineFor('f freeze') + 1);
      expect(lineFor('r rollback'), lineFor('u unfreeze') + 1);
      expect(lineFor('k kill'), lineFor('r rollback') + 1);
      expect(
        tester.terminalState,
        containsText(
          'surface publish pro --type paywall --project default --app default --env staging --plane live',
        ),
      );
    }, size: const Size(160, 32));
  });

  test('detail panel arrows update selected action preview', () async {
    await testNocterm('detail arrows update preview', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();
      await tester.sendKey(LogicalKey.tab);
      await tester.sendKey(LogicalKey.tab);
      await tester.pump();
      await tester.sendArrowDown();
      await tester.sendArrowDown();
      await tester.sendArrowDown();
      await tester.pump();

      expect(tester.terminalState, containsText('> r rollback'));
      expect(
        tester.terminalState,
        containsText(
          'surface rollback pro --type paywall --source-kind paywall',
        ),
      );
      expect(
        tester.terminalState,
        containsText('--project default --app default --env staging'),
      );
    }, size: const Size(160, 32));
  });

  test('manifest-backed preview uses the exact family address', () async {
    await testNocterm('manifest-backed action preview', (tester) async {
      final controller = ConsoleController(
        repository: ManifestConsoleRepository(),
      );
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();
      expect(
        tester.terminalState,
        containsText(
          'surface publish pro --project default --app default --env staging '
          '--plane live',
        ),
      );
      expect(tester.terminalState, isNot(containsText('--type paywall')));

      await tester.sendKey(LogicalKey.tab);
      await tester.sendKey(LogicalKey.tab);
      await tester.pump();
      await tester.sendArrowDown();
      await tester.sendArrowDown();
      await tester.sendArrowDown();
      await tester.pump();
      expect(
        tester.terminalState,
        containsText(
          'surface rollback pro --contract-version 3 --project default '
          '--app default --env staging --plane live',
        ),
      );

      await tester.sendArrowDown();
      await tester.pump();
      expect(
        tester.terminalState,
        containsText(
          'surface kill pro --project default --app default --env staging '
          '--plane live',
        ),
      );
      expect(
        tester.terminalState,
        isNot(containsText('surface kill pro --contract-version')),
      );
    }, size: const Size(160, 32));
  });

  test('overview detail enter does not launch surface actions', () async {
    await testNocterm('overview detail enter is read only', (tester) async {
      final executor = RecordingConsoleOperationExecutor();
      final controller = ConsoleController(
        repository: FakeConsoleRepository(),
        operationExecutor: executor,
      );
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendKey(LogicalKey.tab);
      await tester.sendKey(LogicalKey.tab);
      await tester.pump();
      await tester.sendKey(LogicalKey.enter);
      await tester.pump();

      expect(executor.calls, <String>[]);
      expect(tester.terminalState, containsText('Overview detail'));
      expect(tester.terminalState, isNot(containsText('published pro')));
    });
  });

  test('enter on detail publish action runs publish', () async {
    await testNocterm('detail enter publishes', (tester) async {
      final executor = RecordingConsoleOperationExecutor();
      final controller = ConsoleController(
        repository: FakeConsoleRepository(),
        operationExecutor: executor,
      );
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();
      await tester.sendKey(LogicalKey.tab);
      await tester.sendKey(LogicalKey.tab);
      await tester.pump();
      await tester.sendKey(LogicalKey.enter);
      await tester.pump();
      await tester.pump();

      expect(executor.calls, ['publish:pro:staging']);
      expect(tester.terminalState, containsText('published pro'));
    });
  });

  test('enter on detail rollback action opens rollback prompt', () async {
    await testNocterm('detail enter rollback prompt', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await openRollbackPrompt(tester);

      expect(tester.terminalState, containsText('Rollback target and reason'));
    });
  });

  test('rollback prompt previews cohort impact and requires confirm', () async {
    await testNocterm('rollback preview confirm flow', (tester) async {
      final executor = RecordingConsoleOperationExecutor();
      final controller = ConsoleController(
        repository: FakeConsoleRepository(),
        operationExecutor: executor,
      );
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      // Open the rollback prompt on the selected surface (pro, staging).
      await openRollbackPrompt(tester);
      expect(tester.terminalState, containsText('Rollback target and reason'));

      // Submitting target+reason runs ONLY the preview and shows the
      // cohort-impact note with a confirm step — nothing mutated yet.
      await submitRollbackTarget(tester);
      expect(executor.calls, ['rollbackPreview:pro:staging']);
      expect(tester.terminalState, containsText('Cohort impact'));

      // Confirming executes the rollback.
      await tester.enterText('confirm');
      await tester.sendEnter();
      await tester.pump();
      await tester.pump();
      expect(executor.calls, [
        'rollbackPreview:pro:staging',
        'rollback:pro:staging',
      ]);
      expect(tester.terminalState, containsText('rolled back pro'));
    }, size: const Size(120, 32));
  });

  test('rollback preview blocks other prompts until it completes', () async {
    await testNocterm('rollback preview blocks prompts', (tester) async {
      final executor = SlowPreviewExecutor();
      final controller = ConsoleController(
        repository: FakeConsoleRepository(),
        operationExecutor: executor,
      );
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await openRollbackPrompt(tester);
      await submitRollbackTarget(tester);

      expect(executor.calls, ['rollbackPreview:pro:staging']);
      expect(tester.terminalState, containsText('Previewing rollback'));

      await tester.sendKey(LogicalKey.keyK);
      await tester.sendKey(LogicalKey.keyR);
      await tester.pump();

      expect(tester.terminalState, containsText('Previewing rollback'));
      expect(tester.terminalState, isNot(containsText('Reason for kill')));
      expect(
        tester.terminalState,
        isNot(containsText('Rollback target and reason')),
      );
      expect(executor.calls, ['rollbackPreview:pro:staging']);

      executor.completePreview();
      await tester.pump();
      await tester.pump();

      expect(tester.terminalState, containsText('Type confirm to proceed'));
      expect(tester.terminalState, containsText('Cohort impact'));
    }, size: const Size(120, 32));
  });

  test('escape cancels an in-flight rollback preview', () async {
    await testNocterm('escape cancels rollback preview', (tester) async {
      final executor = SlowPreviewExecutor();
      final controller = ConsoleController(
        repository: FakeConsoleRepository(),
        operationExecutor: executor,
      );
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await openRollbackPrompt(tester);
      await submitRollbackTarget(tester);
      expect(tester.terminalState, containsText('Previewing rollback'));

      await tester.sendKey(LogicalKey.escape);
      await tester.pump();
      executor.completePreview();
      await tester.pump();
      await tester.pump();

      expect(
        tester.terminalState,
        isNot(containsText('Type confirm to proceed')),
      );
      expect(tester.terminalState, isNot(containsText('Cohort impact')));
      expect(executor.calls, ['rollbackPreview:pro:staging']);
    }, size: const Size(120, 32));
  });

  test('confirm aborts when the selection changed since the preview', () async {
    await testNocterm('confirm aborts on changed selection', (tester) async {
      final executor = RecordingConsoleOperationExecutor();
      final controller = ConsoleController(
        repository: FakeConsoleRepository(),
        operationExecutor: executor,
      );
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      // Open the rollback prompt on pro and submit target+reason so the
      // preview runs and the confirm prompt opens.
      await openRollbackPrompt(tester);
      await submitRollbackTarget(tester);
      expect(executor.calls, ['rollbackPreview:pro:staging']);

      // The selection moves to a different surface while the confirm is
      // parked (a mouse tap reaches the same controller method).
      await controller.selectSurface(1);
      await tester.pump();

      // Confirming must NOT roll back the newly selected surface.
      await tester.enterText('confirm');
      await tester.sendEnter();
      await tester.pump();
      await tester.pump();
      expect(executor.calls, ['rollbackPreview:pro:staging']);
      expect(tester.terminalState, containsText('changed'));
    }, size: const Size(120, 32));
  });

  test(
    'a failed preview shows the error and never opens the confirm',
    () async {
      await testNocterm('failed preview aborts rollback flow', (tester) async {
        final executor = FailingPreviewExecutor();
        final controller = ConsoleController(
          repository: FakeConsoleRepository(),
          operationExecutor: executor,
        );
        await tester.pumpComponent(RestageConsoleApp(controller: controller));
        await tester.pump();
        await tester.pump();

        await tester.sendArrowDown();
        await tester.pump();
        await tester.sendKey(LogicalKey.tab);
        await tester.sendKey(LogicalKey.tab);
        await tester.pump();
        await tester.sendArrowDown();
        await tester.sendArrowDown();
        await tester.sendArrowDown();
        await tester.pump();
        await tester.sendKey(LogicalKey.enter);
        await tester.pump();
        await tester.enterText('1 bad build');
        await tester.sendEnter();
        await tester.pump();
        await tester.pump();

        // The failure is visible, the confirm never opens, nothing mutates.
        expect(executor.calls, ['rollbackPreview:pro:staging']);
        expect(tester.terminalState, containsText('preview exploded'));
        expect(
          tester.terminalState,
          isNot(containsText('Type confirm to proceed')),
        );

        // A stray "confirm" afterwards must not resurrect anything.
        await tester.enterText('confirm');
        await tester.sendEnter();
        await tester.pump();
        await tester.pump();
        expect(executor.calls, ['rollbackPreview:pro:staging']);
      }, size: const Size(120, 32));
    },
  );

  test('typing anything but confirm re-prompts and never mutates', () async {
    await testNocterm('non-confirm input does not mutate', (tester) async {
      final executor = RecordingConsoleOperationExecutor();
      final controller = ConsoleController(
        repository: FakeConsoleRepository(),
        operationExecutor: executor,
      );
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await openRollbackPrompt(tester);
      await submitRollbackTarget(tester);
      expect(executor.calls, ['rollbackPreview:pro:staging']);

      // "yes" is not "confirm" — the gate re-prompts and nothing mutates.
      await tester.enterText('yes');
      await tester.sendEnter();
      await tester.pump();
      await tester.pump();
      expect(executor.calls, ['rollbackPreview:pro:staging']);
      expect(tester.terminalState, containsText('Type confirm to proceed'));
    }, size: const Size(120, 32));
  });

  test('escape discards the parked confirm and its impact note', () async {
    await testNocterm('escape clears parked confirm', (tester) async {
      final executor = RecordingConsoleOperationExecutor();
      final controller = ConsoleController(
        repository: FakeConsoleRepository(),
        operationExecutor: executor,
      );
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await openRollbackPrompt(tester);
      await submitRollbackTarget(tester);
      expect(tester.terminalState, containsText('Cohort impact'));

      // Escape closes the confirm and discards the parked operation + note.
      await tester.sendKey(LogicalKey.escape);
      await tester.pump();
      expect(
        tester.terminalState,
        isNot(containsText('Type confirm to proceed')),
      );
      expect(tester.terminalState, isNot(containsText('Cohort impact')));

      // Re-opening the rollback prompt shows no stale note, and a stray
      // "confirm" is just an invalid target line — nothing mutates.
      await tester.sendKey(LogicalKey.keyR);
      await tester.pump();
      expect(tester.terminalState, isNot(containsText('Cohort impact')));
      await tester.enterText('confirm');
      await tester.sendEnter();
      await tester.pump();
      await tester.pump();
      expect(executor.calls, ['rollbackPreview:pro:staging']);
    }, size: const Size(120, 32));
  });

  test('production kill requires confirm and aborts when the selection '
      'changed', () async {
    await testNocterm('production kill confirm pinning', (tester) async {
      final executor = RecordingConsoleOperationExecutor();
      final controller = ConsoleController(
        repository: FakeConsoleRepository(),
        operationExecutor: executor,
      );
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      // Switch to production, then select the pro surface.
      await selectProSurfaceInProduction(tester, controller);

      // Open the kill prompt and submit a reason — production parks a
      // type-confirm instead of killing directly.
      await tester.sendKey(LogicalKey.keyK);
      await tester.pump();
      await tester.enterText('sev1 bad price');
      await tester.sendEnter();
      await tester.pump();
      expect(executor.calls, <String>[]);
      expect(tester.terminalState, containsText('Type confirm to proceed'));

      // The selection moves while the confirm is parked.
      await controller.selectSurface(1);
      await tester.pump();

      // Confirming must NOT kill the newly selected surface.
      await tester.enterText('confirm');
      await tester.sendEnter();
      await tester.pump();
      await tester.pump();
      expect(executor.calls, <String>[]);
      expect(tester.terminalState, containsText('changed'));
    }, size: const Size(120, 32));
  });

  test('production kill executes after typing confirm', () async {
    await testNocterm('production kill confirm executes', (tester) async {
      final executor = RecordingConsoleOperationExecutor();
      final controller = ConsoleController(
        repository: FakeConsoleRepository(),
        operationExecutor: executor,
      );
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await selectProSurfaceInProduction(tester, controller);

      await tester.sendKey(LogicalKey.keyK);
      await tester.pump();
      await tester.enterText('sev1 bad price');
      await tester.sendEnter();
      await tester.pump();
      expect(executor.calls, <String>[]);

      await tester.enterText('confirm');
      await tester.sendEnter();
      await tester.pump();
      await tester.pump();
      expect(executor.calls, ['kill:pro:production']);
    }, size: const Size(120, 32));
  });

  test(
    'same-slug plane switch invalidates a parked live confirmation',
    () async {
      await testNocterm('same-slug confirmation target pinning', (
        tester,
      ) async {
        final executor = RecordingConsoleOperationExecutor();
        final controller = ConsoleController(
          repository: SameSlugConsoleRepository(),
          operationExecutor: executor,
        );
        await tester.pumpComponent(RestageConsoleApp(controller: controller));
        await tester.pump();
        await tester.pump();

        expect(tester.terminalState, containsText('prod (sandbox'));
        expect(tester.terminalState, containsText('prod (live'));
        await controller.selectEnvironment(1);
        await tester.pump();
        await tester.sendArrowDown();
        await tester.pump();
        await tester.sendKey(LogicalKey.tab);
        await tester.sendKey(LogicalKey.tab);
        await tester.pump();

        await tester.sendKey(LogicalKey.keyK);
        await tester.pump();
        await tester.enterText('live target cleanup');
        await tester.sendEnter();
        await tester.pump();
        expect(tester.terminalState, containsText('Type confirm to proceed'));

        await controller.selectEnvironment(0);
        await tester.pump();
        await tester.enterText('confirm');
        await tester.sendEnter();
        await tester.pump();
        await tester.pump();

        expect(executor.calls, <String>[]);
        expect(tester.terminalState, containsText('changed'));
      }, size: const Size(140, 32));
    },
  );

  test('submitting an operation with nothing selected reports a visible '
      'message instead of silently dropping the input', () async {
    await testNocterm('no-selection operation is visible', (tester) async {
      final executor = RecordingConsoleOperationExecutor();
      final controller = ConsoleController(
        repository: EmptyConsoleRepository(),
        operationExecutor: executor,
      );
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      // No surfaces exist; open the rollback prompt anyway and submit.
      await tester.sendKey(LogicalKey.keyR);
      await tester.pump();
      await submitRollbackTarget(tester);

      // The refusal renders in the always-visible message slot (the surface
      // detail panel is not on screen in this state). The trailing period
      // distinguishes the controller's guard message from the detail
      // panel's own "No surface selected" placeholder.
      expect(executor.calls, <String>[]);
      expect(tester.terminalState, containsText('No surface selected.'));
    }, size: const Size(120, 32));
  });

  test('detail panel shows a flow version delivery mode', () async {
    await testNocterm('detail shows delivery mode', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();
      await tester.sendKey(LogicalKey.tab);
      await tester.pump();
      await tester.sendArrowDown();
      await tester.pump();
      await tester.pump();

      // The welcome onboarding surface is general-delivery on its active v3.
      expect(tester.terminalState, containsText('flow (general)'));
      expect(tester.terminalState, containsText('v3 active'));
      expect(tester.terminalState, containsText('sha-3'));
      expect(tester.terminalState, containsText('general'));
    }, size: const Size(160, 32));
  });

  test('audit view renders server audit and local session activity', () async {
    await testNocterm('audit view renders server audit', (tester) async {
      final executor = RecordingConsoleOperationExecutor();
      final controller = ConsoleController(
        repository: FakeConsoleRepository(),
        operationExecutor: executor,
      );
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendKey(LogicalKey.keyP);
      await tester.pump();
      await tester.pump();
      await tester.sendArrowDown();
      await tester.sendArrowDown();
      await tester.pump();

      expect(tester.terminalState, containsText('Server audit'));
      expect(tester.terminalState, containsText('Verdict verified'));
      expect(tester.terminalState, containsText('surfacePublished pro'));
      expect(tester.terminalState, containsText('owner@example.com'));
      expect(tester.terminalState, containsText('Session activity'));
      expect(tester.terminalState, containsText('publish pro exit 0'));
      expect(tester.terminalState, containsText('published pro'));
      expect(tester.terminalState, containsText('Audit detail'));
      expect(tester.terminalState, containsText('Chain verdict'));
      expect(tester.terminalState, containsText('verified through entry 99'));
      expect(tester.terminalState, isNot(containsText('Command preview')));
    }, size: const Size(120, 32));
  });

  test('audit view no longer claims server audit is missing', () async {
    await testNocterm('audit view is server-backed', (tester) async {
      final executor = RecordingConsoleOperationExecutor();
      final controller = ConsoleController(
        repository: FakeConsoleRepository(),
        operationExecutor: executor,
      );
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendKey(LogicalKey.keyP);
      await tester.pump();
      await tester.pump();
      await tester.sendArrowDown();
      await tester.sendArrowDown();
      await tester.pump();

      expect(tester.terminalState, containsText('Session activity'));
      expect(tester.terminalState, containsText('Audit detail'));
      expect(tester.terminalState, containsText('Server audit'));
      expect(
        tester.terminalState,
        isNot(containsText('Server audit not loaded')),
      );
      expect(tester.terminalState, isNot(containsText('Local session only')));
    }, size: const Size(120, 32));
  });

  test('left context renders environment choices', () async {
    await testNocterm('left context renders environments', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      expect(tester.terminalState, containsText('ENVIRONMENTS'));
      expect(tester.terminalState, containsText('production'));
      expect(tester.terminalState, containsText('> staging'));
      expect(tester.terminalState, containsText('ENVIRONMENTS 2'));
    });
  });

  test('keyboard selects environment from left context', () async {
    await testNocterm('keyboard selects environment', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.sendArrowDown();
      await tester.sendArrowDown();
      await tester.sendKey(LogicalKey.enter);
      await tester.pump();
      await tester.pump();

      expect(controller.state.context?.environment, 'production');
      expect(
        tester.terminalState,
        containsText('default / default / production'),
      );
      expect(tester.terminalState, containsText('> production'));
    });
  });

  test('mouse selects environment from left context', () async {
    await testNocterm('mouse selects environment', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.tap(8, 17);
      await tester.pump();
      await tester.pump();

      expect(controller.state.context?.environment, 'production');
      expect(tester.terminalState, containsText('> production'));
    });
  });

  test('tab cycles the three visible dashboard panels', () async {
    await testNocterm('tab cycles visible dashboard panels', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      expect(controller.state.focusedPanel, ConsolePanel.projects);

      await tester.sendKey(LogicalKey.tab);
      await tester.pump();

      expect(controller.state.focusedPanel, ConsolePanel.surfaces);

      await tester.sendKey(LogicalKey.tab);
      await tester.pump();

      expect(controller.state.focusedPanel, ConsolePanel.detail);

      await tester.sendKey(LogicalKey.tab);
      await tester.pump();

      expect(controller.state.focusedPanel, ConsolePanel.projects);
    });
  });

  test('left and right arrows move focus across visible panels', () async {
    await testNocterm('horizontal arrows move panel focus', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      expect(controller.state.focusedPanel, ConsolePanel.projects);

      await tester.sendArrowRight();
      await tester.pump();

      expect(controller.state.focusedPanel, ConsolePanel.surfaces);

      await tester.sendArrowRight();
      await tester.pump();

      expect(controller.state.focusedPanel, ConsolePanel.detail);

      await tester.sendArrowLeft();
      await tester.pump();

      expect(controller.state.focusedPanel, ConsolePanel.surfaces);
    });
  });

  test('mouse click on empty panel areas focuses that panel', () async {
    await testNocterm('empty panel click focuses panel', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.tap(70, 10);
      await tester.pump();

      expect(controller.state.focusedPanel, ConsolePanel.detail);

      await tester.tap(30, 10);
      await tester.pump();

      expect(controller.state.focusedPanel, ConsolePanel.surfaces);

      await tester.tap(15, 10);
      await tester.pump();

      expect(controller.state.focusedPanel, ConsolePanel.projects);
    });
  });

  test('arrow up from top left nav focuses command search', () async {
    await testNocterm('arrow reaches search', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowUp();
      await tester.enterText('wel');
      await tester.pump();

      expect(tester.terminalState, containsText('Search results'));
      expect(tester.terminalState, containsText('welcome'));
      expect(tester.terminalState, isNot(containsText('upsell')));
    });
  });

  test('arrow keys on surfaces panel change selected surface detail', () async {
    await testNocterm('surfaces panel arrows change surface detail', (
      tester,
    ) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();
      await tester.sendKey(LogicalKey.tab);
      await tester.pump();
      await tester.sendArrowDown();
      await tester.pump();
      await tester.pump();

      expect(controller.state.focusedPanel, ConsolePanel.surfaces);
      expect(tester.terminalState, containsText('welcome'));
      expect(tester.terminalState, containsText('flow'));
    });
  });

  test(
    'keyboard can navigate surface filters from the surfaces panel',
    () async {
      await testNocterm('keyboard navigates surface filters', (tester) async {
        final controller = ConsoleController(
          repository: FakeConsoleRepository(),
        );
        await tester.pumpComponent(RestageConsoleApp(controller: controller));
        await tester.pump();
        await tester.pump();

        await tester.sendArrowDown();
        await tester.pump();
        await tester.sendKey(LogicalKey.tab);
        await tester.sendArrowUp();
        await tester.sendArrowRight();
        await tester.pump();

        expect(controller.state.focusedPanel, ConsolePanel.surfaces);
        expect(tester.terminalState, containsText('[pay]'));
        expect(tester.terminalState, containsText('pro'));
        expect(tester.terminalState, containsText('upsell'));
        expect(
          tester.terminalState,
          isNot(containsText('welcome  onboarding')),
        );
      });
    },
  );

  test('enter commits selected surface filter and arrows move rows', () async {
    await testNocterm('enter commits filter into rows', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();
      await tester.sendKey(LogicalKey.tab);
      await tester.pump();
      await tester.sendArrowUp();
      await tester.pump();
      await tester.sendArrowRight();
      await tester.pump();

      const brand = Color.fromRGB(255, 126, 107);
      const focus = Color.fromRGB(52, 211, 153);

      expect(
        tester.terminalState,
        hasStyledText('[pay]', const TextStyle(color: focus)),
      );

      await tester.sendKey(LogicalKey.enter);
      await tester.pump();

      expect(
        tester.terminalState,
        hasStyledText('[pay]', const TextStyle(color: brand)),
      );

      await tester.sendArrowDown();
      await tester.pump();
      await tester.pump();

      expect(controller.state.selectedSurface?.slug, 'upsell');
      expect(tester.terminalState, containsText('Detail: upsell'));
    });
  });

  test('keyboard can reach empty second-row surface filters', () async {
    await testNocterm('keyboard reaches empty second-row filters', (
      tester,
    ) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();
      await tester.sendKey(LogicalKey.tab);
      await tester.pump();
      await tester.sendArrowUp();
      await tester.pump();
      await tester.sendArrowDown();
      await tester.pump();

      expect(controller.state.focusedPanel, ConsolePanel.surfaces);
      expect(tester.terminalState, containsText('No surfaces'));
      expect(tester.terminalState, containsText('[all]'));
      expect(tester.terminalState, containsText('[msg]'));

      await tester.sendArrowRight();
      await tester.pump();

      expect(tester.terminalState, containsText('No surfaces'));
      expect(tester.terminalState, containsText('[surv]'));

      await tester.sendArrowLeft();
      await tester.sendArrowLeft();
      await tester.pump();

      expect(tester.terminalState, containsText('welcome'));
    });
  });

  test('console exposes every surface type filter', () async {
    await testNocterm('console exposes every surface type filter', (
      tester,
    ) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();

      expect(tester.terminalState, containsText('[all]'));
      expect(tester.terminalState, containsText('[pay]'));
      expect(tester.terminalState, containsText('[onbd]'));
      expect(tester.terminalState, containsText('[msg]'));
      expect(tester.terminalState, containsText('[surv]'));
    });
  });

  test('arrow keys on detail panel do not change selected surface', () async {
    await testNocterm('detail panel arrows do not change selected surface', (
      tester,
    ) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();
      await tester.sendKey(LogicalKey.tab);
      await tester.sendKey(LogicalKey.tab);
      await tester.pump();

      expect(controller.state.focusedPanel, ConsolePanel.detail);

      await tester.sendArrowDown();
      await tester.pump();
      await tester.pump();

      expect(controller.state.selectedSurface?.slug, 'pro');
      expect(tester.terminalState, containsText('Detail: pro'));
    });
  });

  test('detail panel allows flow rollback', () async {
    await testNocterm('detail labels flow rollback', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();
      await tester.sendKey(LogicalKey.tab);
      await tester.pump();
      await tester.sendArrowDown();
      await tester.pump();
      await tester.pump();

      // The shape line now carries the active version's delivery mode.
      expect(tester.terminalState, containsText('flow (general) / unlocked'));
    }, size: const Size(160, 32));
  });

  test(
    'slash focuses command search and text filters surface results',
    () async {
      await testNocterm('slash focuses command search', (tester) async {
        final controller = ConsoleController(
          repository: FakeConsoleRepository(),
        );
        await tester.pumpComponent(RestageConsoleApp(controller: controller));
        await tester.pump();
        await tester.pump();

        await tester.sendKey(LogicalKey.slash);
        await tester.enterText('wel');
        await tester.pump();

        expect(tester.terminalState, containsText('Search results'));
        expect(tester.terminalState, containsText('welcome'));
        expect(tester.terminalState, isNot(containsText('upsell')));
      });
    },
  );

  test('search can start rollback prompt for the selected surface', () async {
    await testNocterm('search starts rollback prompt', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendKey(LogicalKey.slash);
      await tester.enterText('rollback');
      expect(tester.terminalState, containsText('Search results'));

      await tester.sendEnter();
      await tester.pump();

      expect(tester.terminalState, containsText('Rollback target and reason'));
    });
  });

  test('mouse click selects a surface row', () async {
    await testNocterm('mouse click selects a surface row', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();

      await tester.tap(34, 15);
      await tester.pump();
      await tester.pump();

      expect(tester.terminalState, containsText('Detail: welcome'));
      expect(tester.terminalState, containsText('delivery'));
      expect(tester.terminalState, containsText('flow'));
    });
  });

  test(
    'mouse click on surface row focuses surfaces panel for arrows',
    () async {
      await testNocterm('mouse row click focuses surfaces panel', (
        tester,
      ) async {
        final controller = ConsoleController(
          repository: FakeConsoleRepository(),
        );
        await tester.pumpComponent(RestageConsoleApp(controller: controller));
        await tester.pump();
        await tester.pump();

        await tester.sendArrowDown();
        await tester.pump();

        await tester.tap(34, 15);
        await tester.pump();

        expect(controller.state.selectedSurface?.slug, 'welcome');

        await tester.sendArrowDown();
        await tester.pump();
        await tester.pump();

        expect(controller.state.focusedPanel, ConsolePanel.surfaces);
        expect(controller.state.selectedSurface?.slug, 'upsell');
        expect(tester.terminalState, containsText('Detail: upsell'));
      });
    },
  );

  test('mouse click focuses command search', () async {
    await testNocterm('mouse click focuses command search', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.tap(10, 5);
      await tester.enterText('wel');
      await tester.pump();

      expect(tester.terminalState, containsText('Search results'));
      expect(tester.terminalState, containsText('welcome'));
      expect(tester.terminalState, isNot(containsText('upsell')));
    });
  });

  test('mouse click on paywall filter limits surface rows', () async {
    await testNocterm('mouse click paywall filter', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();

      await tester.tap(33, 11);
      await tester.pump();

      expect(tester.terminalState, containsText('pro'));
      expect(tester.terminalState, containsText('upsell'));
      expect(tester.terminalState, isNot(containsText('welcome')));
    });
  });

  test('mouse click on populated filter commits row navigation', () async {
    await testNocterm('mouse populated filter commits rows', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();

      await tester.tap(33, 11);
      await tester.pump();

      const brand = Color.fromRGB(255, 126, 107);

      expect(
        tester.terminalState,
        hasStyledText('[pay]', const TextStyle(color: brand)),
      );

      await tester.sendArrowDown();
      await tester.pump();
      await tester.pump();

      expect(controller.state.selectedSurface?.slug, 'upsell');
      expect(tester.terminalState, containsText('Detail: upsell'));
    });
  });

  test('mouse click on empty filter keeps filters visible', () async {
    await testNocterm('mouse empty filter keeps controls', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();

      await tester.tap(33, 12);
      await tester.pump();

      expect(tester.terminalState, containsText('No surfaces'));
      expect(tester.terminalState, containsText('[all]'));
      expect(tester.terminalState, containsText('[msg]'));
      expect(tester.terminalState, containsText('[surv]'));

      await tester.tap(33, 11);
      await tester.pump();

      expect(tester.terminalState, containsText('upsell'));
    });
  });

  test(
    'arrow up after mouse filter selection returns to filter navigation',
    () async {
      await testNocterm('mouse filter selection can return to filters', (
        tester,
      ) async {
        final controller = ConsoleController(
          repository: FakeConsoleRepository(),
        );
        await tester.pumpComponent(RestageConsoleApp(controller: controller));
        await tester.pump();
        await tester.pump();

        await tester.sendArrowDown();
        await tester.pump();

        await tester.tap(33, 11);
        await tester.pump();

        expect(tester.terminalState, containsText('upsell'));

        await tester.sendArrowUp();
        await tester.pump();
        await tester.sendArrowRight();
        await tester.pump();

        expect(controller.state.focusedPanel, ConsolePanel.surfaces);
        expect(tester.terminalState, containsText('[onbd]'));
        expect(tester.terminalState, containsText('welcome'));
        expect(tester.terminalState, isNot(containsText('upsell')));
      });
    },
  );

  test('mouse click on left nav changes active view', () async {
    await testNocterm('mouse click nav changes active view', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.tap(8, 13);
      await tester.pump();

      expect(tester.terminalState, containsText('> Audit trail'));
      expect(tester.terminalState, containsText('Server audit'));
    });
  });

  test('mouse click on rollback action opens rollback prompt', () async {
    await testNocterm('mouse click action opens prompt', (tester) async {
      final controller = ConsoleController(repository: FakeConsoleRepository());
      await tester.pumpComponent(RestageConsoleApp(controller: controller));
      await tester.pump();
      await tester.pump();

      await tester.sendArrowDown();
      await tester.pump();
      await tester.tap(70, 19);
      await tester.pump();

      expect(tester.terminalState, containsText('Rollback target and reason'));
    });
  });
}

class FakeConsoleRepository implements ConsoleRepository {
  @override
  Future<ConsoleSnapshot> load() async => const ConsoleSnapshot(
    context: ConsoleContext(
      organizationSlug: 'restage',
      project: 'default',
      appId: 5,
      app: 'default',
      environmentTargetId: 12,
      namedEnvironmentId: 22,
      environment: 'staging',
      runtimePlane: RuntimePlane.live,
    ),
    projects: [ConsoleProject(slug: 'default', name: 'Default')],
    apps: [ConsoleAppTarget(appId: 5, slug: 'default', name: 'Default')],
    environments: [
      ConsoleEnvironmentTarget(
        environmentTargetId: 13,
        namedEnvironmentId: 23,
        slug: 'production',
        runtimePlane: RuntimePlane.live,
      ),
      ConsoleEnvironmentTarget(
        environmentTargetId: 12,
        namedEnvironmentId: 22,
        slug: 'staging',
        runtimePlane: RuntimePlane.live,
      ),
    ],
    surfaces: [
      ConsoleSurface(surfaceType: 'paywall', slug: 'pro', name: 'Pro'),
      ConsoleSurface(
        surfaceType: 'onboarding',
        slug: 'welcome',
        name: 'Welcome',
      ),
      ConsoleSurface(surfaceType: 'paywall', slug: 'upsell', name: 'Upsell'),
    ],
  );

  @override
  Future<SurfaceStatusResult> status(
    ConsoleSurface surface, {
    required ConsoleContext context,
  }) async => SurfaceStatusResult(
    surfaceType: surface.surfaceType,
    surfaceSlug: surface.slug,
    environmentSlug: context.environment,
    liveVersion: surface.slug == 'pro'
        ? 2
        : surface.slug == 'welcome'
        ? 3
        : null,
    locked: false,
    deliveryShape: surface.surfaceType == 'paywall' ? 'blob' : 'flow',
    versions: surface.slug == 'pro'
        ? [
            SurfaceVersionResult(
              version: 2,
              publishedAt: DateTime.parse('2026-06-01T00:00:00.000Z'),
              contentHash: 'sha-2',
              isActive: true,
            ),
            SurfaceVersionResult(
              version: 1,
              publishedAt: DateTime.parse('2026-05-31T00:00:00.000Z'),
              contentHash: 'sha-1',
              isActive: false,
            ),
          ]
        : surface.slug == 'welcome'
        ? [
            SurfaceVersionResult(
              version: 3,
              publishedAt: DateTime.parse('2026-06-02T00:00:00.000Z'),
              contentHash: 'sha-3',
              isActive: true,
              deliveryMode: 'general',
            ),
            SurfaceVersionResult(
              version: 2,
              publishedAt: DateTime.parse('2026-06-01T00:00:00.000Z'),
              contentHash: 'sha-2b',
              isActive: false,
              deliveryMode: 'typed',
            ),
          ]
        : const [],
  );

  @override
  Future<List<SurfaceAuditLogEntry>> auditLog({
    required ConsoleContext context,
  }) async => [
    SurfaceAuditLogEntry(
      action: 'surfacePublished',
      actorType: 'human',
      actorEmail: 'owner@example.com',
      outcome: 'success',
      severity: 'notice',
      targetType: 'surface',
      targetId: '42',
      occurredAt: DateTime.parse('2026-06-29T18:17:51.000Z'),
      reason: 'demo publish',
      context: const {
        'surfaceSlug': 'pro',
        'surfaceType': 'paywall',
        'environmentSlug': 'staging',
      },
      chainState: 'chained',
      chainVerified: true,
      entryId: 99,
    ),
  ];

  @override
  Future<SurfaceChainVerdictResult> surfaceChainVerdict({
    required ConsoleContext context,
  }) async => SurfaceChainVerdictResult(
    status: 'verified',
    verifiedThroughEntryId: 99,
    verifiedThroughOccurredAt: null,
    failedEntryId: null,
    failedCheck: null,
    lastRunAt: DateTime.parse('2026-06-29T18:30:00.000Z'),
  );
}

class ManifestConsoleRepository extends FakeConsoleRepository {
  @override
  Future<ConsoleSnapshot> load() async {
    final snapshot = await super.load();
    return ConsoleSnapshot(
      context: snapshot.context,
      projects: snapshot.projects,
      apps: snapshot.apps,
      environments: snapshot.environments,
      surfaces: [
        ConsoleSurface(
          surfaceType: 'paywall',
          slug: 'pro',
          name: 'Pro',
          contractVersion: 3,
          sourceKind: 'screen',
          payloadKind: 'blob',
          hasManifestIdentity: true,
        ),
      ],
    );
  }
}

/// Navigate from the initial console state to the rollback prompt on the
/// selected `pro` surface (surfaces panel, rollback action, enter).
Future<void> openRollbackPrompt(NoctermTester tester) async {
  await tester.sendArrowDown();
  await tester.pump();
  await tester.sendKey(LogicalKey.tab);
  await tester.sendKey(LogicalKey.tab);
  await tester.pump();
  await tester.sendArrowDown();
  await tester.sendArrowDown();
  await tester.sendArrowDown();
  await tester.pump();
  await tester.sendKey(LogicalKey.enter);
  await tester.pump();
}

/// Submit the standard rollback target + reason into the open prompt.
Future<void> submitRollbackTarget(NoctermTester tester) async {
  await tester.enterText('1 bad build');
  await tester.sendEnter();
  await tester.pump();
  await tester.pump();
}

/// Switch to production and focus the surfaces panel on the `pro` surface.
Future<void> selectProSurfaceInProduction(
  NoctermTester tester,
  ConsoleController controller,
) async {
  await controller.selectEnvironment(0);
  await tester.pump();
  await tester.sendArrowDown();
  await tester.pump();
  await tester.sendKey(LogicalKey.tab);
  await tester.sendKey(LogicalKey.tab);
  await tester.pump();
}

/// A repository with no surfaces: exercises the operation paths when nothing
/// is (or can be) selected.
class EmptyConsoleRepository extends FakeConsoleRepository {
  @override
  Future<ConsoleSnapshot> load() async => const ConsoleSnapshot(
    context: ConsoleContext(
      organizationSlug: 'restage',
      project: 'default',
      appId: 5,
      app: 'default',
      environmentTargetId: 12,
      namedEnvironmentId: 22,
      environment: 'staging',
      runtimePlane: RuntimePlane.live,
    ),
    projects: [ConsoleProject(slug: 'default', name: 'Default')],
    apps: [ConsoleAppTarget(appId: 5, slug: 'default', name: 'Default')],
    environments: [
      ConsoleEnvironmentTarget(
        environmentTargetId: 13,
        namedEnvironmentId: 23,
        slug: 'production',
        runtimePlane: RuntimePlane.live,
      ),
      ConsoleEnvironmentTarget(
        environmentTargetId: 12,
        namedEnvironmentId: 22,
        slug: 'staging',
        runtimePlane: RuntimePlane.live,
      ),
    ],
    surfaces: [],
  );
}

class SameSlugConsoleRepository extends FakeConsoleRepository {
  @override
  Future<ConsoleSnapshot> load() async => const ConsoleSnapshot(
    context: ConsoleContext(
      organizationSlug: 'restage',
      project: 'default',
      appId: 5,
      app: 'default',
      environmentTargetId: 31,
      namedEnvironmentId: 41,
      environment: 'prod',
      runtimePlane: RuntimePlane.sandbox,
    ),
    projects: [ConsoleProject(slug: 'default', name: 'Default')],
    apps: [ConsoleAppTarget(appId: 5, slug: 'default', name: 'Default')],
    environments: [
      ConsoleEnvironmentTarget(
        environmentTargetId: 31,
        namedEnvironmentId: 41,
        slug: 'prod',
        runtimePlane: RuntimePlane.sandbox,
      ),
      ConsoleEnvironmentTarget(
        environmentTargetId: 32,
        namedEnvironmentId: 41,
        slug: 'prod',
        runtimePlane: RuntimePlane.live,
      ),
    ],
    surfaces: [
      ConsoleSurface(surfaceType: 'paywall', slug: 'pro', name: 'Pro'),
    ],
  );
}

/// An executor whose preview fails: exercises the abort path between the
/// rollback prompt and the confirm.
class FailingPreviewExecutor extends RecordingConsoleOperationExecutor {
  @override
  Future<ConsoleOperationResult> rollbackPreview({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required int toVersion,
  }) async {
    calls.add('rollbackPreview:${surface.slug}:${context.environment}');
    return const ConsoleOperationResult(
      exitCode: 1,
      stdout: '',
      stderr: 'preview exploded\n',
    );
  }
}

class SlowPreviewExecutor extends RecordingConsoleOperationExecutor {
  final _previewCompleter = Completer<ConsoleOperationResult>();

  void completePreview() {
    _previewCompleter.complete(
      const ConsoleOperationResult(
        exitCode: 0,
        stdout:
            'Cohort impact: live clients on the current contract will render '
            'v1.\n'
            'Preview only — nothing was rolled back. Re-run without --preview '
            'to roll back.\n',
        stderr: '',
      ),
    );
  }

  @override
  Future<ConsoleOperationResult> rollbackPreview({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required int toVersion,
  }) {
    calls.add('rollbackPreview:${surface.slug}:${context.environment}');
    return _previewCompleter.future;
  }
}

class RecordingConsoleOperationExecutor implements ConsoleOperationExecutor {
  final calls = <String>[];

  @override
  Future<ConsoleOperationResult> kill({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
    required bool frozen,
    bool confirmedProduction = false,
  }) async {
    calls.add('kill:${surface.slug}:${context.environment}');
    return ConsoleOperationResult(
      exitCode: 0,
      stdout: 'killed ${surface.slug}\n',
      stderr: '',
    );
  }

  @override
  Future<ConsoleOperationResult> rollback({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
    required int toVersion,
    required bool freeze,
    bool confirmedProduction = false,
  }) async {
    calls.add('rollback:${surface.slug}:${context.environment}');
    return ConsoleOperationResult(
      exitCode: 0,
      stdout: 'rolled back ${surface.slug}\n',
      stderr: '',
    );
  }

  @override
  Future<ConsoleOperationResult> rollbackPreview({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required int toVersion,
  }) async {
    calls.add('rollbackPreview:${surface.slug}:${context.environment}');
    return ConsoleOperationResult(
      exitCode: 0,
      stdout:
          'Cohort impact: live clients on the current contract will render '
          'v$toVersion.\n'
          'Preview only — nothing was rolled back. Re-run without --preview '
          'to roll back.\n',
      stderr: '',
    );
  }

  @override
  Future<ConsoleOperationResult> freeze({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
  }) async {
    calls.add('freeze:${surface.slug}:${context.environment}');
    return ConsoleOperationResult(
      exitCode: 0,
      stdout: 'froze ${surface.slug}\n',
      stderr: '',
    );
  }

  @override
  Future<ConsoleOperationResult> unfreeze({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
  }) async {
    calls.add('unfreeze:${surface.slug}:${context.environment}');
    return ConsoleOperationResult(
      exitCode: 0,
      stdout: 'unfroze ${surface.slug}\n',
      stderr: '',
    );
  }

  @override
  Future<ConsoleOperationResult> publish({
    required ConsoleContext context,
    required ConsoleSurface surface,
  }) async {
    calls.add('publish:${surface.slug}:${context.environment}');
    return ConsoleOperationResult(
      exitCode: 0,
      stdout: 'published ${surface.slug}\n',
      stderr: '',
    );
  }
}
