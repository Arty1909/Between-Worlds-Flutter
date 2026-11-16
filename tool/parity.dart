import 'dart:convert';
import 'dart:io';
import 'package:between_worlds/game/engine.dart';

Future<void> main() async {
  final payload = jsonDecode(await stdin.transform(utf8.decoder).join()) as Map;
  final data = obj(payload['data']);
  for (var run = 0; run < payload['runs'].length; run++) {
    String? saved;
    var game = StoryEngine(
      data,
      write: (s) async {
        saved = s;
      },
    );
    stdout.writeln(jsonEncode({'run': run, 'step': -1, 'view': game.view()}));
    final commands = payload['runs'][run] as List;
    for (var step = 0; step < commands.length; step++) {
      Json result;
      try {
        final view = await game.act(obj(commands[step]));
        result = {'view': view};
        game = StoryEngine(
          data,
          saved: saved,
          write: (s) async {
            saved = s;
          },
        );
      } catch (e) {
        if (e is! StateError) rethrow;
        result = {'error': e.message};
      }
      stdout.writeln(jsonEncode({'run': run, 'step': step, ...result}));
    }
  }
}
