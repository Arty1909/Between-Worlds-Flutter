import 'dart:convert';
import 'dart:math' as math;

typedef Json = Map<String, dynamic>;
T clone<T>(T value) => jsonDecode(jsonEncode(value)) as T;
Json obj(dynamic value) => Map<String, dynamic>.from(value as Map);

/// Platform-independent story engine. Only JSON data and an injected save writer.
class StoryEngine {
  StoryEngine(this.data, {String? saved, this.write}) {
    record = saved == null
        ? {
            'revision': 0,
            'state': clone(data['fresh']),
            'slots': <String, dynamic>{},
          }
        : obj(jsonDecode(saved));
    validate(state);
    if (record['revision'] is! int || record['slots'] is! Map) {
      throw StateError('Saved progress could not be read.');
    }
    for (final entry in (record['slots'] as Map).entries) {
      if (!['auto', '1', '2', '3'].contains(entry.key) || entry.value is! Map) {
        throw StateError('Saved slots could not be read.');
      }
      validate(obj(entry.value['state']));
    }
  }
  final Json data;
  final Future<void> Function(String)? write;
  late Json record;
  bool _busy = false;
  Json get state => obj(record['state']);
  // The mutable state is kept private to transactions.
  Json get _s => record['state'] as Json;
  int get revision => record['revision'] as int;
  Json get nodes => obj(data['nodes']);
  Json get endings => obj(data['endings']);
  Json get characters => obj(data['characters']);
  String export() => jsonEncode(record);
  Never fail(String message) => throw StateError(message);

  void validate(Json s) {
    final node = nodes[s['node']];
    if (s['schema'] != 1 ||
        !(data['looks'] as Map).containsKey(s['look']) ||
        (node == null && !endings.containsKey(s['node'])) ||
        s['name'] is! String ||
        (s['name'] as String).runes.isEmpty ||
        (s['name'] as String).runes.length > 24) {
      fail('Saved progress could not be read.');
    }
    if (s['beat'] is! int ||
        s['beat'] < 0 ||
        s['beat'] >= (node?['lines']?.length ?? 1)) {
      fail('Saved dialogue could not be read.');
    }
    for (final field in ['stats', 'bonds']) {
      final keys = field == 'stats'
          ? (data['stat_names'] as Map).keys
          : characters.keys;
      final values = s[field];
      if (values is! Map ||
          values.length != keys.length ||
          keys.any(
            (key) =>
                values[key] is! int ||
                values[key] < 0 ||
                values[key] > (field == 'stats' ? 30 : 10),
          )) {
        fail('Saved attributes could not be read.');
      }
    }
    if (s['stats']['wisdom'] > 3 ||
        s['stats']['shards'] > 3 ||
        s['puzzle_attempts'] is! int ||
        s['puzzle_attempts'] < 0 ||
        s['puzzle_attempts'] > 9999) {
      fail('Saved puzzle could not be read.');
    }
    final allowed = {
      'flags': data['flags'],
      'clues': (data['clues'] as Map).keys.toList(),
      'met': characters.keys.toList(),
    };
    for (final key in allowed.keys) {
      if (s[key] is! List ||
          (s[key] as List).toSet().length != (s[key] as List).length ||
          (s[key] as List).any((v) => !(allowed[key] as List).contains(v))) {
        fail('Saved decisions could not be read.');
      }
    }
    if (s['started'] is! bool ||
        s['puzzle_solved'] is! bool ||
        s['history'] is! List ||
        (s['history'] as List).length > 400 ||
        (s['history'] as List).any(
          (l) => l is! Map || l['text'] is! String || l['speaker'] is! String,
        )) {
      fail('Saved history could not be read.');
    }
    final f = s['feedback'];
    if (f != null &&
        (f is! Map ||
            (!nodes.containsKey(f['next']) &&
                !endings.containsKey(f['next'])) ||
            f['text'] is! String ||
            f['effects'] is! List)) {
      fail('Saved choice could not be read.');
    }
  }

