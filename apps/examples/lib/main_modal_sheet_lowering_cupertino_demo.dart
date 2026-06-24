import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'stub_products.dart';
import 'user_factories.g.dart';

/// On-device smoke for the per-function sheet library: the
/// `showCupertinoSheet` paywall authored in
/// `paywalls/modal_sheet_lowering_cupertino.dart` is compiled to a bundled
/// `.rfw` blob at build time and rendered here through the remote render path
/// (`RestagePaywall(id:)`). Because the lowering pins the sheet library by
/// source function, this renders the Cupertino card sheet on *every* platform
/// — including Android — matching how `showCupertinoSheet` behaves in a
/// hand-written Flutter app. Tap "See all plans" to open the lowered sheet;
/// drag it down or tap the scrim to dismiss.
///
/// Run on a simulator or device with:
///   flutter run -t lib/main_modal_sheet_lowering_cupertino_demo.dart
void main() {
  registerRestageCustomerWidgets();
  Restage.configure(
    apiKey: 'rs_pk_example',
    products: kStubProducts,
    resolver: const AssetVariantResolver(),
  );
  runApp(const _ModalSheetLoweringCupertinoDemoApp());
}

class _ModalSheetLoweringCupertinoDemoApp extends StatelessWidget {
  const _ModalSheetLoweringCupertinoDemoApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Modal sheet lowering demo (Cupertino)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6366F1),
        useMaterial3: true,
      ),
      home: const RestagePaywall(id: 'modal_sheet_lowering_cupertino'),
    );
  }
}
