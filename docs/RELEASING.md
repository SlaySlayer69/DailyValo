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

### Setting it up from a phone

One manual step, then a button.

1. Create a **fine-grained personal access token** at
   *GitHub ▸ Settings ▸ Developer settings ▸ Personal access tokens ▸
   Fine-grained tokens*. Give it access to this repository only, and under
   *Repository permissions* set **Secrets: Read and write**.
2. Save it as a repository secret named `GH_SECRETS_TOKEN` under
   *Settings ▸ Secrets and variables ▸ Actions*.
3. *Actions ▸ Generate a signing key ▸ Run workflow.*

The workflow generates the keystore and writes all four signing secrets itself.
Afterwards you can delete `GH_SECRETS_TOKEN` and the token — nothing needs them
again.

**Why a token at all?** A workflow's built-in `GITHUB_TOKEN` cannot write
secrets. Something has to, and one short token pasted once beats pasting a
3,600-character base64 blob by hand on a phone keyboard.

**Why the key is never handed back.** The obvious alternative — upload the
keystore as an artifact and paste the values yourself — does not work here.
Artifacts can be downloaded by anyone who can read the repository, and this
repository is public, so that would publish the private key. Anyone holding it
could sign an APK that Android accepts as an update to yours. The key goes from
the runner into secret storage and nowhere else.

The consequence: **the secrets are the only copy.** That is survivable — if they
are lost, generate a new key and reinstall once — but there is no off-site
backup unless you make one, which means generating the key yourself.

### Generating it on a computer instead

Do this if you want a backup you control.

```bash
keytool -genkeypair -v -keystore dailyvalo-release.jks -storetype PKCS12 \
  -keyalg RSA -keysize 2048 -validity 10950 -alias dailyvalo
base64 -w0 dailyvalo-release.jks   # the value for ANDROID_KEYSTORE_BASE64
```

Then add four secrets by hand — `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`dailyvalo`) and
`ANDROID_KEY_PASSWORD` — and keep the `.jks` somewhere safe. **If it is lost, no
future build can ever update an installed DailyValo.**

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
