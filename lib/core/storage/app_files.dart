import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Plain-file storage inside the app's documents folder (`TeslaOrg/<sub>`), used
/// for backups and report exports. [root] is injectable for tests.
class AppFiles {
  AppFiles([Future<Directory> Function()? root]) : _root = root ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _root;

  Future<Directory> dir(String sub) async {
    final base = await _root();
    final d = Directory(p.join(base.path, 'TeslaOrg', sub));
    await d.create(recursive: true);
    return d;
  }

  /// Writes UTF-8 text (never overwrites: a numeric suffix is added on conflict).
  Future<File> write(String sub, String name, String content) async {
    final d = await dir(sub);
    var file = File(p.join(d.path, name));
    var i = 1;
    while (await file.exists()) {
      final base = p.basenameWithoutExtension(name);
      file = File(p.join(d.path, '$base-$i${p.extension(name)}'));
      i++;
    }
    return file.writeAsString(content, flush: true);
  }

  /// Newest first.
  Future<List<File>> list(String sub, {String extension = '.json'}) async {
    final d = await dir(sub);
    final files = <File>[
      await for (final e in d.list()) if (e is File && e.path.endsWith(extension)) e,
    ];
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  Future<String> read(File f) => f.readAsString();
}

final appFilesProvider = Provider<AppFiles>((ref) => AppFiles());
