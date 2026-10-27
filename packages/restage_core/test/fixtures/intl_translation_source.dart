import 'package:flutter/widgets.dart' as f;
import 'package:intl/intl.dart' as i;
import 'package:restage_core/restage_core.dart' as r;
import 'package:restage_shared/restage_shared.dart' as s;

part 'intl_translation_source.g.dart';

enum TranslationStatus { active, paused }

class TranslationToken {}

final translationEffects = <String>[];

T translationMark<T>(String label, T value) {
  translationEffects.add(label);
  return value;
}

String authoredMessage(String user, DateTime date, TranslationToken token) =>
    i.Intl.message('Hello $user', name: 'welcome', args: [user, date, token]);

String authoredPlural(int count) => i.Intl.plural(count,
    one: 'one item', other: '$count items', name: 'items', args: [count]);

String authoredGender(String gender) => i.Intl.gender(gender,
    male: 'he', female: 'she', other: 'they', name: 'person', args: [gender]);

String authoredSelect(TranslationStatus choice, TranslationToken token) =>
    i.Intl.select(choice, {'active': 'Active', 'other': 'Other'},
        name: 'status', args: [choice, choice, token]);

String authoredAbsentArgs() => i.Intl.message('fallback', name: 'noArgs');
String authoredNullArgs() =>
    i.Intl.message('fallback', name: 'noArgs', args: null);
String authoredEmptyArgs() =>
    i.Intl.message('fallback', name: 'noArgs', args: []);
String authoredMissing() =>
    i.Intl.message('untranslated', name: 'absent', args: []);
String authoredNullName() => i.Intl.message('unnamed', name: null, args: [1]);
String authoredImplicitName() => i.Intl.message('implicit');
String authoredEmptyName() => i.Intl.message('implicit', name: '');
String authoredMeaning() => i.Intl.message('implicit', meaning: 'context');

String authoredWrongArity() =>
    i.Intl.message('fallback', name: 'wrongArity', args: [1]);
String authoredWrongType() =>
    i.Intl.message('fallback', name: 'wrongType', args: ['bad']);

String authoredOrdered() => i.Intl.plural(
    other: translationMark('other', 'fallback'),
    translationMark('count', 1),
    name: 'items',
    args: [translationMark('args', 1)],
    locale: translationMark('locale', 'fr'),
    desc: translationMark('desc', 'description'),
    examples: translationMark('examples', <String, Object>{'count': 1}),
    skip: translationMark('skip', false));

String authoredUnusedFallback() => i.Intl.plural(1,
    name: 'items', args: [1], other: throw StateError('unused fallback'));

String authoredMetadataFailure() => i.Intl.message('fallback',
    name: 'noArgs', desc: throw ArgumentError('metadata'));

f.Widget authoredTranslatedWidget() =>
    f.LayoutBuilder(builder: (context, constraints) {
      final label = i.Intl.message('fallback', name: 'noArgs', args: []);
      return f.Text(label);
    });

String authoredLiveCount(int count) =>
    i.Intl.message('fallback', name: 'items', args: [count++]);

String authoredPluralMeaning() =>
    i.Intl.plural(1, other: 'fallback', meaning: 'secret');
String authoredGenderMeaning() =>
    i.Intl.gender('male', other: 'fallback', meaning: 'secret');
String authoredSelectMeaning() =>
    i.Intl.select('active', {'other': 'fallback'}, meaning: 'secret');
String authoredPluralNullMeaningName() => i.Intl.plural(1,
    other: 'fallback', meaning: 'secret', name: null, args: null);
String authoredGenderNullMeaningName() => i.Intl.gender('male',
    other: 'fallback', meaning: 'secret', name: null, args: null);
String authoredSelectNullMeaningName() =>
    i.Intl.select('active', {'other': 'fallback'},
        meaning: 'secret', name: null, args: null);
String authoredNestedPluralMeaning() => i.Intl.message('fallback',
    name: 'noArgs',
    desc: i.Intl.plural(1, other: 'fallback', meaning: 'secret'));
String authoredNestedGenderMeaning() => i.Intl.message('fallback',
    name: 'noArgs',
    desc: i.Intl.gender('male', other: 'fallback', meaning: 'secret'));
String authoredNestedSelectMeaning() => i.Intl.message('fallback',
    name: 'noArgs',
    desc: i.Intl.select('active', {'other': 'fallback'}, meaning: 'secret'));

f.Widget authoredNullPluralWidget() =>
    f.LayoutBuilder(builder: (context, constraints) {
      // The unused arm intentionally preserves the widened nullable type.
      // ignore: dead_code
      const String? lookupKey = true ? null : 'secret';
      final label = i.Intl.message('fallback',
          name: 'noArgs',
          desc: i.Intl.plural(1, other: 'fallback', meaning: lookupKey));
      return f.Text(label);
    });

f.Widget authoredNullGenderWidget() =>
    f.LayoutBuilder(builder: (context, constraints) {
      // The unused arm intentionally preserves the widened nullable type.
      // ignore: dead_code
      const String? lookupKey = true ? null : 'secret';
      final label = i.Intl.message('fallback',
          name: 'noArgs',
          desc: i.Intl.gender('male', other: 'fallback', meaning: lookupKey));
      return f.Text(label);
    });

f.Widget authoredNullSelectWidget() =>
    f.LayoutBuilder(builder: (context, constraints) {
      // The unused arm intentionally preserves the widened nullable type.
      // ignore: dead_code
      const String? lookupKey = true ? null : 'secret';
      final label = i.Intl.message('fallback',
          name: 'noArgs',
          desc: i.Intl.select('active', {'other': 'fallback'},
              meaning: lookupKey));
      return f.Text(label);
    });

const pluralLookupAlias = i.Intl.plural;
const genderLookupAlias = i.Intl.gender;
const selectLookupAlias = i.Intl.select;

f.Widget authoredAliasNullPluralWidget() =>
    f.LayoutBuilder(builder: (context, constraints) {
      // The unused arm intentionally preserves the widened nullable type.
      // ignore: dead_code
      const String? lookupKey = true ? null : 'secret';
      final label = i.Intl.message('fallback',
          name: 'noArgs',
          desc: pluralLookupAlias(1, other: 'fallback', meaning: lookupKey));
      return f.Text(label);
    });

f.Widget authoredAliasNullGenderWidget() =>
    f.LayoutBuilder(builder: (context, constraints) {
      // The unused arm intentionally preserves the widened nullable type.
      // ignore: dead_code
      const String? lookupKey = true ? null : 'secret';
      final label = i.Intl.message('fallback',
          name: 'noArgs',
          desc:
              genderLookupAlias('male', other: 'fallback', meaning: lookupKey));
      return f.Text(label);
    });

f.Widget authoredAliasNullSelectWidget() =>
    f.LayoutBuilder(builder: (context, constraints) {
      // The unused arm intentionally preserves the widened nullable type.
      // ignore: dead_code
      const String? lookupKey = true ? null : 'secret';
      final label = i.Intl.message('fallback',
          name: 'noArgs',
          desc: selectLookupAlias('active', {'other': 'fallback'},
              meaning: lookupKey));
      return f.Text(label);
    });
