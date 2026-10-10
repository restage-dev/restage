import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:restage_cli/src/api/delivery_management_api.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/commands/live_guard.dart';
import 'package:restage_cli/src/commands/surface_identity.dart';
import 'package:restage_cli/src/delivery/measurement_impact.dart';
import 'package:restage_cli/src/operations/operation.dart';
import 'package:restage_cli/src/operations/operations.dart';

const _groupDescriptions = <String, String>{
  'org': 'Rename an organization.',
  'app': 'Rename or delete an app.',
  'app-config':
      "Read or change an app's iOS bundle id, Android package, and web "
      'domain, and see what each platform has sent.',
  'products': 'List or import the store products for an app.',
  'slots': "List or set an app's product slots.",
  'stores': "List an app's store connections.",
  'keys':
      "List or revoke an environment's API keys, or find where a key "
      'belongs. Create keys in the dashboard.',
  'audit': 'Read server audit logs and compliance exports.',
  'surface draft':
      'Download or push the draft a surface has saved in the dashboard.',
};

/// The commands for the shared operations under [prefix] (such as
/// `surface `), grouped by path, leaving out the top-level [exclude] groups.
List<Command<int>> operationCommands(
  CommandIo io, {
  String prefix = '',
  Set<String> exclude = const {},
}) {
  final bySegment = <String, List<Operation>>{};
  for (final operation in sharedOperations) {
    if (!operation.cliPath.startsWith(prefix)) continue;
    final segment = operation.cliPath.substring(prefix.length).split(' ').first;
    if (exclude.contains(segment)) continue;
    bySegment.putIfAbsent(segment, () => []).add(operation);
  }
  return [
    for (final MapEntry(key: segment, value: operations) in bySegment.entries)
      if (operations.length == 1 &&
          operations.single.cliPath == '$prefix$segment')
        if (operations.single.reviewMeasurementImpact != null)
          _ReviewedSpecCommand(operations.single, io)
        else
          SpecCommand(operations.single, io)
      else
        _GroupCommand(
          segment,
          _groupDescriptions['$prefix$segment']!,
          operationCommands(io, prefix: '$prefix$segment '),
        ),
  ];
}

class _GroupCommand extends Command<int> {
  _GroupCommand(this.name, this.description, List<Command<int>> children) {
    children.forEach(addSubcommand);
  }

  @override
  final String name;

  @override
  final String description;
}

