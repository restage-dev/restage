import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart' as path_provider;

import 'surface_delivery_receipt_journal.dart';

SurfaceDeliveryReceiptJournal createSurfaceDeliveryReceiptJournal() =>
    FileSurfaceDeliveryReceiptJournal(() async {
      final support = await path_provider.getApplicationSupportDirectory();
      return File('${support.path}/restage/delivery/receipts-v1.json');
    });

/// A journal in one file, replaced atomically.
final class FileSurfaceDeliveryReceiptJournal
    implements SurfaceDeliveryReceiptJournal {
  FileSurfaceDeliveryReceiptJournal(this._file);

  final Future<File> Function() _file;

  @override
  Future<SurfaceDeliveryReceiptJournalState?> read() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return null;
      if (jsonDecode(await file.readAsString())
          case {
            'fingerprint': final String fingerprint,
            'posts': final List<Object?> posts,
            'receipts': final List<Object?> receipts,
          }) {
        return (
          fingerprint: fingerprint,
          posts: [
            for (final post in posts)
              if (post
                  case {
                    'batchId': final String batchId,
                    'receipts': final List<Object?> postReceipts,
                    'dropped': final int dropped,
                  })
                (
                  batchId: batchId,
                  receipts: [for (final r in postReceipts) jsonEncode(r)],
                  dropped: dropped,
                ),
          ],
          receipts: [for (final receipt in receipts) jsonEncode(receipt)],
        );
      }
    } on Object {
      // An unreadable journal is treated as empty.
    }
    return null;
  }

  @override
  Future<void> write(SurfaceDeliveryReceiptJournalState state) async {
    try {
      final file = await _file();
      if (state.posts.isEmpty && state.receipts.isEmpty) {
        if (file.existsSync()) await file.delete();
        return;
      }
      await file.parent.create(recursive: true);
      final posts = [
        for (final post in state.posts)
          '{"batchId":${jsonEncode(post.batchId)},'
              '"receipts":[${post.receipts.join(',')}],'
              '"dropped":${post.dropped}}',
      ];
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        '{"fingerprint":${jsonEncode(state.fingerprint)},'
        '"posts":[${posts.join(',')}],'
        '"receipts":[${state.receipts.join(',')}]}',
        flush: true,
      );
      await temporary.rename(file.path);
    } on Object {
      // Receipts not written stay in memory for this process.
    }
  }
}
