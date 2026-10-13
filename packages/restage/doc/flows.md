# Flows

For an authored `@FlowGraph`, use its generated `<FlowName>Surface(...)` widget.
It supplies the flow reference, typed completion callback, widget registration,
the compiled original flow as fallback, and a placement. No placement name is
needed.
The [authoring guide](../skills/restage-authoring/references/flows.md) shows the
source and generated mount together.

## Lower-level flow hosting

Use `RestageFlowGraph` when supplying a reference and fallback policy yourself.
The example below writes the reference and actions by hand to show the runtime
API.
`AssetFlowResolver` loads the generated flow artifacts from the app bundle.

```dart
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

final class FirstRunResult {
  const FirstRunResult({required this.completed});

  final bool completed;
}

final SurfaceFlowRef<FirstRunResult> firstRunFlowRef =
    SurfaceFlowRef<FirstRunResult>(
  id: 'first_run',
  version: 1,
  minClient: 3,
  surface: Surface.onboarding,
  decodeResult: _decodeFirstRunResult,
);

FirstRunResult _decodeFirstRunResult(Map<String, Object?> result) {
  if (result.length != 1 || result['completed'] is! bool) {
    throw const FormatException('Invalid first_run result.');
  }
  return FirstRunResult(completed: result['completed']! as bool);
}

final class NotificationResult {
  const NotificationResult({required this.granted});

  final bool granted;
}

final class FirstRunActions implements FlowActionRegistry {
  FirstRunActions({
    required FlowActionHandler<void, NotificationResult>
        requestNotifications,
  }) : flowActionBindings = {
          'requestNotifications': FlowActionBinding<void, NotificationResult>(
            actionName: 'requestNotifications',
            contractVersion: 1,
            argsSchema: const FlowActionSchema.object({}),
            resultSchema: const FlowActionSchema.object({
              'granted': FlowActionSchemaField(
                required: true,
                schema: FlowActionSchema.bool(),
              ),
            }),
            minClient: 3,
            idempotent: false,
            handler: requestNotifications,
            decodeArgs: (_) {},
            encodeResult: (value) => {'granted': value.granted},
          ),
        };

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;
}

class FlowEntry extends StatelessWidget {
  const FlowEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return RestageFlowGraph<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: const AssetFlowResolver(),
      actions: FirstRunActions(
        requestNotifications: (_, context) async {
          return const NotificationResult(granted: true);
        },
      ),
      unavailable: FlowUnavailablePolicy.fallback(
        builder: (context, error) => Text(error.message),
      ),
      onComplete: (result) {
        Navigator.of(context).pushReplacementNamed('/home');
      },
    );
  }
}
```

`FlowUnavailablePolicy` is required. Missing assets, incompatible versions, flow features the app doesn't support, actions that don't match the app's, and render failures all fall back or hide the flow instead of running it partway. Generated result decoders reject missing, extra, or mistyped fields, so a bad result stops the flow before `onComplete` runs.

## Host actions

Host actions are typed operations your app provides. A flow can call only the
actions your installed app has. Their handlers are Dart compiled into your app,
so adding or changing one requires an app release. A handler receives typed
arguments and a `FlowActionContext`, and returns a typed result that the flow
can use.

## Data minimization

Custom events, results, child-flow results, and action arguments from a flow pass only the fields you declared before they reach your app. Do not put secrets, credentials, private tokens, or unreleased business logic in flow documents, generated Dart, or bundled RFW assets.

**Experiment eligibility.** Every hosted fetch carries a small hash of what this build can render: the built-in catalog version plus the custom widget libraries it registered. The full list is uploaded only when the server hasn't seen that hash before. The server uses it only to decide experiment eligibility: an app is enrolled only in experiments whose every arm it can render. An app that can't render an arm sits out the experiment and gets the live version. The hash describes what this build can draw. It carries no user, device, or host data.
