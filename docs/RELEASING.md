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

Generate it once, on a machine you trust:

```bash
keytool -genkey -v -keystore dailyvalo-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias dailyvalo
```

Keep that file and its passwords somewhere safe and backed up. **If it is lost,
no future build can ever upgrade an installed DailyValo.**

Then add four repository secrets under *Settings ▸ Secrets and variables ▸
Actions*:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 dailyvalo-release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | the store password |
| `ANDROID_KEY_ALIAS` | `dailyvalo` |
| `ANDROID_KEY_PASSWORD` | the key password |

The first release signed with the new key still needs a manual uninstall on any
device that has a debug-signed build on it. That happens once.

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
the body. A version mismatch or a failing test stops the release rather than
shipping.

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
