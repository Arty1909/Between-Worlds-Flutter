import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:between_worlds/game/controller.dart';
import 'package:between_worlds/main.dart';
import 'package:between_worlds/ui/panels.dart';
import 'package:between_worlds/ui/game_screen.dart';
import 'package:between_worlds/ui/scene_media.dart';
import '../tool/audit_locales.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'All visible story/UI sources, placeholders and dynamic labels are localized',
    () {
      expect(auditLocales(Directory.current), isEmpty);
    },
  );
  for (final lang in Catalog.languages.keys) {
    testWidgets(
      'Saved games and Flutter controls use $lang; names are preserved',
      (tester) async {
        SharedPreferences.setMockInitialValues({'language': lang});
        final g = (await tester.runAsync(GameController.load))!;
        await g.act('new', {'name': 'Вера'});
        g.typewriter = false;
        await tester.pumpWidget(GameApplication(game: g, enableMedia: false));
        await tester.pumpAndSettle();
        final ctx = tester.element(find.byType(GameScreen));
        expect(Localizations.localeOf(ctx).languageCode, lang);
        expect(g.view['hero']['name'], 'Вера');
        final source = g.catalog.dictionaries[lang]!.keys.firstWhere(
          (s) => s.contains('{name}'),
        );
        final rendered = g.t(source.replaceAll('{name}', 'Вера'));
        expect(rendered, contains('Вера'));
        GamePanels(ctx, g).saves();
        await tester.pumpAndSettle();
        for (var i = 1; i <= 3; i++) {
          final label = find.text(
            g.format('Сохранение {number}', {'number': i}),
          );
          await tester.scrollUntilVisible(
            label,
            120,
            scrollable: find
                .descendant(
                  of: find.byType(Dialog),
                  matching: find.byType(Scrollable),
                )
                .last,
          );
          expect(label, findsOneWidget);
        }
        if (lang != 'ru') {
          expect(find.textContaining('Сохранение'), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        g.dispose();
      },
    );
  }
  for (final size in [const Size(320, 640), const Size(1440, 900)]) {
    testWidgets('Journal sections, portraits and dialogue framing at $size', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final g = (await tester.runAsync(GameController.load))!;
      await g.act('new', {'name': 'Arty'});
      g.typewriter = false;
      g.animations = false;
      await tester.pumpWidget(GameApplication(game: g, enableMedia: false));
      await tester.pumpAndSettle();
      for (final portrait in tester.widgetList<Portrait>(
        find.byType(Portrait),
      )) {
        expect(
          portrait.visibleFraction,
          lessThan(1),
          reason: 'Ordinary dialogue is a medium shot',
        );
      }
      expect(
        tester
            .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
            .where((w) => w.opacity > 0 && w.opacity < 1),
        isEmpty,
      );
      final panels = GamePanels(tester.element(find.byType(GameScreen)), g);
      panels.journal();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('journal-clues')), findsOneWidget);
      await tester.tap(find.byKey(const Key('journal-characters')));
      await tester.pumpAndSettle();
      expect(find.text('Veres'), findsOneWidget);
      expect(find.text(g.t('Вы ещё не знакомы')), findsWidgets);
      await tester.ensureVisible(find.text(g.t('Рассмотреть ↗')).first);
      await tester.tap(find.text(g.t('Рассмотреть ↗')).first);
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsWidgets);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(Dialog).last)).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('journal-history')));
      await tester.pumpAndSettle();
      expect(find.text('Your story'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('journal-hero')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<Portrait>(find.byType(Portrait))
            .any((w) => w.visibleFraction == 1),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      g.dispose();
    });
  }
}
