import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../game/controller.dart';
import '../game/engine.dart';

class Portrait extends StatefulWidget {
  const Portrait({
    super.key,
    required this.person,
    required this.game,
    this.emotion = 'neutral',
    this.fit = BoxFit.contain,
    this.visibleFraction = 1,
  });
  final Json person;
  final GameController game;
  final String emotion;
  final BoxFit fit;

  /// Crop the lower body for dialogue shots, without resampling the artwork.
  /// Wardrobe previews keep the complete original sprite.
  final double visibleFraction;
  @override
  State<Portrait> createState() => _PortraitState();
}

class _PortraitState extends State<Portrait> {
  ImageStream? stream;
  ImageStreamListener? listener;
  ui.Image? image;
  String path = '';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    resolve();
  }

  @override
  void didUpdateWidget(Portrait old) {
    super.didUpdateWidget(old);
    resolve();
  }

  void resolve() {
    final next = widget.game.asset(
      widget.person['emotion_images']?[widget.emotion] ??
          widget.person['image'],
    );
    if (path == next) return;
    path = next;
    if (stream != null && listener != null) stream!.removeListener(listener!);
    stream = AssetImage(next).resolve(createLocalImageConfiguration(context));
    listener = ImageStreamListener((info, sync) {
      if (!mounted) return;
      final old = image;
      setState(() => image = info.image.clone());
      old?.dispose();
    });
    stream!.addListener(listener!);
  }

  @override
  void dispose() {
    if (listener != null) stream?.removeListener(listener!);
    image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      painter: _SpritePainter(
        image,
        widget.person['columns'] ?? 1,
        widget.person['frames']?[widget.emotion] ?? 0,
        widget.fit,
        widget.visibleFraction,
      ),
      size: Size.infinite,
    ),
  );
}

