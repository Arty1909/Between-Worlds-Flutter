import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../game/controller.dart';
import '../game/engine.dart';
import 'game_screen.dart' show Glass, gold, paper;
import 'scene_media.dart';
import 'journal.dart';

class GamePanels {
  GamePanels(this.context, this.g);
  final BuildContext context;
  final GameController g;
  Future<void> sheet(
    String title,
    Widget Function(BuildContext, StateSetter) body, {
    double width = 760,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) => ListenableBuilder(
          listenable: g,
          builder: (context, child) => Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: width,
                maxHeight: MediaQuery.sizeOf(context).height * .88,
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            g.t(title),
                            style: const TextStyle(
                              fontSize: 24,
                              fontFamily: 'Lora',
                              color: gold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: g.t('Закрыть'),
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const Divider(height: 22),
                    Flexible(child: body(context, setLocal)),
                    if (g.error != null)
                      Text(
                        g.t(g.error),
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> newStory() async {
    var name = g.catalog.language == 'ru' ? 'Арти' : 'Arty';
    await sheet(
      'Начать историю',
      (ctx, setLocal) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('hero-name'),
              initialValue: name,
              onChanged: (value) => name = value,
              maxLength: 24,
              decoration: InputDecoration(labelText: g.t('Имя героини')),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 18),
            if (g.view['started'])
              Text(
                g.t(
                  'Автосохранение будет заменено. Ручные сохранения останутся.',
                ),
              ),
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('start-story'),
              onPressed: g.busy
                  ? null
                  : () async {
                      await g.act('new', {'name': name});
                      if (ctx.mounted && g.error == null) Navigator.pop(ctx);
                    },
              child: Text(g.t('Начать историю')),
            ),
          ],
        ),
      ),
      width: 460,
    );
  }

  void wardrobe() {
    var selected = g.view['look'] as String, emotion = 'neutral';
    unawaited(
      sheet('Гардероб', (ctx, setLocal) {
        final look = obj(g.engine.data['looks'][selected]);
        return LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth > 500;
            final portrait = SizedBox(
              height: wide ? box.maxHeight : 300,
              width: wide ? box.maxWidth * .48 : 230,
              child: Portrait(
                person: {...obj(g.engine.data['hero']), ...look},
                game: g,
                emotion: emotion,
              ),
            );
            final options = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in obj(g.engine.data['looks']).entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: selected == entry.key
                            ? gold.withValues(alpha: .16)
                            : Colors.transparent,
                        side: BorderSide(
                          color: selected == entry.key ? gold : Colors.white24,
                        ),
                      ),
                      onPressed: () => setLocal(() => selected = entry.key),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              g.t(entry.value['name']),
                              style: const TextStyle(
                                fontSize: 16,
                                color: paper,
                              ),
                            ),
                            Text(
                              g.t(entry.value['detail']),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xffb8adbe),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Wrap(
                  spacing: 6,
                  children: obj(g.engine.data['emotions']).entries
                      .map(
                        (e) => ChoiceChip(
                          label: Text(g.t(e.value['label'])),
                          selected: emotion == e.key,
                          onSelected: (_) => setLocal(() => emotion = e.key),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: g.busy
                      ? null
                      : () async {
                          await g.act('dress', {'look': selected});
                          if (ctx.mounted && g.error == null) {
                            Navigator.pop(ctx);
                          }
                        },
                  child: Text(g.t('Надеть образ')),
                ),
              ],
            );
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      portrait,
                      const SizedBox(width: 20),
                      Expanded(child: SingleChildScrollView(child: options)),
                    ],
                  )
                : SingleChildScrollView(
                    child: Column(children: [portrait, options]),
                  );
          },
        );
      }),
    );
  }

  void journal({String tab = 'clues', bool preview = false}) {
    unawaited(
      sheet(
        preview ? 'По ту сторону двери' : 'Твой дневник',
        (ctx, setLocal) => Journal(
          game: g,
          initialTab: tab,
          preview: preview,
          onWardrobe: wardrobe,
          onPortrait: portraitPreview,
        ),
        width: 920,
      ),
    );
  }

  void cast() => journal(tab: 'characters', preview: true);

  void portraitPreview(Json person) {
    var emotion = 'neutral';
    unawaited(
      sheet(
        person['name'],
        (ctx, setLocal) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: MediaQuery.sizeOf(ctx).height * .45,
                width: 340,
                child: Portrait(
                  person: person,
                  game: g,
                  emotion: emotion,
                  visibleFraction: .55,
                ),
              ),
              const SizedBox(height: 16),
              Text(g.t(person['bio']), style: const TextStyle(height: 1.7)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in obj(g.engine.data['emotions']).entries)
                    if (obj(person['frames']).containsKey(e.key))
                      ChoiceChip(
                        label: Text(g.t(e.value['label'])),
                        selected: emotion == e.key,
                        onSelected: (_) => setLocal(() => emotion = e.key),
                      ),
                ],
              ),
            ],
          ),
        ),
        width: 560,
      ),
    );
  }

  void saves() {
    unawaited(
      sheet(
        'Сохранения',
        (ctx, setLocal) => ListView(
          shrinkWrap: true,
          children: [
            for (final slot in g.view['slots'])
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Glass(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        slot['slot'] == 'auto'
                            ? g.t('Автосохранение')
                            : g.format('Сохранение {number}', {
                                'number': slot['slot'],
                              }),
                        style: const TextStyle(color: gold, fontSize: 18),
                      ),
                      Text(
                        slot['exists']
                            ? '${slot['name']} · ${g.t(slot['location'])}'
                            : g.t('Пустая ячейка'),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        children: [
                          if (slot['slot'] != 'auto')
                            TextButton(
                              onPressed: !g.busy && g.view['started']
                                  ? () async {
                                      if (slot['exists']) {
                                        final yes = await showDialog<bool>(
                                          context: ctx,
                                          builder: (context) => AlertDialog(
                                            content: Text(
                                              g.t('Заменить это сохранение?'),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  false,
                                                ),
                                                child: Text(g.t('Отмена')),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  true,
                                                ),
                                                child: Text(g.t('Сохранить')),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (yes != true) return;
                                      }
                                      await g.act('save', {
                                        'slot': slot['slot'],
                                      });
                                    }
                                  : null,
                              child: Text(g.t('Сохранить')),
                            ),
                          OutlinedButton(
                            onPressed: slot['exists'] && !g.busy
                                ? () async {
                                    await g.act('load', {'slot': slot['slot']});
                                    if (ctx.mounted && g.error == null) {
                                      Navigator.pop(ctx);
                                    }
                                  }
                                : null,
                            child: Text(g.t('Загрузить')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void settings() {
    unawaited(
      sheet(
        'Настройки',
        (ctx, setLocal) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: g.catalog.language,
                decoration: InputDecoration(labelText: g.t('Язык')),
                items: Catalog.languages.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (v) {
                  g.catalog.language = v!;
                  unawaited(g.settings());
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text(g.t('Фоновая музыка')),
                value: g.music,
                onChanged: (v) {
                  g.music = v;
                  unawaited(g.settings());
                },
              ),
              SwitchListTile(
                title: Text(g.t('Звуковые эффекты миров')),
                value: g.effects,
                onChanged: (v) {
                  g.effects = v;
                  unawaited(g.settings());
                },
              ),
              Text(g.t('Громкость')),
              Slider(
                value: g.volume,
                onChanged: (v) {
                  g.volume = v;
                  unawaited(g.settings());
                },
              ),
              SwitchListTile(
                title: Text(g.t('Анимация фона')),
                value: g.animations,
                onChanged: (v) {
                  g.animations = v;
                  unawaited(g.settings());
                },
              ),
              SwitchListTile(
                title: Text(g.t('Плавное появление текста')),
                value: g.typewriter,
                onChanged: (v) {
                  g.typewriter = v;
                  unawaited(g.settings());
                },
              ),
              Text(g.t('Скорость текста')),
              Slider(
                value: g.speed,
                min: 20,
                max: 100,
                onChanged: (v) {
                  g.speed = v;
                  unawaited(g.settings());
                },
              ),
              Text(g.t('Размер текста')),
              Slider(
                value: g.textScale,
                min: .85,
                max: 1.4,
                onChanged: (v) {
                  g.textScale = v;
                  unawaited(g.settings());
                },
              ),
              const Divider(),
              TextButton.icon(
                onPressed: exportSave,
                icon: const Icon(Icons.copy),
                label: Text(g.t('Копировать сохранение')),
              ),
              TextButton.icon(
                onPressed: importSave,
                icon: const Icon(Icons.input),
                label: Text(g.t('Импорт сохранения')),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => showLicensePage(
                  context: ctx,
                  applicationName: 'Between Worlds',
                  applicationVersion: '2.0.2',
                ),
                child: Text(g.t('Лицензии')),
              ),
            ],
          ),
        ),
        width: 540,
      ),
    );
  }

  Future<void> exportSave() async {
    await Clipboard.setData(ClipboardData(text: g.engine.export()));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(g.t('Сохранение скопировано'))));
    }
  }

  Future<void> importSave() async {
    var input = '';
    String? issue;
    await sheet(
      'Импорт сохранения',
      (ctx, setLocal) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              onChanged: (value) => input = value,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: g.t('Вставь JSON сохранения'),
                errorText: issue,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () async {
                try {
                  await g.importSave(input);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (_) {
                  if (ctx.mounted) {
                    setLocal(
                      () => issue = g.t('Не удалось прочитать сохранение.'),
                    );
                  }
                }
              },
              child: Text(g.t('Загрузить')),
            ),
          ],
        ),
      ),
      width: 600,
    );
  }
}
