/// Internal shared flow-experiment contract and eligibility primitives.
///
/// This is a deliberately separate library from `restage_shared.dart`. Flutter
/// applications should not acquire this transport contract through the public
/// `restage.dart` barrel.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_shared/src/capability/capability_manifest.dart';
import 'package:restage_shared/src/capability/installed_capability.dart';
import 'package:restage_shared/src/flow_document/flow_action_schema.dart';
import 'package:restage_shared/src/flow_document/flow_active_render_gate.dart';
import 'package:restage_shared/src/flow_document/flow_document.dart';
import 'package:restage_shared/src/flow_document/flow_document_codec.dart';
import 'package:restage_shared/src/flow_document/flow_document_hash.dart';
import 'package:restage_shared/src/flow_document/flow_document_validation.dart';
import 'package:restage_shared/src/flow_document/general_render_gate.dart';
import 'package:restage_shared/src/surface_document/surface_document.dart';

part 'src/capability/flow_experiment_contract.dart';
part 'src/capability/flow_experiment_eligibility.dart';