class _SpritePainter extends CustomPainter {
  _SpritePainter(
    this.image,
    this.columns,
    this.frame,
    this.fit,
    this.visibleFraction,
  );
  final ui.Image? image;
  final int columns, frame;
  final BoxFit fit;
  final double visibleFraction;
  @override
  void paint(Canvas canvas, Size size) {
    final im = image;
    if (im == null || size.isEmpty) return;
    final sourceSize = Size(im.width / columns, im.height * visibleFraction);
    final sizes = applyBoxFit(fit, sourceSize, size);
    final src = Alignment.topCenter
        .inscribe(sizes.source, Offset.zero & sourceSize)
        .shift(Offset(sourceSize.width * frame, 0));
    final dst = Alignment.topCenter.inscribe(
      sizes.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(
      im,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(_SpritePainter old) =>
      old.image != image ||
      old.frame != frame ||
      old.columns != columns ||
      old.fit != fit ||
      old.visibleFraction != visibleFraction;
}

/// Two bounded players crossfade the loop. Door clips play once and hold.
class SceneBackdrop extends StatefulWidget {
  const SceneBackdrop({
    super.key,
    required this.game,
    required this.bg,
    required this.door,
    required this.paused,
    required this.onDoorReady,
    this.enableMedia = true,
  });
  final GameController game;
  final String bg;
  final bool door, paused, enableMedia;
  final VoidCallback onDoorReady;
  @override
  State<SceneBackdrop> createState() => _SceneBackdropState();
}

class _SceneBackdropState extends State<SceneBackdrop> {
  final players = <Player>[];
  final controllers = <VideoController>[];
  final subscriptions = <StreamSubscription>[];
  int active = 0;
  bool ready = false, changing = false, held = false;
  String? failure;
  late String path;
  int reframeTicket = 0;
  bool reframing = false;
  String? requestedDoorPath;
  Uint8List? frozenDoorFrame;
  String get doorPath => MediaQuery.sizeOf(context).aspectRatio < 1
      ? 'assets/video/11.mp4'
      : 'assets/video/door-landscape.mp4';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (players.isEmpty &&
        widget.enableMedia &&
        (widget.door || widget.game.animations) &&
        widget.bg != 'room-v2') {
      start();
    } else if (widget.door &&
        players.isNotEmpty &&
        (path != doorPath || reframing)) {
      unawaited(reframeDoor(doorPath));
    }
  }

  Future<void> reframeDoor(String nextPath) async {
    requestedDoorPath = nextPath;
    if (reframing) return;
    reframing = true;
    final ticket = ++reframeTicket;
    final player = players[0], position = players[0].state.position;
    try {
      await player.pause();
      // Keep the current scene visible during a decoder/source resize. Never
      // expose the unrelated poster of the closed door behind an open doorway.
      try {
        final frame = await player.screenshot();
        if (mounted && ticket == reframeTicket) {
          setState(() => frozenDoorFrame = frame);
        }
      } catch (_) {
        // Unsupported capture must not prevent rotation or resume playback.
      }
      // Window dragging can request several aspect changes. Serialize open/seek
      // and apply only the latest request, rather than racing multiple opens.
      while (mounted && ticket == reframeTicket && requestedDoorPath != path) {
        final next = requestedDoorPath!;
        final metadata = Completer<Duration>();
        final subscription = player.stream.duration.listen((duration) {
          if (duration > Duration.zero && !metadata.isCompleted) {
            metadata.complete(duration);
          }
        });
        try {
          await player.open(Media('asset:///$next'), play: false);
          if (!mounted || ticket != reframeTicket) return;
          path = next;
          final duration = await metadata.future.timeout(
            const Duration(seconds: 15),
          );
          if (!mounted || ticket != reframeTicket) return;
          final lastFrame = duration - const Duration(milliseconds: 50);
          await player.seek(
            held || position > lastFrame ? lastFrame : position,
          );
          // Give the native texture a presentation frame after the seek.
          await Future<void>.delayed(const Duration(milliseconds: 150));
        } finally {
          await subscription.cancel();
        }
      }
      if (mounted && ticket == reframeTicket && !widget.paused && !held) {
        await player.play();
      }
      if (mounted && ticket == reframeTicket) {
        setState(() => failure = null);
      }
    } catch (e) {
      if (mounted) setState(() => failure = e.toString());
    } finally {
      reframing = false;
      if (mounted) setState(() => frozenDoorFrame = null);
    }
  }

  void start() {
    path = widget.door ? doorPath : 'assets/video/${widget.bg}.mp4';
    for (var i = 0; i < (widget.door ? 1 : 2); i++) {
      final p = Player(
        configuration: const PlayerConfiguration(bufferSize: 4 * 1024 * 1024),
      );
      players.add(p);
      controllers.add(VideoController(p));
      final index = i;
      subscriptions.add(
        p.stream.error.listen((e) {
          // A deliberate pause/reload cancels the browser's pending play
          // promise. This is not a loading or decoding failure.
          if (e.contains('play() request was interrupted')) return;
          if (mounted) setState(() => failure = e);
        }),
      );
      subscriptions.add(
        p.stream.position.listen((position) {
          if (!mounted || index != active) return;
          if (!ready && position > Duration.zero) setState(() => ready = true);
          final remaining = p.state.duration - position;
          if (!widget.door &&
              !changing &&
              !widget.paused &&
              p.state.duration.inSeconds > 2 &&
              remaining < const Duration(milliseconds: 800)) {
            unawaited(crossfade());
          }
        }),
      );
      subscriptions.add(
        p.stream.completed.listen((done) {
          if (done && widget.door && !held && !reframing && mounted) {
            held = true;
            unawaited(p.pause());
            widget.onDoorReady();
          }
        }),
      );
      unawaited(p.setVolume(0));
    }
    unawaited(open());
  }

  Future<void> open() async {
    try {
      await players[0].open(Media('asset:///$path'), play: !widget.paused);
    } catch (e) {
      if (mounted) setState(() => failure = e.toString());
    }
  }

  Future<void> crossfade() async {
    changing = true;
    final next = 1 - active, old = active;
    try {
      await players[next].open(Media('asset:///$path'), play: !widget.paused);
      if (!mounted) return;
      setState(() => active = next);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (mounted) await players[old].pause();
    } catch (e) {
      if (mounted) setState(() => failure = e.toString());
    } finally {
      changing = false;
    }
  }

  @override
  void didUpdateWidget(SceneBackdrop old) {
    super.didUpdateWidget(old);
    if (widget.paused != old.paused) {
      for (var i = 0; i < players.length; i++) {
        if (widget.paused || i != active || held || reframing) {
          unawaited(players[i].pause());
        } else {
          unawaited(players[i].play());
        }
      }
    }
    if (!widget.game.animations && !widget.door) {
      for (final p in players) {
        unawaited(p.pause());
      }
    } else if (players.isEmpty &&
        widget.enableMedia &&
        widget.bg != 'room-v2') {
      start();
    } else if (!widget.paused && !held && !reframing && players.isNotEmpty) {
      unawaited(players[active].play());
    }
  }

  @override
  void dispose() {
    reframeTicket++;
    for (final s in subscriptions) {
      unawaited(s.cancel());
    }
    for (final p in players) {
      unawaited(p.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (!widget.door || !ready)
        Image.asset(
          widget.door && doorPath.endsWith('/11.mp4')
              ? 'assets/backgrounds/door-portrait.webp'
              : widget.game.poster(widget.bg),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      if (widget.door || widget.game.animations)
        for (var i = 0; i < controllers.length; i++)
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: ready && i == active ? 1 : 0,
              duration: Duration(milliseconds: widget.door ? 0 : 750),
              child: Video(
                controller: controllers[i],
                controls: NoVideoControls,
                fit: BoxFit.cover,
                fill: Colors.black,
                pauseUponEnteringBackgroundMode: false,
              ),
            ),
          ),
      if (frozenDoorFrame != null)
        Image.memory(
          frozenDoorFrame!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x28141120), Color(0x15141120), Color(0x80141120)],
          ),
        ),
      ),
      if (failure != null && widget.door)
        Center(
          child: FilledButton(
            onPressed: () {
              setState(() => failure = null);
              unawaited(open());
            },
            child: Text(widget.game.t('Попробовать снова')),
          ),
        ),
    ],
  );
}

