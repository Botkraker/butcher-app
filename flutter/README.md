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
- `test/sync_test.dart`: the Neon request is byte for byte what the Kotlin app sent; failures and retries.
- `test/screens_test.dart`: taps through every screen and saves an image of each in `test/goldens/`.
After a wanted screen change: `flutter test --update-goldens`, then look at the images.

## One difference from Kotlin
Kotlin used WorkManager, which could send data while the app was closed.
Here, sending runs while the app is open: at start, after every save, when the app comes back to the front,
and again after 30 s, 1 min, 2 min ... when it fails. Nothing is lost; it waits on the phone until the next send.
