import 'engine.dart';

/// Exact dictionary lookups and explicit templates; never translate fragments
/// inside arbitrary words. Missing keys are exposed to the release audit.
class Catalog {
  Catalog(this.dictionaries);
  final Map<String, Json> dictionaries;
  String language = 'en';
  final missingKeys = <String>{};
  final Map<String, String> _cache = {};
  final Map<String, List<_Template>> _templates = {};
  static const languages = {
    'en': 'English',
    'ru': 'Русский',
    'es': 'Español',
    'it': 'Italiano',
    'fr': 'Français',
  };
  String t(dynamic value) {
    final source = (value ?? '').toString();
    return _cache.putIfAbsent('$language|$source', () => _translate(source));
  }

  String format(String key, Map<String, Object> parameters) {
    var result = t(key);
    for (final e in parameters.entries) {
      result = result.replaceAll('{${e.key}}', e.value.toString());
    }
    return result;
  }

  String _translate(String source) {
    if (source.isEmpty) return source;
    final dict = dictionaries[language]!;
    if (dict.containsKey(source)) return dict[source].toString();
    final normalized = source.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (dict.containsKey(normalized)) return dict[normalized].toString();
    final templates = _templates.putIfAbsent(language, () {
      final entries = dict.entries.where((e) => e.key.contains('{')).toList()
        ..sort((a, b) => b.key.length.compareTo(a.key.length));
      return entries.map((e) => _Template(e.key, e.value.toString())).toList();
    });
    for (final template in templates) {
      final match = template.pattern.firstMatch(normalized);
      if (match == null) continue;
      var result = template.translation;
      for (var i = 0; i < template.parameters.length; i++) {
        final parameter = template.parameters[i];
        final value = match.group(i + 1)!;
        // Player-entered names must never be translated, even if they match a
        // character name or a word that also appears in the dictionary.
        final rendered = ['name', 'number', 'amount'].contains(parameter)
            ? value
            : t(value);
        result = result.replaceAll('{$parameter}', rendered);
      }
      return result;
    }
    missingKeys.add(source);
    return dictionaries['en']?[source]?.toString() ?? source;
  }
}

class _Template {
  _Template(String source, this.translation) {
    final normalized = source.replaceAll(RegExp(r'\s+'), ' ').trim();
    var expression = '', offset = 0;
    for (final match in RegExp(
      r'\{(name|companion|character|stat|number|amount)\}',
    ).allMatches(normalized)) {
      final key = match.group(1)!;
      parameters.add(key);
      expression += RegExp.escape(normalized.substring(offset, match.start));
      expression += ['number', 'amount'].contains(key)
          ? r'([+-]?\d+)'
          : '(.+?)';
      offset = match.end;
    }
    expression += RegExp.escape(normalized.substring(offset));
    pattern = RegExp('^$expression\$');
  }
  final String translation;
  final parameters = <String>[];
  late final RegExp pattern;
}
