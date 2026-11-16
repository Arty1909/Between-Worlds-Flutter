import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:between_worlds/game/controller.dart';
import 'package:between_worlds/game/engine.dart';
import 'package:between_worlds/ui/game_screen.dart';
import 'package:between_worlds/ui/scene_media.dart';

void check(WidgetTester tester) {
  final e = tester.takeException();
  if (e is FlutterError) debugPrint(e.toStringDeep());
  expect(e, isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1440, 900),
  ]) {
    testWidgets('Story, choices, inspection and wardrobe at $size', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final g = (await tester.runAsync(GameController.load))!;
      g.typewriter = false;
      g.animations = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: GameScreen(game: g, enableMedia: false),
        ),
      );
      await tester.pumpAndSettle();
      check(tester);
      expect(tester.widget<SceneBackdrop>(find.byType(SceneBackdrop)).bg, '3');
      expect(
        find.descendant(
          of: find.byKey(const Key('home-cover')),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );
      expect(
        tester.getRect(find.byKey(const Key('new-game'))).bottom,
        lessThanOrEqualTo(size.height),
      );
      await tester.ensureVisible(find.byKey(const Key('new-game')));
      await tester.tap(find.byKey(const Key('new-game')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('hero-name')), 'Arty');
      await tester.ensureVisible(find.byKey(const Key('start-story')));
      await tester.tap(find.byKey(const Key('start-story')));
      await tester.pumpAndSettle();
      check(tester);
      expect(find.byType(Portrait), findsWidgets);
      await tester.tap(find.byKey(const Key('inspect')));
      await tester.pumpAndSettle();
      expect(find.byType(Portrait), findsNothing);
      expect(find.byType(Dialogue), findsNothing);
      await tester.tap(find.byKey(const Key('inspect')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('dialogue-next')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('dialogue-next')));
      await tester.pumpAndSettle();
      check(tester);
      final choices = g.view['choices'] as List;
      expect(choices, isNotEmpty);
      await g.act('choose', {'choice': choices.first['id']});
      await tester.pumpAndSettle();
      check(tester);
      g.textScale = 1.4;
      await g.settings();
      await tester.pumpAndSettle();
      check(tester);
      await tester.tap(find.byIcon(Icons.checkroom));
      await tester.pumpAndSettle();
      check(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      g.dispose();
    });
  }
  test('Storage failure rolls back both state and revision', () async {
    final d = obj(
      jsonDecode(await rootBundle.loadString('assets/data/story.json')),
    );
    final engine = StoryEngine(
      d,
      write: (_) async => throw StateError('disk full'),
    );
    final before = engine.export();
    await expectLater(
      engine.act({'action': 'new', 'name': 'Arty', 'revision': 0}),
      throwsStateError,
    );
    expect(engine.export(), before);
  });
  test('All referenced media and translations are bundled', () async {
    SharedPreferences.setMockInitialValues({});
    final g = await GameController.load();
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final paths = manifest.listAssets().toSet();
    for (final path in g.media.values) {
      expect(paths.contains(path), isTrue, reason: path);
    }
    expect(g.catalog.dictionaries.keys.toSet(), {'en', 'es', 'ru', 'it', 'fr'});
    for (final lang in Catalog.languages.keys) {
      g.catalog.language = lang;
      expect(g.t('Между мирами').isNotEmpty, isTrue);
    }
  });
  test(
    'Recovery never replaces the valid backup with corrupt primary data',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = await GameController.load();
      await first.act('new', {'name': 'Arty'});
      final valid = first.engine.export();
      first.dispose();
      SharedPreferences.setMockInitialValues({
        GameController.saveKey: '{broken',
        '${GameController.saveKey}.backup': valid,
      });
      final recovered = await GameController.load();
      expect(recovered.engine.export(), valid);
      await recovered.act('advance');
      expect(recovered.error, isNull);
      expect(
        recovered.preferences.getString('${GameController.saveKey}.backup'),
        valid,
      );
      expect(recovered.engine.state['beat'], 1);
      recovered.dispose();
    },
  );
}
