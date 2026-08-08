# Releasing DailyValo

Releases are built and published by GitHub Actions, so the same two clicks work
from a laptop or from a phone. Nothing is built on your own machine.

---

## One-time setup: the signing key

**Do this before the first release.** Android identifies an app by the key it is
signed with. Two builds signed with different keys are different apps as far as
the installer is concerned, so an APK signed by a CI runner cannot upgrade one
signed on a laptop — the install just fails, and the only way through is to
uninstall, which takes the wishlist and cached collection with it.

Until a key is configured, builds fall back to the per-machine debug key, and
every machine produces a mutually incompatible APK. One real key, held by CI,
fixes that permanently.

A build with no key configured falls back to a debug key, and on a CI runner
that key is generated fresh for every job — so two debug-signed releases cannot
update *each other* either. That is why the Release workflow refuses to publish
one unless the run explicitly ticks **Publish a test build**.

### Generating it from a phone

*Actions ▸ Generate a signing key ▸ Run workflow.* It creates the keystore and
uploads it as a private artifact — the key is never printed to the log, because
anyone able to read a workflow log could otherwise sign an APK that Android
would accept as an update to yours.

Download the **signing-key** artifact, then add four repository secrets under
*Settings ▸ Secrets and variables ▸ Actions*, pasting the contents of the
matching file:

| Secret | File in the artifact |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `ANDROID_KEYSTORE_BASE64.txt` |
| `ANDROID_KEYSTORE_PASSWORD` | `ANDROID_KEYSTORE_PASSWORD.txt` |
| `ANDROID_KEY_ALIAS` | `ANDROID_KEY_ALIAS.txt` |
| `ANDROID_KEY_PASSWORD` | `ANDROID_KEY_PASSWORD.txt` |

**Keep `dailyvalo-release.jks` somewhere safe and backed up.** If it is lost, no
future build can ever update an installed DailyValo — every user has to
uninstall and lose their wishlist. The artifact expires after seven days.

### Generating it on a computer instead

```bash
keytool -genkeypair -v -keystore dailyvalo-release.jks -storetype PKCS12 \
  -keyalg RSA -keysize 2048 -validity 10950 -alias dailyvalo
base64 -w0 dailyvalo-release.jks   # the value for ANDROID_KEYSTORE_BASE64
```

Then add the same four secrets.

### After the switch

The first release signed with the new key still needs a one-time uninstall on
any device carrying a debug-signed build. After that, updates work normally and
the warning disappears from the release notes by itself.

### Building signed APKs locally

Optional. Create `android/key.properties` — it is gitignored:

```properties
storeFile=/absolute/path/to/dailyvalo-release.jks
storePassword=…
keyAlias=dailyvalo
keyPassword=…
```

Without it, local release builds keep working and use the debug key.

---

## Cutting a release

1. Bump `version:` in `pubspec.yaml` (e.g. `2.2.0+11`).
2. Add a `## v2.2.0` section at the top of `CHANGELOG.md`. That section becomes
   the release description, so write it for whoever is downloading the APK.
3. Merge that to `main`.
4. Publish, either way:

**From a PC**

```bash
git tag -a v2.2.0 -m "DailyValo v2.2.0"
git push origin v2.2.0
```

**From a phone** — GitHub mobile app or the site: *Actions ▸ Release ▸ Run
workflow*, enter `v2.2.0`. **The tag does not need to exist**; the workflow cuts
it from the current default branch. That is the whole point of this path — there
is nothing to do first on a machine with git on it.

Either path runs the same job: it checks the version against `pubspec.yaml`,
tags the commit if it is not tagged already, runs `flutter analyze` and the
tests, builds the three APKs, and publishes them with the changelog section as
the body. A version mismatch, a failing test, or a missing signing key stops the
release rather than shipping.

Ticking **Publish a test build** allows a release with no signing key. Use it
for something you only want to try on your own phone — the resulting APK cannot
update any other install, and its release notes say so.

The version check runs *before* the tag is created, so a mistyped version fails
without leaving a stray tag behind — retrying after fixing `pubspec.yaml` is
just pressing the button again.

---

## Backfilling the old versions

*Actions ▸ Backfill releases ▸ Run workflow.*

It reads `tool/versions.tsv`, creates any missing tags at the recorded commits,
and opens a release per version using that version's changelog section. Existing
tags and releases are left alone, so it is safe to re-run.

The **Rebuild each old version** switch is off by default, and should usually
stay off. Old tags do not reliably build with a current toolchain, and a rebuilt
old APK is debug-signed — it cannot be installed over a real release, so it is
an archive artifact rather than something to hand to anyone. Turn it on only if
you actually want the binaries on record; failures are reported per version and
do not stop the rest.

---

## Adding a version to the map

`tool/versions.tsv` is version + commit, tab-separated:

```
v2.2.0	<full commit sha>
```

Only the backfill workflow reads it. Normal releases work off the tag you push
and never touch this file.
