import 'dart:async';

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
  // Both ways: send what is new on the phone, then bring down what is new in Neon.
  Future<String?> push() async {
    final out = await pushAll(db, prefs, neon);
    final inn = await pullAll(db, prefs, neon);
    await repo.reload();
    repo.syncedAt(await prefs.lastSync());
    final errors = [?out, ?inn];
    return errors.isEmpty ? null : errors.join('\n');
  }

  // No Neon address built in: nothing to send, no retry (the Kotlin worker failed the same way).
  final syncer = Syncer(() async => neon.configured ? push() : null);
  repo = Repo(db, prefs, kick: syncer.kick);
  await repo.init(firstInstallTime: await native.firstInstallTime());
  // First start on a phone (new phone, reinstall): read Neon before the starter list is added,
  // so the old products come back instead of 15 new copies.
  if (neon.configured && !await prefs.seedDone()) {
    await push().timeout(const Duration(seconds: 20), onTimeout: () => 'timeout').catchError((Object e) => '$e');
  }
  syncer.kick();
  // New rows from Neon (another phone) arrive within 5 minutes while the app is open.
  Timer.periodic(const Duration(minutes: 5), (_) => syncer.kick());
  runApp(ButcherApp(Deps(repo, native, push, neon)));
}
