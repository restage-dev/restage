import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A reusable heading whose supported composition can be delivered in RFW.
@RestageWidget()
class RecapHeading extends StatelessWidget {
  const RecapHeading({super.key, required this.title});

  /// Text displayed above the recap details.
  final String title;

  @override
  Widget build(BuildContext context) => Text(title);
}
