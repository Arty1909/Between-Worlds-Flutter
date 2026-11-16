import 'dart:convert';
import 'dart:io';
import 'package:between_worlds/game/catalog.dart';
import 'package:between_worlds/game/engine.dart';

List<String> auditLocales(Directory root) {
  final dictionaries = <String, Json>{};
  for (final lang in Catalog.languages.keys) {
    dictionaries[lang] = obj(
      jsonDecode(
        File('${root.path}/assets/locales/$lang.json').readAsStringSync(),
      ),
    );
  }
  final catalog = Catalog(dictionaries), errors = <String>[];
  final cyrillic = RegExp(r'[\u0400-\u04ff]');
  final placeholders = RegExp(r'\{\w+\}');
  Set<String> tokens(String value) =>
      placeholders.allMatches(value).map((m) => m[0]!).toSet();
  final sources = <String>{};
  void walk(dynamic value) {
    if (value is String && cyrillic.hasMatch(value)) sources.add(value);
    if (value is List) value.forEach(walk);
    if (value is Map) value.values.forEach(walk);
  }

  for (final name in ['story', 'arrivals']) {
    walk(
      jsonDecode(
        File('${root.path}/assets/data/$name.json').readAsStringSync(),
      ),
    );
  }
  // Literal UI labels and validation errors must be explicitly in the catalog.
  final literals = RegExp(r"'((?:\\.|[^'\\\r\n])*)'");
  for (final f
      in Directory('${root.path}/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
    final code = f.readAsStringSync();
    for (final match in literals.allMatches(code)) {
      final text = match[1]!.replaceAll(r'\n', '\n').replaceAll(r"\'", "'");
      if (cyrillic.hasMatch(text) &&
          !text.contains(r'$') &&
          text != 'Русский') {
        sources.add(text);
      }
    }
    for (final match in RegExp(
      r"(?:fail|StateError)\('([^']+)'\)",
    ).allMatches(code)) {
      sources.add(match[1]!);
    }
  }
  sources.addAll([
    'Audio is unavailable. Try enabling sound again.',
    'Could not open the story. Existing saves are preserved.',
    'Сохранение 1',
    'Сохранение 2',
    'Сохранение 3',
    'Верес: доверие +2',
    'Смелость +1',
  ]);
  final reference = dictionaries['en']!;
  for (final lang in Catalog.languages.keys) {
    final dict = dictionaries[lang]!;
    for (final key in {...reference.keys, ...dict.keys}) {
      if (!dict.containsKey(key) || !reference.containsKey(key)) {
        errors.add('$lang: mismatched dictionary key: $key');
        continue;
      }
      final value = dict[key].toString();
      if (value.trim().isEmpty) errors.add('$lang: empty translation: $key');
      if (tokens(key).difference(tokens(value)).isNotEmpty ||
          tokens(value).difference(tokens(key)).isNotEmpty) {
        errors.add('$lang: changed placeholders: $key');
      }
      if (lang != 'ru' && cyrillic.hasMatch(value)) {
        errors.add('$lang: Cyrillic in translation: $key');
      }
    }
    catalog.language = lang;
    catalog.missingKeys.clear();
    for (final source in sources) {
      catalog.t(source);
    }
    for (final missing in catalog.missingKeys) {
      errors.add('$lang: missing: $missing');
    }
  }
  return errors;
}

void main() {
  final errors = auditLocales(
    Directory.fromUri(Platform.script.resolve('../')),
  );
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
  } else {
    stdout.writeln(
      'All five catalogs cover story, arrivals, UI literals, errors and dynamic labels.',
    );
  }
}
