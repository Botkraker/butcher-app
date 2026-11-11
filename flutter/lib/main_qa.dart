// Browser test build only (flutter build web -t lib/main_qa.dart). Never shipped to the phone.
// Same app and screens; the database lives in the browser's memory, settings in a map,
// no voice, and no Neon address, so nothing can reach the real database.
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show inMemoryDatabasePath;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'app.dart';
import 'db.dart';
import 'native.dart';
import 'repo.dart';
import 'sync.dart';

class QaNative implements Native {
  final data = <String, Object?>{};
  @override
  Future<String?> speech() async => 'صوت تجربة';
  @override
  Future<int> firstInstallTime() async => DateTime.now().millisecondsSinceEpoch;
  @override
  Future<String?> getString(String file, String key) async => data['$file/$key'] as String?;
  @override
  Future<int?> getLong(String file, String key) async => data['$file/$key'] as int?;
  @override
  Future<bool?> getBool(String file, String key) async => data['$file/$key'] as bool?;
  @override
  Future<void> putString(String file, String key, String v) async => data['$file/$key'] = v;
  @override
  Future<void> putLong(String file, String key, int v) async => data['$file/$key'] = v;
  @override
  Future<void> putBool(String file, String key, bool v) async => data['$file/$key'] = v;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final native = QaNative();
  final db = await openButcherDb(databaseFactoryFfiWebNoWebWorker, inMemoryDatabasePath);
  final neon = Neon(http.Client(), url: '', conn: '');
  final repo = Repo(db, Prefs(native));
  await repo.init(firstInstallTime: await native.firstInstallTime());
  runApp(ButcherApp(Deps(repo, native, () async => 'QA build: no Neon', neon)));
}
