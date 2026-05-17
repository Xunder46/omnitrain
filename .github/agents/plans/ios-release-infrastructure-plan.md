# Release Infrastructure — iOS TestFlight

## Status: Complete (May 2026)

## What Was Set Up

This was the first release infrastructure pass for OmniTrain. The goal was to harden the repo so subsequent TestFlight builds are predictable, without introducing CI/CD or automation tooling (that comes later).

### Version Management

**Single source of truth: `pubspec.yaml` → `version:` field.**

Flutter propagates this at build time:
- `CFBundleShortVersionString` ← `$(FLUTTER_BUILD_NAME)` ← the string before `+` in pubspec `version:`
- `CFBundleVersion` ← `$(FLUTTER_BUILD_NUMBER)` ← the integer after `+` in pubspec `version:`

This was already wired correctly in `ios/Runner/Info.plist` (which uses `$(FLUTTER_BUILD_NAME)` and `$(FLUTTER_BUILD_NUMBER)`). No changes to iOS project files were needed.

**To release:** change only `pubspec.yaml`. The iOS layer reads from it automatically.

### Pre-Release Sanity Check

**Script: `scripts/pre_release_check.sh`**

Run before every Archive. Checks:
1. Build number is greater than last released build (tracked in `docs/releases/.last-released-build`)
2. pubspec.yaml version bump is committed
3. Info.plist still uses Flutter build variables (not hard-coded values)
4. Bundle identifier is consistent across all Runner build configurations
5. Development team (S3976AA7K8) is set
6. VALIDATE_PRODUCT=YES is present in Release config
7. DEBUG=1 macro is only in the Debug config

After every successful upload, update the tracking file:
```bash
echo "<build_number>" > docs/releases/.last-released-build
git add docs/releases/.last-released-build
git commit -m "chore: record released build <build_number>"
```

### Release Checklist

**Docs: `docs/releases/ios-testflight.md`**

Step-by-step checklist covering:
- Version bump procedure
- Pre-release check
- Xcode Archive
- Validation before upload
- Upload to App Store Connect
- Export compliance (the most common first-time blocker)
- Tester notification template
- Post-upload tracking file update

Written for a non-iOS-engineer at 11pm who just wants to ship.

## What Was Not Changed

- No app code was modified.
- No CI/CD, fastlane, or Codemagic configuration was added.
- iOS project signing (`Automatic`, Team ID `S3976AA7K8`) was already correct — no changes.
- Deployment target (`iOS 13.0`) was already set consistently — no changes.
- `debugPrint()` calls in the app are safe in release mode (Flutter no-ops them) — no changes needed.

## iOS Project Config (For Reference)

| Setting | Value |
|---|---|
| Bundle ID | `dev.sasha.omnitrain` |
| Team ID | `S3976AA7K8` |
| Deployment target | iOS 13.0 |
| Signing | Automatic |
| Version source | `pubspec.yaml` |

## Android

Android release configuration is explicitly deferred. No Play Store setup, signing keys, or release build configuration has been created. When that work begins (after iOS TestFlight is shipping reliably), create a corresponding plan and `docs/releases/android-play-store.md`.

## Next Steps for Release Infrastructure (Phase 2)

Once the manual TestFlight flow has been used 2–3 times, consider:
- Automating build number increment with a short script
- fastlane for Archive + upload in one command
- GitHub Actions for automated TestFlight distribution on merge to `main`
