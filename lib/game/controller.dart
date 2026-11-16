import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'engine.dart';
import 'catalog.dart';
export 'catalog.dart';

class GameController extends ChangeNotifier {
  GameController(
    this.engine,
    this.catalog,
    this.media,
    this.arrivals,
    this.preferences,
  );
  final StoryEngine engine;
  final Catalog catalog;
  final Json media, arrivals;
  final SharedPreferences preferences;
  bool busy = false, home = true, scenery = false, panel = false;
  bool music = false, effects = true, animations = true, typewriter = true;
  double volume = .35, textScale = 1, speed = 38;
  Json? arrival;
  String? error;
  static const saveKey = 'between-worlds-flutter-save-v1';
  static Future<GameController> load({
    void Function(Catalog)? onCatalogLoaded,
  }) async {
    Future<Json> read(String p) async =>
        obj(jsonDecode(await rootBundle.loadString(p)));
    final prefs = await SharedPreferences.getInstance();
    final dictionaries = <String, Json>{};
    for (final language in Catalog.languages.keys) {
      dictionaries[language] = await read('assets/locales/$language.json');
    }
    final catalog = Catalog(dictionaries);
    final language = prefs.getString('language') ?? 'en';
    catalog.language = Catalog.languages.containsKey(language)
        ? language
        : 'en';
    onCatalogLoaded?.call(catalog);
    final data = await read('assets/data/story.json'),
        media = await read('assets/data/media.json'),
        arrivals = await read('assets/data/arrivals.json');
    String? lastGoodSave;
    Future<void> write(String text) async {
      if (lastGoodSave != null &&
          !await prefs.setString('$saveKey.backup', lastGoodSave!)) {
        throw StateError('Не удалось сохранить игру.');
      }
      if (!await prefs.setString(saveKey, text)) {
        throw StateError('Не удалось сохранить игру.');
      }
      lastGoodSave = text;
    }

    // Preserve corrupt data for recovery; never silently reset an existing save.
    StoryEngine engine;
    String? recovery;
    try {
      engine = StoryEngine(data, saved: prefs.getString(saveKey), write: write);
    } catch (_) {
      final backup = prefs.getString('$saveKey.backup');
      if (backup == null) rethrow;
      engine = StoryEngine(data, saved: backup, write: write);
      recovery = 'Восстановлено предыдущее сохранение.';
    }
    if (prefs.containsKey(saveKey) || recovery != null) {
      lastGoodSave = engine.export();
    }
    final c = GameController(engine, catalog, media, arrivals, prefs);
    c.music = prefs.getBool('music') ?? false;
    c.effects = prefs.getBool('effects') ?? true;
    c.animations = prefs.getBool('animations') ?? true;
    c.typewriter = prefs.getBool('typewriter') ?? true;
    c.volume = (prefs.getDouble('volume') ?? .35).clamp(0, 1);
    c.textScale = (prefs.getDouble('textScale') ?? 1).clamp(.85, 1.4);
    c.speed = (prefs.getDouble('speed') ?? 38).clamp(20, 100);
    c.error = recovery;
    return c;
  }

  Json get view => engine.view();
  String t(dynamic s) => catalog.t(s);
  String format(String key, Map<String, Object> parameters) =>
      catalog.format(key, parameters);

  String asset(String original) => media[original] ?? original;
  String poster(String bg) => asset(
    bg == 'room-v2'
        ? 'assets/backgrounds/room-v2.png'
        : 'assets/backgrounds/$bg.jpg',
  );
  Future<void> act(String action, [Json extra = const {}]) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    final previous = view;
    try {
      await engine.act({
        'action': action,
        'revision': engine.revision,
        ...extra,
      });
      final next = view;
      if (action == 'new' || action == 'load') {
        home = false;
        scenery = false;
        panel = false;
        arrival = null;
      } else if (!home &&
          previous['bg'] != next['bg'] &&
          next['kind'] != 'ending') {
        arrival = arrivals[next['bg']] == null
            ? null
            : obj(arrivals[next['bg']]);
      }
    } catch (e) {
      error = e is StateError
          ? e.message
          : 'Не удалось выполнить действие. Попробуй ещё раз.';
    }
    busy = false;
    notifyListeners();
  }

  void resume() {
    home = false;
    arrival = null;
    scenery = false;
    notifyListeners();
  }

  void goHome() {
    home = true;
    scenery = false;
    arrival = null;
    notifyListeners();
  }

  void dismissArrival() {
    arrival = null;
    notifyListeners();
  }

  void inspect() {
    scenery = !scenery;
    panel = false;
    notifyListeners();
  }

  void togglePanel() {
    panel = !panel;
    notifyListeners();
  }

  Future<void> settings() async {
    notifyListeners();
    await Future.wait([
      preferences.setString('language', catalog.language),
      preferences.setBool('music', music),
      preferences.setBool('effects', effects),
      preferences.setBool('animations', animations),
      preferences.setBool('typewriter', typewriter),
      preferences.setDouble('volume', volume),
      preferences.setDouble('speed', speed),
      preferences.setDouble('textScale', textScale),
    ]);
  }

  Future<void> importSave(String text) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      final imported = StoryEngine(engine.data, saved: text);
      await engine.write?.call(imported.export());
      engine.record = clone<Json>(imported.record);
      resume();
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
