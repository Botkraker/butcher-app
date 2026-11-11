# Butcher app (Flutter)

Flutter port of the Kotlin app in `../app/`. Same screens, same words, same rules.
It installs over the Kotlin app (same id `tn.butcher.app`, same debug key) and keeps the phone's data:
it opens the same `butcher.db` file with the same tables, and reads the same settings files.

## Run on the phone (no Android Studio)
1. Once: `flutter doctor --android-licenses` (accept the Android licences).
2. Once, and after you change `../app/local.properties`: `python3 tool/make_secrets.py` (writes `secrets.json`, gitignored).
3. Connect the phone (Wi-Fi adb), then: `flutter run --release --dart-define-from-file=secrets.json`

Build on the same PC as before. A different PC has a different debug key: Android then refuses the update,
and uninstalling would delete the data. Never uninstall.

## Tests (run on the PC, no phone)
`flutter test` runs:
- `test/logic_test.dart`: money, kg, rounding (same as Kotlin), credit balances, order.
- `test/db_test.dart`: an old Kotlin (Room) database v1 and v2 opens with every row kept; every save rule.
- `test/sync_test.dart`: the Neon request has the same SQL and values as the Kotlin app sent; failures and retries.
- `test/screens_test.dart`: taps through every screen and saves an image of each in `test/goldens/`.
After a wanted screen change: `flutter test --update-goldens`, then look at the images.

## Neon, both ways
Every sync sends what is new on the phone, then reads what is new in Neon (another phone, or after a reinstall).
Rows are only ever added, with a UUID key, so a row the phone already has is skipped and never changed;
an edit or a cancel from another phone arrives as its own row. On the first start of a new phone it reads
Neon before adding the 15 starter products, so the old ones come back instead of copies.
Reading needs `../app/neon_migration_003.sql` run once in Neon (GRANT SELECT). Until then sending still works,
and the debug screen shows "permission denied" for the reads.

## One difference from Kotlin
Kotlin used WorkManager, which could send data while the app was closed.
Here, syncing runs while the app is open (and every 5 minutes): at start, after every save, when the app comes back to the front,
and again after 30 s, 1 min, 2 min, 4 min, then every 5 min when it fails. Nothing is lost; it waits on the phone until the next send.
