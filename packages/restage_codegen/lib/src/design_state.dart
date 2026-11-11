import 'package:analyzer/dart/element/element.dart';
import 'package:collection/collection.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/islands/islands.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/source_state.dart';

/// The build to compile with [lifted]'s `State` in the mount: the design keeps
/// the state it lowers unless what the mount records depends on it.
({SourceBuildBlueprint build, TranslationResult translation, Issue? notice})
liftState(
  SourceBuildBlueprint lifted,
  TranslationResult Function(SourceBuildBlueprint build) translate,
) {
  final translation = translate(lifted);
  final whole = lifted.liftable;
  final state = lifted.liftedState;
  if (whole == null || state == null || lifted.state == null) {
    return (build: lifted, translation: translation, notice: null);
  }
  final record = translation.split?.recordProblem;
  final stuck =
      translation.issues.firstWhereOrNull(
        (issue) => !issue.code.isBuildNotice,
      ) ??
      record;
  if (stuck == null) {
    return (build: lifted, translation: translation, notice: null);
  }
  final kept =
      "`${state.name}` stays in your app's code, so a published design can't "
      'change it';
  final notice = record?.code == IssueCode.stateKeptInApp
      ? record!
      : Issue(
          code: IssueCode.stateKeptInApp,
          message: switch (_neededMember(translation, lifted)) {
            final MethodElement member =>
              '$kept: code your app runs calls `${member.name}` of '
                  '`${state.name}`. Try passing a setState handler straight '
                  'to the widget that fires it, as in '
                  '`onTap: selectMonthly`, and do other work in a callback '
                  'your widget takes.',
            final member? =>
              '$kept: a widget your app builds, or a value it computes, '
                  'reads `${member.name}`. Try reading `${member.name}` only '
                  "in Restage's catalog widgets and in setState handlers.",
            null => '$kept: ${stuck.message}',
          },
          location: stuck.location,
        );
  return (build: whole, translation: translate(whole), notice: notice);
}

// The State member the mount needed, preferring one the design doesn't keep.
Element? _neededMember(
  TranslationResult translation,
  SourceBuildBlueprint lifted,
) {
  final state = lifted.liftedState!;
  final kept = {
    ...?lifted.state?.map((field) => field.name),
    ...lifted.eventHandlers.keys,
  };
  final needed = [
    for (final element in translation.blocked)
      if (isDesignStateMemberOf(state, element)) element,
  ];
  return needed.where((element) => !kept.contains(element.name)).firstOrNull ??
      needed.firstOrNull;
}