  int chapter([Json? s]) => nodes[(s ?? _s)['node']]?['chapter'] ?? 5;
  String location([Json? s]) =>
      nodes[(s ?? _s)['node']]?['location'] ??
      endings[(s ?? _s)['node']]['title'];
  bool available(Json choice) =>
      obj(choice['requires'] ?? {}).entries.every((e) {
        final value = _s[e.key] ?? _s['stats'][e.key] ?? 0;
        final required = e.value is bool ? (e.value ? 1 : 0) : e.value;
        return (value is bool ? (value ? 1 : 0) : value) >= required;
      });
  void _log(Json line) {
    final text =
        line['when'] != null && !(_s['flags'] as List).contains(line['when'])
        ? line['alternate']
        : line['text'];
    final history = _s['history'] as List;
    history.add({
      'speaker': line['speaker'],
      'text': (text as String).replaceAll('{name}', _s['name']),
    });
    if (history.length > 400) history.removeRange(0, history.length - 400);
  }

  void _enter(String id) {
    _s.addAll({'node': id, 'beat': 0, 'feedback': null});
    final n = nodes[id];
    if (n != null) {
      for (final pair in [('clues', n['clue']), ('met', n['character'])]) {
        if (pair.$2 != null && !(_s[pair.$1] as List).contains(pair.$2)) {
          (_s[pair.$1] as List).add(pair.$2);
        }
      }
      _log(obj(n['lines'][0]));
    }
  }

  void _save(String slot) => record['slots'][slot] = {
    'state': clone(_s),
    'saved_at': DateTime.now().toUtc().toIso8601String(),
  };
  List<Json> slots() => ['auto', '1', '2', '3'].map((slot) {
    final entry = record['slots'][slot];
    return entry == null
        ? <String, dynamic>{'slot': slot, 'exists': false}
        : <String, dynamic>{
            'slot': slot,
            'exists': true,
            'name': entry['state']['name'],
            'chapter': chapter(obj(entry['state'])),
            'location': location(obj(entry['state'])),
            'saved_at': entry['saved_at'],
          };
  }).toList();