/// One shared [Operation] as a CLI command.
class SpecCommand extends Command<int> {
  /// Construct the command for [operation].
  SpecCommand(this.operation, this._io) {
    if (operation.surface) addSurfaceTypeOption(argParser);
    addScopeOptions(argParser, operation.scope);
    for (final param in operation.params) {
      if (param.mcpOnly || param.positional) continue;
      if (param.type == ParamType.boolean) {
        argParser.addFlag(param.cli!, negatable: false, help: param.help);
      } else {
        argParser.addOption(
          param.cli!,
          allowed: param.allowed,
          help: param.help,
        );
      }
    }
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Emit JSON instead of the default text output. Use it in scripts.',
    );
  }

  /// The operation this command runs.
  final Operation operation;
  final CommandIo _io;

  OperationParam? get _positional =>
      operation.params.where((param) => param.positional).firstOrNull;

  @override
  String get name => operation.cliPath.split(' ').last;

  @override
  String get description => operation.description;

  @override
  String get invocation {
    final positional = operation.surface
        ? '<id>'
        : _positional?.cli?.split(' ').last;
    return positional == null
        ? super.invocation
        : 'restage ${operation.cliPath} $positional [arguments]';
  }

  @override
  Future<int> run() async {
    final stderr = _io.stderr;
    final results = argResults!;
    final values = <String, Object?>{};
    String? slug;
    if (operation.surface) {
      slug = resolveSingleSlug(argResults: results, stderr: stderr);
      if (slug == null) return 1;
    }
    for (final param in operation.params) {
      if (param.mcpOnly) continue;
      final String? raw;
      if (param.positional) {
        raw = results.rest.length == 1 ? results.rest.single : null;
        if (raw == null) {
          stderr.writeln('Expected exactly one ${param.cli}.');
          return 1;
        }
      } else if (param.type == ParamType.boolean) {
        if (results.wasParsed(param.cli!)) values[param.key] = true;
        continue;
      } else {
        raw = results[param.cli!] as String?;
      }
      if (raw == null) continue;
      switch (param.type) {
        case ParamType.integer:
          final parsed = int.tryParse(raw);
          if (parsed == null) {
            stderr.writeln(
              param.positional
                  ? 'Expected exactly one ${param.cli}.'
                  : 'Expected an integer for --${param.cli}.',
            );
            return 1;
          }
          values[param.key] = parsed;
        case ParamType.clearable:
          values[param.key] = raw == unmappedProductId ? null : raw;
        case ParamType.string || ParamType.boolean:
          values[param.key] = raw;
      }
    }
    final args = OperationArgs(values);
    final invalid = operation.validate?.call(args, _flagOf);
    if (invalid != null) {
      stderr.writeln(invalid);
      return 1;
    }
    for (final param in operation.params) {
      if (param.required && !param.mcpOnly && !args.has(param.key)) {
        final values = param.allowed == null
            ? ''
            : ' <${param.allowed!.join('|')}>';
        stderr.writeln('Required: --${param.cli}$values.');
        return 1;
      }
    }
    SurfaceReadSelection? selection;
    if (slug != null) {
      selection = operation.readsSurface
          ? await resolveSurfaceReadSelection(
              argResults: results,
              fixedSurfaceType: null,
              slug: slug,
              stderr: stderr,
            )
          : switch (await resolveSurfaceLifecycleIdentity(
              argResults: results,
              fixedSurfaceType: null,
              slug: slug,
              stderr: stderr,
            )) {
              final identity? => SurfaceReadSelection.of(identity),
              null => null,
            };
      if (selection == null) return 1;
    }

    return runAuthed(_io, results, operation.scope, (ctx) async {
      final resolved = ctx.target;
      final identity = await selection?.resolve(
        api: ctx.api,
        project: resolved?.project ?? ctx.project!,
        app: resolved?.app ?? ctx.app!.slug,
        organizationId: resolved?.organizationId ?? ctx.organizationId,
        appId: resolved?.appId ?? ctx.app?.appId,
      );
      final target = OperationTarget(
        api: ctx.api,
        syntax: currentSelectorSyntax,
        organizationId: ctx.organizationId,
        project: resolved?.project ?? ctx.project,
        app: resolved?.app ?? ctx.app?.slug,
        appId: resolved?.appId ?? ctx.app?.appId,
        environment: resolved?.environment,
        environmentTargetId: resolved?.environmentTargetId,
        runtimePlane: resolved?.runtimePlane,
        planeIsImplicit: resolved?.planeIsImplicit ?? true,
        identity: identity,
        snapshot: ctx.snapshot,
      );
      var callArgs = args;
      if (operation.reviewMeasurementImpact case final reviewImpact?) {
        final live = target.snapshot
            ?.targets(projectSlug: target.project!, appSlug: target.app!)
            .any((at) => at.runtimePlane == RuntimePlane.live);
        if (!await confirmLiveChange(
          command: this,
          interactive: _io.interactive,
          stdout: _io.stdout,
          stderr: _io.stderr,
          live: live ?? true,
          impactLine:
              'This archives "${identity!.slug}" across every target of "${target.app}".',
        )) {
          return 1;
        }
        try {
          final review = await reviewImpact(target);
          if (args.optBool('reviewOnly') ?? false) {
            _io.stdout.writeln(formatDeliveryMeasurementMutationReview(review));
            return review.refusalCodes.isEmpty ? 0 : 1;
          }
          final proceed = await confirmDeliveryMeasurementProceed(
            review: review,
            interactive: _io.interactive,
            stdout: _io.stdout,
            reviewedDigest: args.optStr('reviewedDigest'),
            operationId: args.optStr('operationId'),
          );
          if (proceed == null) {
            _io.stdout.writeln('Aborted.');
            return 1;
          }
          callArgs = OperationArgs(args.values, measurementProceed: proceed);
          _io.stdout.writeln('Operation ${proceed.operationId}.');
        } on DeliveryManagementResponseException catch (error) {
          _io.stderr.writeln(error);
          return 2;
        } on DeliveryMeasurementReviewRequired catch (error) {
          _io.stderr.writeln(
            'Review the complete warnings, then pass --reviewed-digest ${error.review.digest.hex}.',
          );
          return 1;
        } on FormatException catch (error) {
          _io.stderr.writeln(error.message);
          return 1;
        }
      }
      final value = await operation.call(target, callArgs);
      final out = _io.stdout;
      if (results['json'] as bool) {
        out.writeln(jsonEncode(operation.json(value)));
      } else if (operation.render case final render?) {
        await render(out, value, callArgs, target);
      } else if (value is List &&
          value.isEmpty &&
          operation.emptyNote != null) {
        out.writeln(operation.emptyNote);
      } else {
        writeOperationValue(out, value, operation.columns!);
      }
      return 0;
    });
  }

  String _flagOf(String key) =>
      '--${operation.params.firstWhere((param) => param.key == key).cli}';
}

class _ReviewedSpecCommand extends SpecCommand implements LiveGuardedCommand {
  _ReviewedSpecCommand(super.operation, super.io);
}

/// Write [value] as a table when it is a list of rows, else as one
/// `key: value` line per column.
void writeOperationValue(
  StringSink out,
  Object? value,
  List<OperationColumn> columns,
) {
  String cell(Object? value) => value == null ? '-' : '$value';
  if (value is List) {
    out.writeln(columns.map((column) => column.header).join('\t'));
    for (final row in value.cast<Map<String, Object?>>()) {
      out.writeln(columns.map((column) => cell(row[column.key])).join('\t'));
    }
    return;
  }
  final row = value! as Map<String, Object?>;
  for (final column in columns) {
    out.writeln('${column.key}: ${cell(row[column.key])}');
  }
}
