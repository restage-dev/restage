import 'surface_delivery_receipt_journal.dart';

SurfaceDeliveryReceiptJournal createSurfaceDeliveryReceiptJournal() =>
    const _NoJournal();

final class _NoJournal implements SurfaceDeliveryReceiptJournal {
  const _NoJournal();

  @override
  Future<SurfaceDeliveryReceiptJournalState?> read() async => null;

  @override
  Future<void> write(SurfaceDeliveryReceiptJournalState state) async {}
}
