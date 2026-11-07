# Butcher app (first slice)

Kotlin, Compose, Room, WorkManager. minSdk 24. Arabic, right-to-left.
Slice: Home, Sale with undo, Products, sync worker, debug screen.
Not built yet: Carcass, Closing, stock, waste screens (their tables exist).

## Neon setup
1. Open `neon_schema.sql`. Replace `CHANGE_ME_PLACEHOLDER` with a real password.
2. Run it in the Neon SQL editor.
3. Copy `local.properties.example` to `local.properties`.
4. Set `sdk.dir`, `neon.sql.url` (`https://<host>/sql`) and `neon.connection.string` (role `app_writer`).
`local.properties` is in `.gitignore`. Never commit it.

## Build
The Gradle wrapper jar and `gradlew` scripts are not included (they need a Gradle download).
1. Open this folder in Android Studio. It uses `gradle/wrapper/gradle-wrapper.properties` (Gradle 8.7).
2. Optional, for a terminal build: run `gradle wrapper` once with a local Gradle.
3. Close other apps first (low memory). Build > Build APK(s), or run `./gradlew assembleDebug`.
4. APK path: `app/build/outputs/apk/debug/app-debug.apk`.
For updates, keep the same signing key. A key change forces an uninstall and wipes the data.

## Phone test steps
1. Install the APK on the phone (allow install from unknown sources).
2. Turn on mobile data. Open the app. Tap "اختبار الاتصال", then "إرسال صف تجريبي".
3. Expect `HTTP 200`. In Neon run `SELECT * FROM debug_pings;` as the owner. One row must appear.
4. Add a product. Make a sale. Tap "تراجع" and check the sale is hidden from "آخر عملية".
5. Turn on airplane mode. Save 3 sales. Kill the app. Open it again. The sales must remain.
6. Turn off airplane mode. Wait 1 to 2 minutes. In Neon check `sales` and `voids` rows. "آخر مزامنة" on Home must update.
7. Force a second sync. The row counts must not change.
