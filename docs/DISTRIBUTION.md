# GitHub releases and Obtainium

The public repository is https://github.com/ER404R/bankroll-tracker.
Every successful push to `main` runs analysis and unit/widget tests, builds a
signed ARM64 release APK and publishes a GitHub release. Pull requests run
checks without signing secrets or publishing. These checks do not replace
emulator workflow validation or the owner's phone review.

## One-time setup before the first push

Authenticate the GitHub CLI as a repository administrator (`gh auth login` if
needed), then run from the project root:

```sh
python3 scripts/setup_release.py
```

The script creates a dedicated permanent RSA signing key under
`.release-private/`, then uploads `KEY_JKS`, `ANDROID_STORE_PASSWORD`,
`ANDROID_KEY_PASSWORD` and `ANDROID_KEY_ALIAS` as GitHub Actions secrets.
Existing local signing material is reused. Secret values are not printed.
Back up the entire `.release-private/` directory securely; it contains both the
key and its password. Never commit it. Losing the key prevents signing updates
for existing installations. Do not regenerate the key after distribution.

Review and push the source normally:

```sh
git add .
git diff --cached --stat
git commit -m "Set up Bankroll Tracker Android releases"
git push -u origin main
```

Private `SPEC.md`, `AGENTS.md`, reference captures, validation documents and
signing material are ignored, retained locally and must not be force-added.
The Gradle wrapper scripts/JAR are included so CI can build from a fresh checkout.
Check the **Android Release** workflow in GitHub Actions after pushing.

## Install with Obtainium

Add `https://github.com/ER404R/bankroll-tracker` in Obtainium after the first
successful release. If configuring an APK filename filter, use
`^bankroll-tracker-arm64\.apk$`. Keep normal version detection enabled;
release tags and APK version names match. Releases are ordinary GitHub releases
so prerelease inclusion is not required, but they are explicitly labeled
*development releases* until version 1.0 is actually complete.
Allow Android to install apps from Obtainium when prompted. Future updates are
installed over the existing release app. The app itself stays offline.

The APK targets ARM64 phones, including Nothing Phone (3a) Pro. Emulators can
continue using local debug builds. The package ID stays `de.feltledger.felt_ledger`.
A previous debug-signed installation cannot be updated with the new release key;
do not uninstall a copy holding valuable data before a supported backup/migration
path is available. Import/export remains the final 1.0 milestone.

## Version and signing policy

CI uses pinned Flutter 3.47.8, Java 17, and Android build tools 36. Version codes
are `github.run_number * 100 + github.run_attempt`; version names append
`-build.CODE` to the version in `pubspec.yaml`. Do not delete/rename the workflow
and reset its counter. Do not rerun old runs after newer releases; the publication
step rejects older/equal versions. Push a fresh commit instead. Keep the package
ID and signing key stable. Release builds fail without signing credentials;
local debug builds do not need them.

CI checks that native libraries are ARM64-only, rejects private-reference paths
in the APK, verifies the APK signature, and publishes SHA256SUMS with the APK.
Do not manually publish newer version codes outside this counter without first
updating the versioning policy. Missing secrets, failed checks or failed builds
prevent publication.

## Setup validation status

Workflow structure, setup-script syntax, privacy exclusions, and synthetic APK
validation can be checked locally. The first actual GitHub run must still verify
hosted SDK availability, Gradle release signing and publication. This session
could not reach the GitHub API, and the installed Flutter SDK cache is read-only;
no first release or signed APK has been claimed as successful.
