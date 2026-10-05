# ClaudeBar for Android (minimal, Java, zero dependencies)

Port of chaudhryfaisal/claude-usage-status-bar. Shows your remaining Claude quota
(session 5h) as a number in the status bar via an ongoing notification; pull down
the shade to see session / weekly / Opus remaining and reset times.

## Build & run
1. Open this folder in Android Studio (Koala+; JDK 17) and let Gradle sync.
   (CLI: `gradle wrapper && ./gradlew installDebug`)
2. Run on a device/emulator (API 26+). Allow notifications.
3. Tap **Connect Claude Account** -> approve in browser -> copy the code shown -> paste -> **Submit code**.

Refreshes on app open and every ~15 min (Android's minimum for periodic jobs).

## Notes
- Same read-only `user:profile` OAuth scope + PKCE(S256) as the macOS app; endpoints are undocumented and may change.
- Token lives in app-private SharedPreferences. For hardening, wrap it with Android Keystore.
- On Android 14+ users can swipe away ongoing notifications; the next refresh re-posts it.
- Some OEMs hide notification icons in the status bar or aggressively kill background jobs; exempt the app from battery optimization if updates stall.
