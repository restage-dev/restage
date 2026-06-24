import 'package:meta/meta.dart';

/// Opts a widget class or field out of catalog inclusion.
///
/// Use on classes that can't be remote-rendered (e.g. CustomPainter
/// users) or on fields whose types aren't expressible in the catalog
/// (e.g. controllers, hosts-app callbacks). The [reason] is surfaced in
/// the editor and compilation report.
///
/// ```dart
/// @RfwIncompatible(reason: 'custom Canvas painting')
/// class CustomChart extends StatelessWidget { /* … */ }
///
/// class AcmeButton extends StatelessWidget {
///   @RestageProperty(description: '…')
///   final String label;
///
///   @RfwIncompatible(reason: 'controller is host-app responsibility')
///   final AcmeButtonController? controller;
/// }
/// ```
@immutable
final class RfwIncompatible {
  /// Const constructor.
  const RfwIncompatible({required this.reason});

  /// Human-readable explanation; surfaced in the editor and the
  /// compilation report.
  final String reason;
}