class Soundscape {
  final music = [Player(), Player()];
  final effect = Player();
  int active = 0, serial = 0;
  String? world;
  String effectWorld = '';
  bool enabled = false, paused = false;
  double volume = .35;
  Timer? timer;
  Future<void> update(
    String bg,
    GameController c, {
    bool suspended = false,
  }) async {
    paused = suspended;
    volume = c.volume;
    enabled = c.music;
    effectWorld = bg;
    if (c.effects && !paused && !c.home && timer == null) {
      timer = Timer.periodic(const Duration(seconds: 27), (_) async {
        if (paused || !c.effects || c.home) return;
        try {
          await effect.setVolume(volume * 22);
          await effect.open(
            Media(
              'asset:///assets/effects/${effectWorld == '2' ? 'dragon' : 'wind'}.wav',
            ),
          );
        } catch (_) {
          // An optional ambience cue must not interrupt the story.
        }
      });
    }
    if (!c.effects || paused || c.home) {
      timer?.cancel();
      timer = null;
      await effect.pause();
    }
    if (!enabled || paused) {
      serial++;
      for (final p in music) {
        await p.pause();
      }
      return;
    }
    if (world != bg) {
      world = bg;
      final ticket = ++serial, old = active;
      active = 1 - active;
      final next = music[active];
      await next.setVolume(0);
      await next.setPlaylistMode(PlaylistMode.single);
      await next.open(Media('asset:///assets/music/$bg.mp3'));
      for (var step = 1; step <= 15; step++) {
        if (ticket != serial || paused || !enabled) {
          if (paused || !enabled) await next.pause();
          return;
        }
        await next.setVolume(volume * 100 * step / 15);
        await music[old].setVolume(volume * 100 * (1 - step / 15));
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      await music[old].pause();
    } else {
      await music[active].setVolume(volume * 100);
      await music[active].play();
    }
  }

  Future<void> dispose() async {
    serial++;
    timer?.cancel();
    for (final p in [...music, effect]) {
      await p.dispose();
    }
  }
}
