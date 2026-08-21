# Flows

`restage_codegen` generates the `SurfaceFlowRef<R>` and, when the flow uses host actions, a `FlowActionRegistry`. The example below shows the public API that generated code and your app code use together.

For the normal bundled path, `RestageFlowGraph` uses `AssetFlowResolver` by
default; it can also be passed explicitly as shown below. The resolver loads
the generated flow artifact closure from the app bundle. It does not determine
the flow's identity or publication category; generated publication metadata is
the authority for those.

```dart
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

final class FirstRunResult {
  const FirstRunResult({required this.completed});

  final bool completed;
}

abstract final class FirstRunFlowDescriptor {
  static final SurfaceFlowRef<FirstRunResult> ref =
      SurfaceFlowRef<FirstRunResult>(
    id: 'first_run',
    version: 1,
    minClient: 3,
    surface: Surface.onboarding,
    decodeResult: _decodeResult,
  );

  static FirstRunResult _decodeResult(Map<String, Object?> result) {
    if (result.length != 1 || result['completed'] is! bool) {
      throw const FormatException('Invalid first_run result.');
    }
    return FirstRunResult(completed: result['completed']! as bool);
  }
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

`FlowUnavailablePolicy` is required. Missing assets, incompatible versions, unsupported document features, action-contract mismatches, and build-time render failures fall back or hide instead of running the flow partway. Generated result decoders reject missing, extra, or mistyped fields, so a bad terminal result fails closed before `onComplete` runs.

## Host actions

Host actions are typed, app-owned capability boundaries. A flow can select among the action capabilities your installed app already shipped. It cannot define new executable behavior. Handlers receive typed args plus `FlowActionContext` and return typed results the runtime encodes back into the flow.

## Data minimization

Flow-originated custom events, terminal results, child-flow results, and action arguments are filtered through explicit declarations before they leave the flow runtime. Do not put secrets, credentials, private tokens, or unreleased business logic in flow documents, generated Dart, or bundled RFW assets.

**The experiment eligibility contract.** Every hosted fetch carries a small rendering-capability contract hash: the built-in catalog version this build ships plus the custom widget libraries it has registered (the full list is uploaded only when the server hasn't seen that hash before). The server uses it only for experiment eligibility: a client is enrolled only in experiments whose every arm this build can render; a client that can't render an arm sits out the experiment and is served the active version, never a broken one. The contract describes what this build can draw. It carries no user, device, or host-supplied render data.
