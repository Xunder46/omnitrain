# iOS TestFlight Release Checklist

> **Who is this for?** You. You've done this before but it's been a few weeks and you don't want to re-learn it.
> **Apple Team ID:** S3976AA7K8 · **Bundle ID:** `dev.sasha.omnitrain`

---

## Before You Start

Make sure you're on `main` (or whatever branch has the code you want to ship), all tests pass, and the device you tested on is someone else's phone — not the simulator.

---

## Step 1 — Increment the version in pubspec.yaml

Open `pubspec.yaml`. Find this line:

```
version: 1.0.0+1
```

The number **after the `+`** is the **build number** — this is what TestFlight uses to distinguish uploads. **It must go up by at least 1 every upload, no exceptions.** If you upload the same build number twice, the second upload will be rejected.

The number **before the `+`** is the **version string** shown to users. Increment this when you have a meaningful set of changes (use semantic versioning: `1.0.1`, `1.1.0`, `2.0.0`).

**For a routine internal TestFlight push:** bump only the build number.
```
version: 1.0.0+2   ← bump the build number
```

**For a release with new features:** bump both.
```
version: 1.1.0+3
```

Commit the change before archiving:
```bash
git add pubspec.yaml
git commit -m "chore: bump version to 1.0.0+2 for TestFlight build 2"
```

> **Why pubspec.yaml?** The iOS `Info.plist` reads `$(FLUTTER_BUILD_NAME)` and `$(FLUTTER_BUILD_NUMBER)`, which Flutter sets from pubspec.yaml at build time. You never need to touch the Xcode version fields manually.

---

## Step 2 — Run the pre-release check

From the repo root:

```bash
bash scripts/pre_release_check.sh
```

This takes about 30 seconds. It checks:
- Build number is higher than the last uploaded build
- pubspec.yaml is committed
- Info.plist still reads from Flutter variables (not hard-coded)
- Bundle ID is consistent across all build configurations
- Development team is set
- No DEBUG=1 macro leaking into Release config

**All checks must pass before you Archive.** Fix any `✗` errors it reports.

---

## Step 3 — Archive in Xcode

1. Open `ios/Runner.xcworkspace` in Xcode (**not** `Runner.xcodeproj`).
2. At the top-left device selector, choose **Any iOS Device (arm64)** — not a simulator, not your plugged-in phone.
3. Menu: **Product → Archive**
4. Wait. The first archive after a `flutter pub get` takes a few minutes. Subsequent ones are faster.
5. When the Organizer window opens, you should see your new archive at the top.

> **If the Archive option is greyed out:** you probably have a simulator selected. Change to "Any iOS Device".

---

## Step 4 — Validate before uploading

In the Organizer window:

1. Select the archive you just created.
2. Click **Validate App**.
3. Choose **Automatically manage signing**.
4. Click through the dialogs. Let it validate.
5. If validation fails: read the error. The most common issues are a duplicate build number (go back to Step 1) or a missing entitlement (rare for TestFlight).

Only proceed to upload after validation succeeds.

---

## Step 5 — Upload to App Store Connect

1. Back in Organizer, click **Distribute App**.
2. Choose **TestFlight & App Store**.
3. Choose **Automatically manage signing**.
4. Click through. Let it upload. This takes 2–10 minutes depending on your connection.
5. When it says "Upload Successful", you're done with Xcode.

---

## Step 6 — Answer the Export Compliance question

**Do not skip this.** After upload, go to [App Store Connect](https://appstoreconnect.apple.com):

1. My Apps → OmniTrain → TestFlight
2. Find your new build (it may say "Processing" for a few minutes — refresh the page).
3. Once processing completes, it will prompt you: **"Missing Compliance"**
4. Click on it and answer the export compliance questions.
   - OmniTrain does **not** use encryption beyond standard HTTPS → answer **No** to custom encryption.
5. After answering, the build status changes to "Ready to Test".

> **This is the #1 reason testers say "I don't see the build in TestFlight."** The build is invisible to testers until export compliance is answered.

---

## Step 7 — Add testers and send notification

1. In App Store Connect → TestFlight → Internal Testing group (or whichever group you use)
2. Click **+** next to Builds and add the new build.
3. Testers will receive an automatic email notification from Apple.

If you want to send a personal heads-up:

---

**Tester notification template:**

> Hey — just pushed a new OmniTrain build to TestFlight (build [BUILD_NUMBER], version [VERSION]).
> You should get an email from Apple shortly. Open the TestFlight app to update.
> Main changes: [2–3 bullet points of what's new or fixed]
> Let me know if anything feels broken. Thanks for testing!

---

## Step 8 — Record the released build number

After a successful upload, update the tracking file so the pre-release check knows what was last shipped:

```bash
echo "2" > docs/releases/.last-released-build    # ← replace 2 with your actual build number
git add docs/releases/.last-released-build
git commit -m "chore: record released build 2"
```

---

## Common First-Time Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Forgot to increment build number | Upload rejected: "The bundle already contains a build with this version number" | Bump `+N` in pubspec.yaml, re-archive |
| Uploaded a debug build | App behaves oddly, crashes in TestFlight, logging is verbose | Make sure you archived with scheme "Runner" and no debug overrides; run pre-release check |
| Skipped export compliance | Testers see "No Builds Available" in TestFlight | Go to App Store Connect, find the build, answer the compliance questions |
| Opened .xcodeproj instead of .xcworkspace | Pods not linked, build fails with missing symbols | Always open `Runner.xcworkspace` |
| Wrong device target selected | Archive option is greyed out | Set destination to "Any iOS Device (arm64)" |

---

## Reference

- **Xcode workspace:** `ios/Runner.xcworkspace`
- **Version source of truth:** `pubspec.yaml` → `version:` field
- **Pre-release check:** `bash scripts/pre_release_check.sh`
- **Last released build tracking:** `docs/releases/.last-released-build`
- **Apple Team ID:** S3976AA7K8
- **Bundle ID:** `dev.sasha.omnitrain`
- **Deployment target:** iOS 13.0
- **Signing:** Automatic (Xcode manages certificates and provisioning profiles)

---

## Android

Android release configuration is not yet set up. This placeholder will be replaced when the iOS TestFlight workflow has been used 2–3 times and the process is stable. When that work begins, create `docs/releases/android-play-store.md` following the same format as this file.
