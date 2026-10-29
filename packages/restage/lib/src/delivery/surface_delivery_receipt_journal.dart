import 'package:meta/meta.dart';

import 'surface_delivery_receipt_journal_stub.dart'
    if (dart.library.io) 'surface_delivery_receipt_journal_io.dart'
    as implementation;

/// One post of receipts, resent unchanged under its own [batchId] until the
/// service acknowledges it.
typedef SurfaceDeliveryReceiptPost = ({
  String batchId,
  List<String> receipts,
  int dropped,
});

/// What the journal holds: unacknowledged posts, receipts not yet in a post,
/// and the fingerprint of the service and key they were written for.
typedef SurfaceDeliveryReceiptJournalState = ({
  String fingerprint,
  List<SurfaceDeliveryReceiptPost> posts,
  List<String> receipts,
});

/// Receipts written for the service, kept until it acknowledges them.
abstract interface class SurfaceDeliveryReceiptJournal {
  /// The last state written, or null when there is none.
  Future<SurfaceDeliveryReceiptJournalState?> read();

  /// Replaces the journal; nothing to keep clears it.
  Future<void> write(SurfaceDeliveryReceiptJournalState state);
}

/// The platform's journal: a file in app support storage, or none on the web.
SurfaceDeliveryReceiptJournal createSurfaceDeliveryReceiptJournal() =>
    implementation.createSurfaceDeliveryReceiptJournal();

/// A journal that keeps its state in memory; tests install it so a restore
/// never waits on a file.
@visibleForTesting
final class MemorySurfaceDeliveryReceiptJournal
    implements SurfaceDeliveryReceiptJournal {
  SurfaceDeliveryReceiptJournalState? _state;

  @override
  Future<SurfaceDeliveryReceiptJournalState?> read() async => _state;

  @override
  Future<void> write(SurfaceDeliveryReceiptJournalState state) async =>
      _state = state;
}