  Json view() {
    final s = _s, d = data;
    final r = <String, dynamic>{
      'revision': revision,
      'edition': 3,
      'name': s['name'],
      'started': s['started'],
      'hero': {
        ...obj(d['hero']),
        ...obj(d['looks'][s['look']]),
        'name': s['name'],
      },
      'emotions': d['emotions'],
      'look': s['look'],
      'looks': obj(
        d['looks'],
      ).entries.map((e) => {'id': e.key, ...obj(e.value)}).toList(),
      'stats': s['stats'],
      'chapter': chapter(),
      'chapters': d['chapters'],
      'location': location(),
      'node': s['node'],
      'warning': '',
      'clues': (s['clues'] as List)
          .map((id) => {'id': id, ...obj(d['clues'][id])})
          .toList(),
      'characters': characters.entries
          .map(
            (e) => {
              'id': e.key,
              ...obj(e.value),
              'met': (s['met'] as List).contains(e.key),
              'bond': s['bonds'][e.key],
            },
          )
          .toList(),
      'history': s['history'],
      'slots': slots(),
      'feedback': s['feedback'],
      'puzzle_solved': s['puzzle_solved'],
    };
    if (endings.containsKey(s['node'])) {
      final ending = clone<Json>(obj(endings[s['node']]));
      var who = 'loony';
      for (final k in ['merry', 'moony']) {
        if (s['bonds'][k] > s['bonds'][who]) who = k;
      }
      for (final e in {
        'stay_forest': 'loony',
        'stay_garden': 'merry',
        'stay_beacon': 'moony',
      }.entries) {
        if ((s['flags'] as List).contains(e.key)) who = e.value;
      }
      ending['text'] = (ending['text'] as String).replaceAll(
        '{companion}',
        characters[who]['name'],
      );
      if (s['node'] == 'ending_stay') {
        ending['bg'] = d['stay_lives'][who][0];
        ending['text'] = d['stay_lives'][who][1];
      }
      ending['afterword'] = (s['flags'] as List).contains('echo_released')
          ? ending['after_echo'] ?? ''
          : (s['flags'] as List).contains('echo_remembered')
          ? data['afterword_remembered']
          : '';
      r.addAll({
        'kind': 'ending',
        'ending': ending,
        'bg': ending['bg'],
        'character': s['node'] == 'ending_stay'
            ? {'id': who, ...obj(characters[who])}
            : null,
      });
    } else {
      final n = nodes[s['node']], who = nodes[s['node']]['character'];
      final line = clone<Json>(obj(n['lines'][s['beat']]));
      if (line['when'] != null &&
          !(s['flags'] as List).contains(line['when'])) {
        line['text'] = line['alternate'];
      }
      line['text'] = (line['text'] as String).replaceAll('{name}', s['name']);
      var emotion = line['emotion'] ?? 'neutral',
          heroEmotion = line['hero_emotion'] ?? 'neutral';
      if (s['feedback'] != null) {
        final effects = (s['feedback']['effects'] as List).join('\n');
        if (effects.contains('доверие')) {
          emotion = 'warm';
          heroEmotion = 'warm';
        } else if (n['kind'] == 'quiz') {
          emotion = effects.contains('Верных ответов') ? 'warm' : 'worried';
          heroEmotion = emotion;
        } else {
          heroEmotion = 'resolve';
        }
      }
      final last = s['beat'] == (n['lines'] as List).length - 1;
      r.addAll({
        'kind': n['kind'] ?? 'story',
        'bg': n['bg'],
        'line': line,
        'framing': n['framing'] ?? 'medium',
        'beat': s['beat'],
        'beats': n['lines'].length,
        'choices': last && s['feedback'] == null
            ? (n['choices'] as List).indexed
                  .map(
                    (c) => {
                      'id': c.$1,
                      'text': c.$2['text'],
                      'label': c.$2['label'],
                      'available': available(obj(c.$2)),
                    },
                  )
                  .toList()
            : [],
        'character': who == null
            ? null
            : {'id': who, ...obj(characters[who]), 'emotion': emotion},
        'hero_emotion': heroEmotion,
        'can_advance': s['feedback'] != null || !last,
      });
      if (n['kind'] == 'puzzle') {
        r.addAll({
          'symbols': d['puzzle_symbols'],
          'puzzle_attempts': s['puzzle_attempts'],
        });
      }
    }
    r['media'] = {
      'poster': 'assets/backgrounds/${r['bg']}.jpg',
      'video': RegExp(r'^\d+$').hasMatch(r['bg'])
          ? 'materials/${r['bg']}.mp4'
          : null,
    };
    if (r['bg'] == 'room-v2') {
      r['media']['poster'] = 'assets/backgrounds/room-v2.png';
    }
    if (['10', '11'].contains(r['bg'])) {
      r['media']['video'] =
          'assets/video/${r['bg'] == '10' ? 'moon-clean' : 'door-once'}.mp4';
    }
    return clone(r);
  }

