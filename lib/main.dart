import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'game/controller.dart';
import 'ui/game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const BetweenWorlds());
}

class BetweenWorlds extends StatefulWidget {
  const BetweenWorlds({super.key});
  @override
  State<BetweenWorlds> createState() => _AppState();
}

class _AppState extends State<BetweenWorlds> {
  Catalog? startupCatalog;
  GameController? game;
  late Future<GameController> loading = load();
  Future<GameController> load() async {
    final loaded = await GameController.load(
      onCatalogLoaded: (c) => startupCatalog = c,
    );
    game = loaded;
    return loaded;
  }

  @override
  void dispose() {
    game?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<GameController>(
    future: loading,
    builder: (context, snapshot) {
      if (snapshot.hasData) return GameApplication(game: snapshot.data!);
      return _application(
        language: startupCatalog?.language ?? 'en',
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/branding/icon-key-192.png', width: 80),
                  const SizedBox(height: 24),
                  if (snapshot.hasError) ...[
                    Text(
                      startupCatalog?.t(
                            'Could not open the story. Existing saves are preserved.',
                          ) ??
                          'Could not open the story. Existing saves are preserved.',
                      textAlign: TextAlign.center,
                    ),
                    FilledButton(
                      onPressed: () => setState(() => loading = load()),
                      child: Text(
                        startupCatalog?.t('Попробовать снова') ?? 'Try again',
                      ),
                    ),
                  ] else
                    const CircularProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// The chosen game language also drives Flutter's built-in controls and tooltips.
class GameApplication extends StatelessWidget {
  const GameApplication({
    super.key,
    required this.game,
    this.enableMedia = true,
  });
  final GameController game;
  final bool enableMedia;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: game,
    builder: (context, child) => _application(
      language: game.catalog.language,
      home: GameScreen(game: game, enableMedia: enableMedia),
    ),
  );
}

MaterialApp _application({required String language, required Widget home}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Between Worlds',
      locale: Locale(language),
      supportedLocales: Catalog.languages.keys.map(Locale.new).toList(),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xff161320),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xffd6bb83),
          brightness: Brightness.dark,
        ),
        dialogTheme: const DialogThemeData(backgroundColor: Color(0xff211c2c)),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xffd6bb83),
            foregroundColor: const Color(0xff211b2a),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 19),
          ),
        ),
      ),
      home: home,
    );
