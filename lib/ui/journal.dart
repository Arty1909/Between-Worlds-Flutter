import 'package:flutter/material.dart';
import '../game/controller.dart';
import '../game/engine.dart';
import 'game_screen.dart' show gold, paper;
import 'scene_media.dart';

/// The same four journal sections as the original web game.
class Journal extends StatefulWidget {
  const Journal({
    super.key,
    required this.game,
    required this.onWardrobe,
    required this.onPortrait,
    this.initialTab = 'clues',
    this.preview = false,
  });
  final GameController game;
  final VoidCallback onWardrobe;
  final ValueChanged<Json> onPortrait;
  final String initialTab;
  final bool preview;
  @override
  State<Journal> createState() => _JournalState();
}

class _JournalState extends State<Journal> {
  late String tab = widget.initialTab;
  GameController get g => widget.game;
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Widget card(Widget child) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xff332b40), Color(0xff241e30)],
      ),
      border: Border.all(color: const Color(0x44c0a5cf)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: child,
  );
  Widget empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
    child: Text(
      g.t(text),
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: 'Lora',
        fontSize: 18,
        height: 1.7,
        color: Color(0xffbaacc7),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        g.t('ПАМЯТЬ О ПУТЕШЕСТВИИ'),
        style: const TextStyle(fontSize: 10, letterSpacing: 2, color: gold),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in {
            'clues': 'Подсказки',
            'characters': 'Персонажи',
            'history': 'Диалоги',
          }.entries)
            ChoiceChip(
              key: Key('journal-${e.key}'),
              label: Text(g.t(e.value)),
              selected: tab == e.key,
              onSelected: (_) {
                setState(() => tab = e.key);
                if (scroll.hasClients) scroll.jumpTo(0);
              },
            ),
          ActionChip(
            key: const Key('journal-hero'),
            label: Text(g.t('Твоя героиня')),
            onPressed: widget.onWardrobe,
          ),
        ],
      ),
      const SizedBox(height: 20),
      Flexible(
        child: Scrollbar(
          controller: scroll,
          child: SingleChildScrollView(
            key: const Key('journal-scroll'),
            controller: scroll,
            child: switch (tab) {
              'characters' => characters(),
              'history' => history(),
              _ => clues(),
            },
          ),
        ),
      ),
    ],
  );
  Widget clues() {
    final entries = g.view['clues'] as List;
    if (entries.isEmpty) {
      return empty(
        'Пока здесь чистые страницы.\nПодсказки появятся, когда начнётся твоя история.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${g.t('ЗАПИСЬ')} ${(i + 1).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.6,
                      color: Color(0xffbaacc7),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    g.t(entries[i]['title']),
                    style: const TextStyle(
                      fontFamily: 'Lora',
                      fontSize: 20,
                      color: gold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    g.t(entries[i]['text']),
                    style: const TextStyle(height: 1.7, color: paper),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget characters() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        g.t(
          widget.preview
              ? 'Десять людей по ту сторону двери. У каждого — ремесло, мечта и жизнь за пределами твоего путешествия.'
              : 'Каждая встреча оставляет след. Выборы меняют доверие; близость к Верес, Марен или Саэль определяет финал «Там, где тебя ждут».',
        ),
        style: const TextStyle(height: 1.7, color: Color(0xffc5b9cf)),
      ),
      const SizedBox(height: 20),
      LayoutBuilder(
        builder: (context, box) {
          final columns = box.maxWidth >= 700
              ? 4
              : box.maxWidth >= 430
              ? 2
              : 1;
          final width = (box.maxWidth - 12 * (columns - 1)) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final raw in g.view['characters'])
                SizedBox(
                  width: width,
                  child: card(
                    Builder(
                      builder: (context) {
                        final c = obj(raw),
                            met = c['met'] == true,
                            bond = c['bond'] as int;
                        return Column(
                          children: [
                            SizedBox(
                              height: 190,
                              width: double.infinity,
                              child: Portrait(
                                person: c,
                                game: g,
                                visibleFraction: .42,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              g.t(c['name']),
                              style: const TextStyle(
                                fontFamily: 'Lora',
                                fontSize: 20,
                                color: gold,
                              ),
                            ),
                            Text(
                              g.t(c['title']),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xffc5b9cf),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              g.t(c['bio']),
                              style: const TextStyle(fontSize: 13, height: 1.6),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              met
                                  ? '♡ $bond · ${g.t(bond >= 3
                                        ? 'Близость'
                                        : bond >= 1
                                        ? 'Доверие'
                                        : 'Знакомство')}'
                                  : g.t('Вы ещё не знакомы'),
                              style: const TextStyle(fontSize: 12, color: gold),
                            ),
                            TextButton(
                              onPressed: () => widget.onPortrait(c),
                              child: Text(g.t('Рассмотреть ↗')),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
  Widget history() {
    final lines = g.view['history'] as List;
    if (lines.isEmpty) return empty('Ваш первый разговор ещё впереди.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in lines)
          Container(
            margin: const EdgeInsets.only(bottom: 22),
            padding: const EdgeInsets.only(left: 16),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: Color(0x66776184))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line['speaker'] == 'hero'
                      ? g.view['hero']['name']
                      : g.t(
                          g.engine.characters[line['speaker']]?['name'] ??
                              'Твоя история',
                        ),
                  style: const TextStyle(fontSize: 12, color: gold),
                ),
                const SizedBox(height: 8),
                Text(
                  g.t(line['text']),
                  style: const TextStyle(
                    fontFamily: 'Lora',
                    fontSize: 16,
                    height: 1.7,
                    color: paper,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