  Future<Json> act(Json p) async {
    if (_busy) fail('Сначала дочитай реплику.');
    if (p['revision'] != revision) {
      fail(
        'Прогресс изменился в другом окне. Обновляем экран — повтори действие.',
      );
    }
    final before = clone<Json>(record);
    _busy = true;
    try {
      final action = p['action'];
      if (action == 'new') {
        if ((p['name'] ?? 'Арти') is! String) fail('Введи имя героини.');
        final name =
            (p['name'] ?? 'Арти').trim().replaceAll(RegExp(r'\s+'), ' ')
                as String;
        if (name.runes.isEmpty ||
            name.runes.length > 24 ||
            RegExp(r'[\x00-\x1f]').hasMatch(name)) {
          fail('Имя должно содержать от 1 до 24 символов.');
        }
        final look = _s['look'];
        record['state'] = clone(data['fresh']);
        _s.addAll({'name': name, 'look': look, 'started': true});
        _enter('ordinary_evening');
      } else if (action == 'dress') {
        if (!(data['looks'] as Map).containsKey(p['look'])) {
          fail('Выбери один из образов гардероба.');
        }
        _s['look'] = p['look'];
      } else if (action == 'load' || action == 'save') {
        final slot = '${p['slot']}';
        if (!['auto', '1', '2', '3'].contains(slot)) {
          fail('Неизвестная ячейка сохранения.');
        }
        if (action == 'load') {
          if (record['slots'][slot] == null) {
            fail('В этой ячейке ещё нет сохранения.');
          }
          record['state'] = clone(record['slots'][slot]['state']);
          validate(_s);
        } else {
          if (!_s['started']) fail('Сначала начни историю.');
          if (slot == 'auto') fail('Выбери одну из трёх ручных ячеек.');
          _save(slot);
        }
      } else if (endings.containsKey(_s['node']) || !_s['started']) {
        fail('Начни новую историю или загрузи сохранение.');
      } else if (action == 'advance') {
        if (_s['feedback'] != null) {
          _enter(_s['feedback']['next']);
        } else {
          final n = nodes[_s['node']];
          if (_s['beat'] >= n['lines'].length - 1) {
            fail('Сначала сделай выбор.');
          }
          _s['beat']++;
          _log(obj(n['lines'][_s['beat']]));
        }
      } else if (action == 'choose') {
        final n = nodes[_s['node']], i = p['choice'];
        if (_s['feedback'] != null || _s['beat'] != n['lines'].length - 1) {
          fail('Сначала дочитай реплику.');
        }
        if (i is! int || i < 0 || i >= n['choices'].length) {
          fail('Такого выбора нет.');
        }
        final c = obj(n['choices'][i]), effects = <String>[];
        if (!available(c)) fail('Этот путь пока недоступен.');
        for (final e in obj(c['effects']).entries) {
          if (e.key.startsWith('bond_')) {
            final who = e.key.substring(5);
            _s['bonds'][who] += e.value;
            effects.add('${characters[who]['name']}: доверие +${e.value}');
          } else {
            _s['stats'][e.key] += e.value;
            effects.add('${data['stat_names'][e.key]} +${e.value}');
          }
        }
        if (c['clue'] != null && !(_s['clues'] as List).contains(c['clue'])) {
          (_s['clues'] as List).add(c['clue']);
        }
        for (final flag in c['set_flags'] ?? []) {
          if (!(_s['flags'] as List).contains(flag)) {
            (_s['flags'] as List).add(flag);
          }
        }
        _log({'speaker': 'hero', 'text': c['text']});
        _log({'speaker': 'narrator', 'text': c['reply']});
        _s['feedback'] = {
          'text': c['reply'],
          'next': c['next'],
          'effects': effects,
        };
      } else if (action == 'puzzle' || action == 'skip_puzzle') {
        if (_s['node'] != 'mechanism' || _s['feedback'] != null) {
          fail('Механизм сейчас недоступен.');
        }
        Json f;
        if (action == 'skip_puzzle') {
          f = clone<Json>(obj(data['puzzle_results']['help']));
        } else {
          final symbols = p['symbols'],
              valid = (data['puzzle_symbols'] as List).map((s) => s['id']);
          if (symbols is! List ||
              symbols.length != 3 ||
              symbols.toSet().length != 3 ||
              symbols.any((s) => !valid.contains(s))) {
            fail('Выбери три разных символа.');
          }
          _s['puzzle_attempts'] = math.min(
            (_s['puzzle_attempts'] as int) + 1,
            9999,
          );
          if (jsonEncode(symbols) != jsonEncode(data['puzzle_answer'])) {
            f = clone<Json>(obj(data['puzzle_results']['retry']));
          } else {
            _s['puzzle_solved'] = true;
            f = clone<Json>(obj(data['puzzle_results']['solved']));
          }
        }
        _s['feedback'] = f;
        _log({'speaker': 'narrator', 'text': f['text']});
      } else {
        fail('Неизвестное действие.');
      }
      validate(_s);
      _save('auto');
      record['revision']++;
      final result = view();
      await write?.call(export());
      return result;
    } catch (_) {
      record = before;
      rethrow;
    } finally {
      _busy = false;
    }
  }
}
