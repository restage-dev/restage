import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:restage_cli/src/api/placement_sample_api.dart';
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/commands/delivery_command.dart';
import 'package:restage_cli/src/commands/live_guard.dart';
import 'package:restage_cli/src/commands/measurement_page_command.dart';
import 'package:restage_cli/src/commands/surface_routing_command.dart'
    show newOperationId;
import 'package:restage_cli/src/operations/operation.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

/// Local capture import and explicitly reviewed private sample storage.
class DeliverySampleCommand extends Command<int> {
  /// Shares command I/O with the enclosing delivery group.
  DeliverySampleCommand(CommandIo io) {
    for (final operation in _SampleOperation.values) {
      addSubcommand(
        operation.mutates
            ? _SampleMutationCommand(operation, io)
            : _SampleCommand(operation, io),
      );
    }
  }

  @override
  String get name => 'sample';

  @override
  String get description =>
      'Import, review, upload, and bind private screen samples.';
}

enum _SampleOperation {
  import('import', 'Validate a local capture and create a target-bound draft.'),
  review(
    'review',
    'Review an exact draft and prepare its private upload.',
    true,
  ),
  upload('upload', 'Upload current PNG bytes under the reviewed ticket.', true),
  bind('bind', 'Bind a stored complete frame at an expected revision.', true),
  show('show', 'Read sample metadata and current availability.'),
  download('download', 'Download an authorized private sample PNG.'),
  delete('delete', 'Remove a private sample and its current binding.', true);

  const _SampleOperation(
    this.cliName,
    this.description, [
    this.mutates = false,
  ]);

  final String cliName;
  final String description;
  final bool mutates;
}

class _SampleMutationCommand extends _SampleCommand
    implements LiveGuardedCommand {
  _SampleMutationCommand(super.operation, super.io);
}

