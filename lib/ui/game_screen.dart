import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../game/controller.dart';
import '../game/engine.dart';
import 'scene_media.dart';
import 'panels.dart';

const gold = Color(0xffd6bb83), paper = Color(0xffeee6da);

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.game, this.enableMedia = true});
  final GameController game;
  final bool enableMedia;
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  GameController get g => widget.game;
  Soundscape? sound;
  final camera = TransformationController(),
      dialogueKey = GlobalKey<DialogueState>();
  late final panels = GamePanels(context, g);
  String lastBg = '';
  bool doorReady = false, doorDismissed = false, suspended = false;
  bool get cinematic => !g.home && g.view['bg'] == '11' && !doorDismissed;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    g.addListener(changed);
    if (widget.enableMedia) sound = Soundscape();
    changed();
  }

  void changed() {
    final bg = g.home ? '3' : g.view['bg'] as String;
    if (bg != lastBg || g.home) {
      lastBg = bg;
      doorReady = false;
      doorDismissed = false;
      camera.value = Matrix4.identity();
    }
    if (mounted) setState(() {});
    unawaited(
      sound?.update(bg, g, suspended: suspended).catchError((Object e) {
        if (mounted) {
          setState(
            () => g.error = 'Audio is unavailable. Try enabling sound again.',
          );
        }
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    suspended = state != AppLifecycleState.resumed;
    changed();
  }

  @override
  void dispose() {
    g.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    camera.dispose();
    unawaited(sound?.dispose());
    super.dispose();
  }

  void next() {
    if (cinematic || g.arrival != null || g.home || g.scenery || g.busy) return;
    dialogueKey.currentState?.next();
  }

  Color accent(Json v) {
    final s = v['character']?['color'] as String?;
    return s == null
        ? gold
        : Color(int.parse(s.replaceFirst('#', 'ff'), radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final v = g.view,
        bg = g.home ? '3' : v['bg'] as String,
        wide = MediaQuery.sizeOf(context).width >= 760;
    return PopScope(
      canPop: g.home,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (g.scenery) {
            g.inspect();
          } else if (!cinematic) {
            g.goHome();
          }
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): next,
          const SingleActivator(LogicalKeyboardKey.enter): next,
          const SingleActivator(LogicalKeyboardKey.keyJ): panels.journal,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  if (!cinematic) header(wide),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(
                            child: InteractiveViewer(
                              transformationController: camera,
                              panEnabled: g.scenery,
                              scaleEnabled: g.scenery,
                              minScale: 1,
                              maxScale: 1.8,
                              child: SizedBox(
                                width: box.maxWidth,
                                height: box.maxHeight,
                                child: SceneBackdrop(
                                  key: ValueKey('$bg-${g.home}'),
                                  game: g,
                                  bg: bg,
                                  door: bg == '11',
                                  paused: suspended,
                                  enableMedia: widget.enableMedia,
                                  onDoorReady: () {
                                    if (mounted) {
                                      setState(() => doorReady = true);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                          if (g.home)
                            home(box, wide, v)
                          else if (cinematic)
                            GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: doorReady
                                  ? () => setState(() => doorDismissed = true)
                                  : null,
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  padding: const EdgeInsets.all(30),
                                  child: Glass(
                                    width: 380,
                                    child: Text(
                                      g.t(
                                        doorReady
                                            ? 'Коснись экрана, чтобы продолжить'
                                            : 'Открывается дверь…',
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          else if (g.arrival != null)
                            Center(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(28),
                                child: Glass(
                                  width: 600,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.auto_awesome,
                                        color: gold,
                                        size: 36,
                                      ),
                                      const SizedBox(height: 22),
                                      Text(
                                        g.t(g.arrival!['title']),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontFamily: 'Lora',
                                          fontSize: 30,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      Text(
                                        g.t(g.arrival!['text']),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 19,
                                          height: 1.6,
                                        ),
                                      ),
                                      const SizedBox(height: 26),
                                      FilledButton(
                                        onPressed: g.dismissArrival,
                                        child: Text(g.t('Продолжить путь')),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else ...[
                            if (!g.scenery)
                              Positioned.fill(child: actors(box, wide, v)),
                            Positioned(
                              top: 14,
                              left: 16,
                              child: Row(
                                children: [
                                  if (!g.scenery)
                                    OutlinedButton.icon(
                                      onPressed: g.togglePanel,
                                      icon: const Icon(Icons.menu, size: 17),
                                      label: Text(g.t('Панель')),
                                    ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    key: const Key('inspect'),
                                    onPressed: g.inspect,
                                    icon: Icon(
                                      g.scenery
                                          ? Icons.arrow_back
                                          : Icons.open_with,
                                      size: 17,
                                    ),
                                    label: Text(
                                      g.t(
                                        g.scenery
                                            ? 'Вернуться к истории'
                                            : 'Осмотреть мир',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (g.scenery)
                              Positioned(
                                bottom: 24,
                                left: 24,
                                right: 24,
                                child: Center(
                                  child: Glass(
                                    width: 420,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          g.t('Потяни мир мышью или пальцем'),
                                        ),
                                        Wrap(
                                          alignment: WrapAlignment.center,
                                          children: [
                                            IconButton(
                                              tooltip: g.t('Левый вид'),
                                              onPressed: () => camera.value =
                                                  Matrix4.identity()
                                                    ..translateByDouble(
                                                      -box.maxWidth * .14,
                                                      0,
                                                      0,
                                                      1,
                                                    )
                                                    ..scaleByDouble(
                                                      1.3,
                                                      1.3,
                                                      1,
                                                      1,
                                                    ),
                                              icon: const Icon(
                                                Icons.chevron_left,
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () => camera.value =
                                                  Matrix4.identity(),
                                              child: Text(g.t('Общий план')),
                                            ),
                                            IconButton(
                                              tooltip: g.t('Правый вид'),
                                              onPressed: () => camera.value =
                                                  Matrix4.identity()
                                                    ..translateByDouble(
                                                      -box.maxWidth * .3,
                                                      0,
                                                      0,
                                                      1,
                                                    )
                                                    ..scaleByDouble(
                                                      1.3,
                                                      1.3,
                                                      1,
                                                      1,
                                                    ),
                                              icon: const Icon(
                                                Icons.chevron_right,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            if (!g.scenery)
                              Positioned(
                                left: wide ? 32 : 12,
                                right: wide ? 32 : 12,
                                bottom: 18,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: v['kind'] == 'ending'
                                      ? ending(v, box)
                                      : Dialogue(
                                          key: dialogueKey,
                                          game: g,
                                          view: v,
                                          color: accent(v),
                                          maxHeight: math.min(
                                            470,
                                            box.maxHeight *
                                                (wide ? 0.48 : 0.50),
                                          ),
                                        ),
                                ),
                              ),
                            if (g.panel && !g.scenery)
                              Positioned(
                                top: 66,
                                bottom: 24,
                                left: 16,
                                width: math.min(300, box.maxWidth - 32),
                                child: Glass(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                g.t('Твой путь'),
                                                style: const TextStyle(
                                                  fontSize: 22,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: g.togglePanel,
                                              icon: const Icon(Icons.close),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          '${v['chapter'] + 1} / 6',
                                          style: const TextStyle(color: gold),
                                        ),
                                        Text(
                                          g.t(v['chapters'][v['chapter']]),
                                          style: const TextStyle(fontSize: 18),
                                        ),
                                        const Divider(height: 30),
                                        for (final e in obj(v['stats']).entries)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    g.t(
                                                      g
                                                          .engine
                                                          .data['stat_names'][e
                                                          .key],
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  '${e.value}',
                                                  style: const TextStyle(
                                                    color: gold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        const Divider(height: 30),
                                        Text(
                                          g.t('Твои решения меняют историю'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                          if (g.error != null)
                            Positioned(
                              left: 16,
                              right: 16,
                              bottom: 8,
                              child: Material(
                                color: const Color(0xff583847),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 14),
                                  child: Row(
                                    children: [
                                      Expanded(child: Text(g.t(g.error))),
                                      IconButton(
                                        onPressed: () =>
                                            setState(() => g.error = null),
                                        icon: const Icon(Icons.close),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget header(bool wide) => Container(
    height: wide ? 76 : 64,
    padding: EdgeInsets.symmetric(horizontal: wide ? 30 : 8),
    decoration: const BoxDecoration(
      color: Color(0xee191522),
      border: Border(bottom: BorderSide(color: Color(0x33d6bb83))),
    ),
    child: Row(
      children: [
        InkWell(
          onTap: g.goHome,
          child: Row(
            children: [
              Image.asset(
                'assets/branding/icon-key-192.png',
                width: wide ? 50 : 40,
              ),
              const SizedBox(width: 12),
              if (wide || MediaQuery.sizeOf(context).width >= 600)
                Text(
                  g.t('МЕЖДУ МИРАМИ'),
                  style: TextStyle(
                    fontSize: wide ? 14 : 11,
                    letterSpacing: wide ? 3 : 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        const Spacer(),
        nav(
          Icons.checkroom,
          'Гардероб',
          panels.wardrobe,
          MediaQuery.sizeOf(context).width >= 1100,
        ),
        nav(
          Icons.menu_book_outlined,
          'Дневник',
          panels.journal,
          MediaQuery.sizeOf(context).width >= 1100,
        ),
        nav(
          Icons.bookmark_border,
          'Сохранения',
          panels.saves,
          MediaQuery.sizeOf(context).width >= 1100,
        ),
        IconButton(
          tooltip: g.t(g.music ? 'Выключить звук' : 'Включить звук'),
          onPressed: () {
            g.music = !g.music;
            unawaited(g.settings());
          },
          icon: Icon(g.music ? Icons.music_note : Icons.music_off, color: gold),
        ),
        IconButton(
          tooltip: g.t('Настройки'),
          onPressed: panels.settings,
          icon: const Icon(Icons.tune, color: gold),
        ),
      ],
    ),
  );
  Widget nav(IconData icon, String title, VoidCallback tap, bool wide) => wide
      ? TextButton.icon(
          onPressed: tap,
          icon: Icon(icon, color: gold, size: 19),
          label: Text(g.t(title), style: const TextStyle(color: paper)),
        )
      : IconButton(
          tooltip: g.t(title),
          onPressed: tap,
          icon: Icon(icon, color: gold, size: 22),
        );
  Widget home(BoxConstraints box, bool wide, Json v) {
    final compact = box.maxHeight < 560;
    final short = box.maxHeight < 380;
    final inset = wide ? (box.maxWidth * .045).clamp(24.0, 64.0) : 24.0;
    final copyWidth = wide
        ? math.min(600.0, box.maxWidth * .5)
        : box.maxWidth - inset * 2;
    final gap = compact ? 12.0 : 22.0;
    return Stack(
      key: const Key('home-cover'),
      children: [
        Positioned(
          right: wide ? box.maxWidth * .05 : -box.maxWidth * .3,
          bottom: -box.maxHeight * .04,
          width: wide ? box.maxWidth * .5 : box.maxWidth,
          height: box.maxHeight * .94,
          child: Portrait(person: obj(v['hero']), game: g, emotion: 'warm'),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xee161320), Color(0x11161320)],
                end: Alignment.centerRight,
              ),
            ),
          ),
        ),
        Positioned(
          left: inset,
          top: short ? 10 : 24,
          bottom: short ? 10 : 24,
          width: copyWidth,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: copyWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!compact) ...[
                      Text(
                        g.t('ТВОЯ ИСТОРИЯ НАЧИНАЕТСЯ ЗДЕСЬ'),
                        style: const TextStyle(
                          color: gold,
                          fontSize: 11,
                          letterSpacing: 3,
                        ),
                      ),
                      SizedBox(height: gap),
                    ],
                    Text(
                      g.t('Между мирами'),
                      style: TextStyle(
                        fontFamily: 'Lora',
                        fontSize: wide
                            ? (compact ? 52 : 82)
                            : (compact ? 42 : 54),
                        height: 1.08,
                        color: paper,
                      ),
                    ),
                    SizedBox(height: gap),
                    Text(
                      g.t('ОСКОЛКИ КЛЮЧА'),
                      style: TextStyle(
                        color: gold,
                        fontSize: compact ? 10 : 12,
                        letterSpacing: 3,
                      ),
                    ),
                    if (!short) ...[
                      SizedBox(height: gap),
                      Text(
                        g.t(
                          'Одна дверь. Десять встреч.\nИ выбор, который никто не сделает за тебя.',
                        ),
                        style: TextStyle(
                          fontSize: compact ? 16 : 18,
                          color: paper,
                          height: 1.5,
                        ),
                      ),
                    ],
                    SizedBox(height: gap),
                    SizedBox(
                      width: 320,
                      child: FilledButton(
                        key: const Key('new-game'),
                        onPressed: panels.newStory,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: Text(g.t('Начать историю'))),
                            const Icon(Icons.north_east, size: 18),
                          ],
                        ),
                      ),
                    ),
                    if (v['started']) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: 320,
                        child: OutlinedButton(
                          onPressed: g.resume,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          child: Text(g.t('Продолжить')),
                        ),
                      ),
                    ],
                    SizedBox(height: compact ? 4 : 12),
                    TextButton(
                      onPressed: panels.cast,
                      child: Text(g.t('Познакомиться с миром')),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 18),
                      Text(
                        g.t('✧ Фэнтези   ♡ Отношения   ◇ 4 концовки'),
                        style: const TextStyle(
                          color: Color(0xffb5abbf),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget actors(BoxConstraints box, bool wide, Json v) {
    final npc = v['character'] == null ? null : obj(v['character']);
    final hero = obj(v['hero']);
    final speaker = v['feedback'] != null ? 'hero' : v['line']?['speaker'];
    final heroSpeaks =
        speaker == 'hero' || npc == null || speaker == 'narrator';
    // Legacy 'full' describes the scene, not a full-body dialogue portrait.
    final full = v['kind'] == 'cinematic' && v['framing'] == 'full';
    final close = v['framing'] == 'close' || v['bg'] == 'room-v2';
    final fraction = full ? 1.0 : (close || !wide ? .56 : .66);
    final top = box.maxHeight * (wide ? .06 : .10);
    final height = box.maxHeight - top;
    Widget actor(Json person, String emotion, String id) => AnimatedSwitcher(
      duration: Duration(milliseconds: g.animations ? 450 : 0),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: Portrait(
        key: ValueKey('$id-$emotion-${v['look']}'),
        person: person,
        emotion: emotion,
        game: g,
        visibleFraction: fraction,
        fit: full ? BoxFit.contain : BoxFit.cover,
      ),
    );
    // Fixed top anchors keep faces still while expressions crossfade. Dialogue
    // portraits are foreground medium shots, never feet placed on furniture.
    if (!wide) {
      return Padding(
        padding: EdgeInsets.only(top: top),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: box.maxWidth * .96,
            height: height,
            child: actor(
              heroSpeaks ? hero : npc,
              heroSpeaks
                  ? v['hero_emotion'] ?? 'neutral'
                  : npc['emotion'] ?? 'neutral',
              heroSpeaks ? 'hero' : npc['id'],
            ),
          ),
        ),
      );
    }
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned(
          left: npc == null ? null : box.maxWidth * .025,
          right: npc == null ? box.maxWidth * .08 : null,
          top: top,
          width: box.maxWidth * (npc == null ? .45 : .40),
          height: height,
          child: actor(hero, v['hero_emotion'] ?? 'neutral', 'hero'),
        ),
        if (npc != null)
          Positioned(
            right: box.maxWidth * .025,
            top: top,
            width: box.maxWidth * .40,
            height: height,
            child: actor(npc, npc['emotion'] ?? 'neutral', npc['id']),
          ),
      ],
    );
  }

  Widget ending(Json v, BoxConstraints box) => Glass(
    width: 660,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: box.maxHeight * .72),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              g.t(v['ending']['title']),
              style: const TextStyle(
                fontSize: 28,
                fontFamily: 'Lora',
                color: gold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              g.t(v['ending']['text']),
              style: const TextStyle(fontSize: 19, height: 1.6),
            ),
            if ((v['ending']['afterword'] ?? '').isNotEmpty) ...[
              const SizedBox(height: 15),
              Text(g.t(v['ending']['afterword'])),
            ],
            const SizedBox(height: 24),
            FilledButton(onPressed: g.goHome, child: Text(g.t('Главное меню'))),
          ],
        ),
      ),
    ),
  );
}

class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.width,
    this.color = gold,
    this.padding = 20,
  });
  final Widget child;
  final double? width;
  final Color color;
  final double padding;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        width: width,
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .7)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xe8392c36), Color(0xed211c2e)],
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    ),
  );
}

class Dialogue extends StatefulWidget {
  const Dialogue({
    super.key,
    required this.game,
    required this.view,
    required this.color,
    required this.maxHeight,
  });
  final GameController game;
  final Json view;
  final Color color;
  final double maxHeight;
  @override
  State<Dialogue> createState() => DialogueState();
}

class DialogueState extends State<Dialogue> {
  Timer? timer;
  int visible = 0;
  String text = '', signature = '';
  bool choices = false;
  final selected = <String>[];
  GameController get g => widget.game;
  Json get v => widget.view;
  @override
  void initState() {
    super.initState();
    sync();
  }

  @override
  void didUpdateWidget(Dialogue oldWidget) {
    super.didUpdateWidget(oldWidget);
    sync();
  }

  void sync() {
    final next =
        '${v['node']}/${v['beat']}/${v['feedback']}/${g.catalog.language}';
    if (next == signature) {
      if (!g.typewriter) {
        timer?.cancel();
        visible = text.characters.length;
      }
      return;
    }
    signature = next;
    timer?.cancel();
    choices = false;
    selected.clear();
    text = g.t(v['feedback']?['text'] ?? v['line']['text']);
    visible = g.typewriter ? 0 : text.characters.length;
    if (g.typewriter) {
      timer = Timer.periodic(Duration(milliseconds: g.speed.round()), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => visible = math.min(visible + 1, text.characters.length));
        if (visible == text.characters.length) t.cancel();
      });
    }
  }

  void next() {
    if (g.busy) return;
    if (visible < text.characters.length) {
      timer?.cancel();
      setState(() => visible = text.characters.length);
      return;
    }
    if (v['can_advance']) {
      unawaited(g.act('advance'));
    } else {
      setState(() => choices = true);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final speaker = v['feedback'] != null ? 'narrator' : v['line']['speaker'];
    final name = speaker == 'hero'
        ? v['name']
        : speaker == 'narrator'
        ? 'Твоя история'
        : g.engine.characters[speaker]?['name'] ??
              v['character']?['name'] ??
              'Твоя история';
    return Glass(
      width: 680,
      color: widget.color,
      padding: 18,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  color: widget.color,
                  size: 21,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    speaker == 'hero' ? name : g.t(name),
                    style: TextStyle(
                      color: widget.color,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Text(
                  '${v['beat'] + 1} / ${v['beats']}',
                  style: const TextStyle(
                    color: Color(0xffb6a8c0),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Flexible(
              child: SingleChildScrollView(
                key: ValueKey('$signature-$choices'),
                child: choices
                    ? choiceContent()
                    : Semantics(
                        label: text,
                        child: ExcludeSemantics(
                          child: Text(
                            text.characters.take(visible).toString(),
                            style: TextStyle(
                              fontFamily: 'Lora',
                              fontSize: 21 * g.textScale,
                              height: 1.5,
                              color: paper,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            if (v['feedback'] != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                children: (v['feedback']['effects'] as List)
                    .map(
                      (e) => Text(
                        g.t(e),
                        style: TextStyle(color: widget.color, fontSize: 12),
                      ),
                    )
                    .toList(),
              ),
            ],
            const Divider(height: 25, color: Color(0x33cabbcb)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (choices)
                  Expanded(
                    child: TextButton(
                      onPressed: () => setState(() => choices = false),
                      child: Text(g.t('Вернуться к реплике')),
                    ),
                  )
                else ...[
                  IconButton(
                    key: const Key('dialogue-history'),
                    tooltip: g.t('История диалогов'),
                    onPressed: () =>
                        GamePanels(context, g).journal(tab: 'history'),
                    icon: const Icon(
                      Icons.auto_stories_outlined,
                      size: 18,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: TextButton(
                      key: const Key('dialogue-next'),
                      onPressed: g.busy ? null : next,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              g.t(
                                visible < text.characters.length
                                    ? 'Показать текст'
                                    : v['can_advance']
                                    ? 'Далее'
                                    : 'Выбрать ответ',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Icons.arrow_forward, size: 19),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget choiceContent() {
    if (v['kind'] == 'puzzle') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(g.t('Выбери три разных символа.')),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: (v['symbols'] as List)
                .map(
                  (s) => ChoiceChip(
                    label: Text(
                      '${selected.contains(s['id']) ? '${selected.indexOf(s['id']) + 1}. ' : ''}${g.t(s['name'])}',
                    ),
                    selected: selected.contains(s['id']),
                    onSelected: (_) => setState(() {
                      if (selected.contains(s['id'])) {
                        selected.remove(s['id']);
                      } else if (selected.length < 3) {
                        selected.add(s['id']);
                      }
                    }),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: selected.length == 3 && !g.busy
                ? () => g.act('puzzle', {'symbols': selected.toList()})
                : null,
            child: Text(g.t('Повернуть кольца')),
          ),
          TextButton(
            onPressed: g.busy ? null : () => g.act('skip_puzzle'),
            child: Text(g.t('Попросить помощи')),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in v['choices'])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: widget.color.withValues(alpha: .7)),
                padding: const EdgeInsets.all(16),
              ),
              onPressed: c['available'] && !g.busy
                  ? () => g.act('choose', {'choice': c['id']})
                  : null,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.t(c['text']),
                          style: const TextStyle(fontSize: 16, color: paper),
                        ),
                        if (c['label'] != null)
                          Text(
                            g.t(c['label']),
                            style: TextStyle(fontSize: 11, color: widget.color),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    c['available'] ? Icons.arrow_forward : Icons.lock_outline,
                    size: 17,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
