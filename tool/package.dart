import 'dart:io';
import 'package:archive/archive_io.dart';
import 'audit_locales.dart';

/// Packages only compiled runtime files. Run after the desired Flutter builds.
Future<void> main(List<String> args) async {
  final root = Directory.fromUri(Platform.script.resolve('../')).absolute;
  final localeErrors = auditLocales(root);
  if (localeErrors.isNotEmpty) {
    throw StateError('Localization audit failed:\n${localeErrors.join('\n')}');
  }
  final output = Directory('${root.path}/output');
  await output.create(recursive: true);
  final targets = args.isEmpty ? ['web', 'windows', 'android'] : args;
  for (final target in targets) {
    if (target == 'android') {
      final apk = File(
        '${root.path}/build/app/outputs/flutter-apk/app-release.apk',
      );
      final input = InputFileStream(apk.path);
      final contents = ZipDecoder().decodeStream(input);
      final abis = contents.files
          .where((f) => f.name.startsWith('lib/'))
          .map((f) => f.name.split('/')[1])
          .toSet();
      await input.close();
      if (abis.length != 1 || !abis.contains('arm64-v8a')) {
        throw StateError(
          'Build the Android release with --target-platform android-arm64 first.',
        );
      }
      final file = await apk.copy(
        '${output.path}/between-worlds-flutter-arm64-v8a.apk',
      );
      stdout.writeln(
        '${file.path} (${(await file.length() / 1048576).toStringAsFixed(1)} MiB)',
      );
      continue;
    }
    if (!['web', 'windows'].contains(target)) {
      throw ArgumentError('Supported packages: web, windows, android');
    }
    final source = Directory(
      '${root.path}/build/${target == 'web' ? 'web' : 'windows/x64/runner/Release'}',
    );
    if (!source.existsSync()) throw StateError('Build $target first.');
    final web = target == 'web';
    final staged = Directory('${output.path}/$target');
    final zip = ZipFileEncoder()
      ..create('${output.path}/between-worlds-flutter-$target.zip');
    for (final file
        in source
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()) {
      final relative = file.path
          .substring(source.path.length + 1)
          .replaceAll('\\', '/');
      if (relative.split('/').any((p) => p.startsWith('.')) ||
          relative.endsWith('.map') ||
          relative.endsWith('.pdb')) {
        continue;
      }
      final destination = File('${staged.path}/$relative');
      await destination.parent.create(recursive: true);
      if (web && relative == 'index.html') {
        final html = (await file.readAsString()).replaceFirst(
          RegExp(r'<base href="[^"]*">'),
          '<base href="./">',
        );
        await destination.writeAsString(html);
      } else {
        await file.copy(destination.path);
      }
      await zip.addFile(destination, relative);
    }
    if (web) {
      final config = File('${staged.path}/.htaccess');
      await config.writeAsString('''DirectoryIndex index.html
Options -Indexes
<IfModule mod_mime.c>
  AddType application/wasm .wasm
  AddType video/mp4 .mp4
  AddType image/webp .webp
  AddType font/ttf .ttf
</IfModule>
<IfModule mod_headers.c>
  <FilesMatch "^(index\\.html|flutter_bootstrap\\.js|flutter_service_worker\\.js|manifest\\.json)\$">
    Header set Cache-Control "no-cache"
  </FilesMatch>
</IfModule>
''');
      await zip.addFile(config, '.htaccess');
    }
    await zip.close();
    stdout.writeln('${output.path}/between-worlds-flutter-$target.zip');
  }
}