class _SampleCommand extends Command<int> {
  _SampleCommand(this.operation, this.io) {
    addScopeOptions(argParser, OperationScope.target);
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print the exact public result JSON.',
    );
    switch (operation) {
      case _SampleOperation.import:
        argParser
          ..addOption(
            'manifest',
            help: 'Canonical target-free capture JSON file.',
          )
          ..addOption('png', help: 'PNG file from the same capture frame.')
          ..addOption(
            'screen-label',
            help: 'Screen label to bind in the draft.',
          )
          ..addOption(
            'out',
            help: 'Write the canonical target-bound draft here.',
          );
      case _SampleOperation.review:
        argParser
          ..addOption(
            'draft',
            help: 'Canonical target-bound sample draft file.',
          )
          ..addOption('png', help: 'Current PNG file to review.')
          ..addOption(
            'reviewed-digest',
            help: 'Exact review digest explicitly approved by the operator.',
          )
          ..addOption(
            'operation-id',
            help: 'Canonical UUIDv4 retry identity. Generated when omitted.',
          )
          ..addOption(
            'out',
            help: 'Write the unchanged server upload ticket here.',
          );
      case _SampleOperation.upload:
        argParser
          ..addOption(
            'ticket',
            help: 'Canonical upload ticket issued by sample review.',
          )
          ..addOption(
            'png',
            help: 'Current PNG file matching the reviewed ticket.',
          )
          ..addOption(
            'out',
            help: 'Write the unchanged stored-sample result here.',
          );
      case _SampleOperation.bind:
        argParser
          ..addOption('stored', help: 'Canonical stored-sample result file.')
          ..addOption(
            'operation-id',
            help: 'Canonical UUIDv4 retry identity. Generated when omitted.',
          )
          ..addOption(
            'expected-binding-revision',
            help: 'Expected complete frame revision. Omit for a new binding.',
          );
      case _SampleOperation.show:
        argParser.addOption('sample-id', help: 'Exact private sample UUIDv4.');
      case _SampleOperation.download:
        argParser
          ..addOption('sample-id', help: 'Exact private sample UUIDv4.')
          ..addOption('out', help: 'Write the authorized PNG here.');
      case _SampleOperation.delete:
        argParser
          ..addOption('sample-id', help: 'Exact private sample UUIDv4.')
          ..addOption(
            'operation-id',
            help: 'Canonical UUIDv4 retry identity. Generated when omitted.',
          )
          ..addOption(
            'expected-binding-revision',
            help: 'Expected current complete frame revision.',
          );
    }
  }

  final _SampleOperation operation;
  final CommandIo io;

  @override
  String get name => operation.cliName;

  @override
  String get description => operation.description;

  String _required(String option) {
    final value = argResults?[option] as String?;
    if (value == null || value.isEmpty) {
      throw FormatException('Required: --$option.');
    }
    return value;
  }

  Future<Uint8List> _document(String option) => readDeliveryFile(
    _required(option),
    maximumBytes: maximumPlacementSampleDocumentBytes,
  );

  Future<Uint8List> _png() => readDeliveryFile(
    _required('png'),
    maximumBytes: placementScreenSampleMaxBytes,
  );

  String _operationId() =>
      argResults?['operation-id'] as String? ?? newOperationId();

  int? _revision() {
    final raw = argResults?['expected-binding-revision'] as String?;
    if (raw == null) return null;
    final value = int.tryParse(raw);
    if (value == null || value < 1) {
      throw const FormatException(
        '--expected-binding-revision must be a positive integer.',
      );
    }
    return value;
  }

  @override
  Future<int> run() async {
    try {
      return await runAuthed(io, argResults, OperationScope.target, (
        context,
      ) async {
        final selected = context.target!;
        final target = targetCoordinateOf(selected);
        if (this is LiveGuardedCommand &&
            !await confirmLiveChange(
              command: this,
              interactive: io.interactive,
              stdout: io.stdout,
              stderr: io.stderr,
              runtimePlane: selected.runtimePlane,
              impactLine:
                  'Sample $name for ${selected.app} in ${selected.environment} (live).',
            )) {
          return 1;
        }

        final api = PlacementSampleApi(context.api);
        final CanonicalValue result;
        switch (operation) {
          case _SampleOperation.import:
            _required('out');
            result = importPlacementSample(
              captureBytes: await _document('manifest'),
              pngBytes: await _png(),
              target: target,
              screenLabel: argResults?['screen-label'] as String?,
            );
          case _SampleOperation.review:
            _required('out');
            final draft = PlacementSampleDraftV1.fromCanonicalBytes(
              await _document('draft'),
            );
            final png = await _png();
            if (draft.manifest.target != target) {
              throw const FormatException('The draft is for another target.');
            }
            validatePlacementScreenSample(
              manifest: draft.manifest,
              pngBytes: png,
            );
            var digest = argResults?['reviewed-digest'] as String?;
            if (digest == null && io.interactive.isInteractive) {
              _printDraft(draft);
              if (await io.interactive.confirm(
                'Approve this exact image and manifest for upload?',
              )) {
                digest = draft.reviewedDigest;
              }
            }
            if (digest == null || digest != draft.reviewedDigest) {
              throw const FormatException(
                'Supply the exact --reviewed-digest after reviewing the image and manifest.',
              );
            }
            result = await api.prepare(
              projectSlug: selected.project,
              appSlug: selected.app,
              target: target,
              request: PlacementSamplePrepareV1(
                manifest: draft.manifest,
                buildContract: draft.buildContract,
                reviewedDigest: digest,
                operationId: _operationId(),
              ),
              pngBytes: png,
            );
          case _SampleOperation.upload:
            _required('out');
            result = await api.store(
              projectSlug: selected.project,
              appSlug: selected.app,
              target: target,
              ticket: PlacementSampleUploadTicketV1.fromCanonicalBytes(
                await _document('ticket'),
              ),
              pngBytes: await _png(),
            );
          case _SampleOperation.bind:
            final stored = PlacementSampleStoredV1.fromCanonicalBytes(
              await _document('stored'),
            );
            result = await api.bind(
              projectSlug: selected.project,
              appSlug: selected.app,
              target: target,
              request: PlacementSampleBindV1(
                sampleId: stored.sampleId,
                operationId: _operationId(),
                expectedBindingRevision: _revision(),
              ),
            );
            final ref = result as PlacementScreenSampleRefV1;
            if (ref.manifestDigest != stored.manifestDigest ||
                ref.imageSha256 != stored.imageSha256) {
              throw const PlacementSampleResponseException();
            }
          case _SampleOperation.show:
            result = await api.read(
              projectSlug: selected.project,
              appSlug: selected.app,
              target: target,
              request: PlacementSampleReadV1(sampleId: _required('sample-id')),
            );
          case _SampleOperation.download:
            final out = _required('out');
            final bytes = await api.readImage(
              projectSlug: selected.project,
              appSlug: selected.app,
              target: target,
              request: PlacementSampleReadV1(sampleId: _required('sample-id')),
            );
            await File(out).writeAsBytes(bytes, flush: true);
            io.stdout.writeln(
              argResults?['json'] == true
                  ? jsonEncode({
                      'sampleId': _required('sample-id'),
                      'pngBase64': base64Encode(bytes),
                    })
                  : 'Downloaded sample ${_required('sample-id')}.',
            );
            return 0;
          case _SampleOperation.delete:
            result = await api.delete(
              projectSlug: selected.project,
              appSlug: selected.app,
              target: target,
              request: PlacementSampleDeleteV1(
                sampleId: _required('sample-id'),
                operationId: _operationId(),
                expectedBindingRevision: _revision(),
              ),
            );
        }
        if (argResults!.options.contains('out')) {
          final out = argResults?['out'] as String?;
          if (out != null) {
            await File(out).writeAsBytes(result.canonicalBytes, flush: true);
          }
        }
        if (argResults?['json'] == true) {
          io.stdout.writeln(utf8.decode(result.canonicalBytes));
        } else {
          _printResult(result);
        }
        return 0;
      });
    } on PlacementSampleException catch (error) {
      io.stderr.writeln(error);
      return 1;
    } on PlacementSampleResponseException catch (error) {
      io.stderr.writeln(error);
      return 2;
    } on CanonicalFormatException catch (error) {
      io.stderr.writeln(error);
      return 1;
    } on FormatException catch (error) {
      io.stderr.writeln(error.message);
      return 1;
    } on FileSystemException {
      io.stderr.writeln('Could not read or write the supplied sample file.');
      return 1;
    }
  }

  void _printDraft(PlacementSampleDraftV1 draft) {
    final manifest = draft.manifest;
    io.stdout
      ..writeln('Sample draft: ${manifest.screenLabel}')
      ..writeln('Target: ${utf8.decode(manifest.target.canonicalBytes)}')
      ..writeln(
        'Image: ${manifest.pngWidth} × ${manifest.pngHeight}; ${manifest.pngSha256}',
      )
      ..writeln('Review digest: ${draft.reviewedDigest}');
    for (final mount in manifest.mounts) {
      io.stdout.writeln('Mount: ${utf8.decode(mount.canonicalBytes)}');
    }
  }

  void _printResult(CanonicalValue result) {
    switch (result) {
      case PlacementSampleDraftV1 draft:
        _printDraft(draft);
      case PlacementSampleUploadTicketV1 ticket:
        io.stdout.writeln(
          'Upload ticket: ${ticket.ticketId}; image ${ticket.imageSha256}.',
        );
      case PlacementSampleStoredV1 stored:
        io.stdout.writeln(
          'Stored sample: ${stored.sampleId}; binding requires sample bind.',
        );
      case PlacementScreenSampleRefV1 ref:
        io.stdout.writeln(
          'Bound sample: ${ref.sampleId}; revision ${ref.bindingRevision}.',
        );
      case PlacementSampleReadResultV1 read:
        io.stdout.writeln(
          'Sample ${read.sampleId}: ${read.status.name}; binding revision ${read.bindingRevision ?? 'unavailable'}.',
        );
      case PlacementSampleDeleteResultV1 deleted:
        io.stdout.writeln(
          'Sample ${deleted.sampleId}: ${deleted.status.name}; binding revision ${deleted.bindingRevision ?? 'unavailable'}.',
        );
      default:
        io.stdout.writeln(utf8.decode(result.canonicalBytes));
    }
  }
}
