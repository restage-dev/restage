import 'package:flutter/widgets.dart' as f;
import 'package:intl/intl.dart' as i;
import 'package:restage_core/restage_core.dart' as r;
import 'package:restage_shared/restage_shared.dart' as s;

part 'callable_authority_source.g.dart';

void Function(f.BuildContext) authoredCallable(
        void Function(f.BuildContext) callback,
        void Function(f.BuildContext) replacement) =>
    (f.BuildContext context) {
      final alias = callback;
      alias(context);
      callback = replacement;
    };

void Function(f.BuildContext) authoredNullableCallable(
        void Function(f.BuildContext)? callback,
        void Function(f.BuildContext) replacement,
        bool Function() acquire) =>
    (f.BuildContext context) {
      callback ??= acquire() ? replacement : replacement;
      callback!(context);
    };

const callableLookup = i.Intl.message;
final callableMetadataFailure = StateError('metadata');
String callableFailMetadata() => throw callableMetadataFailure;
String authoredAliasedLookup() =>
    callableLookup('fallback', name: 'fixed', desc: callableFailMetadata());
