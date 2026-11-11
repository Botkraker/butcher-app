import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app.dart';
import 'db.dart';
import 'native.dart';
import 'repo.dart';
import 'sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Always sideways, full screen; the bars come back with a swipe.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final native = AndroidNative();
  final prefs = Prefs(native);
  // Same file as the Kotlin app: /data/data/tn.butcher.app/databases/butcher.db
  final db = await openButcherDb(databaseFactory, p.join(await getDatabasesPath(), dbName));
  final neon = Neon(http.Client());

  late final Repo repo;
  Future<String?> push() async {
    final r = await pushAll(db, prefs, neon);
    repo.syncedAt(await prefs.lastSync());
    return r;
  }

  // No Neon address built in: nothing to send, no retry (the Kotlin worker failed the same way).
  final syncer = Syncer(() async => neon.configured ? push() : null);
  repo = Repo(db, prefs, kick: syncer.kick);
  await repo.init(firstInstallTime: await native.firstInstallTime());
  syncer.kick();
  runApp(ButcherApp(Deps(repo, native, push, neon)));
}
