# Sparkle auto-update — setup

Orchard uses [Sparkle](https://sparkle-project.org) for in-app auto-updates. The
code and CI are already wired up; this document covers the **one-time setup**
you need to do on your machine and in the repo settings before the first
Sparkle-enabled release.

## Overview of how it works

- The app embeds Sparkle (added as a Swift Package) and reads `SUFeedURL` and
  `SUPublicEDKey` from `Orchard/Info.plist`.
- On launch it asks the user once whether to check automatically, then checks
  the **appcast** in the background.
- The appcast is published to **GitHub Pages** and served from the repo's
  custom domain at `https://orchard.andon.dev/appcast.xml`.
- On each tagged release, CI signs the DMG with an EdDSA key and regenerates the
  appcast (see `.github/workflows/release.yml`).

Each app gets its **own subdomain** (`<app>.andon.dev`) so appcasts never
collide — the release workflow's `cname:` keeps orchard's domain pinned.

## One-time setup

### 1. Resolve the Swift Package

Open `Orchard.xcodeproj` in Xcode. It will resolve the new **Sparkle** package
(`https://github.com/sparkle-project/Sparkle`, 2.9.x) automatically. Build once
to confirm it links.

### 2. Generate the EdDSA signing keys

Download the Sparkle tools (matching the version in `release.yml`) and generate
a key pair:

```bash
curl -sL -o sparkle.tar.xz \
  https://github.com/sparkle-project/Sparkle/releases/download/2.9.4/Sparkle-2.9.4.tar.xz
tar -xf sparkle.tar.xz
./bin/generate_keys
```

This stores the **private** key in your login Keychain and prints your
**public** key (a base64 string).

### 3. Add the public key to Info.plist

Copy the printed public key into `Orchard/Info.plist`, replacing the placeholder:

```xml
<key>SUPublicEDKey</key>
<string>PASTE_YOUR_PUBLIC_KEY_HERE</string>
```

> ⚠️ Until this placeholder is replaced with the real key, the app builds and
> runs but update signature verification will fail.

### 4. Add the private key as a CI secret

Export the private key and add it as a repository secret named
**`SPARKLE_PRIVATE_KEY`** (Settings ▸ Secrets and variables ▸ Actions):

```bash
./bin/generate_keys -x sparkle_private_key.txt   # writes the private key to a file
# copy the file contents into the SPARKLE_PRIVATE_KEY secret, then delete it:
rm sparkle_private_key.txt
```

Keep this key safe and backed up — if you lose it, existing users can't be
offered signed updates and you'd have to ship a new public key via a manual
update.

### 5. Enable GitHub Pages + custom domain

The `gh-pages` branch is created automatically by the release workflow's "Deploy
appcast to GitHub Pages" step on the first signed release. Then:

1. **DNS** (Cloudflare, on `andon.dev`): add `CNAME  orchard → andrew-waters.github.io`
   with **Proxy status = DNS only (grey cloud)**. The grey cloud is essential —
   if Cloudflare proxies the record, GitHub can't provision an HTTPS certificate.
2. **Settings ▸ Pages**: source = **Deploy from a branch → `gh-pages` / (root)**,
   and set **Custom domain** to `orchard.andon.dev`. (This overrides the domain
   inherited from the user site.)
3. Once the certificate provisions, tick **Enforce HTTPS** — Sparkle requires an
   HTTPS feed.

> Adding a future app? Give it its own subdomain (e.g. `newapp.andon.dev`) the
> same way; don't share one domain across apps.

## Cutting the first Sparkle release

1. Complete steps 1–5 above.
2. Bump the version and tag as usual (`./scripts/release.sh <version>`).
3. CI builds, signs, notarizes, creates the GitHub Release, and publishes the
   appcast to Pages.
4. Verify `https://orchard.andon.dev/appcast.xml` loads over HTTPS and the
   `enclosure` URL, `sparkle:edSignature`, and `sparkle:version` look right.

> **Bootstrap note:** users on the current (pre-Sparkle) builds won't
> auto-update *to* the first Sparkle release — they upgrade once via
> `brew upgrade --cask orchard` or a manual download. Every release after that
> updates automatically.

## Notes & limitations

- **CFBundleVersion** is set in CI to `github.run_number` (an always-increasing
  integer), which is what Sparkle compares. The appcast's `sparkle:version` is
  set to the same value.
- **`sparkle:minimumSystemVersion`** is set to `26.0` in the workflow — keep it
  in sync with the README's Requirements if the floor changes.
- The appcast currently contains a **single item** (the latest release), which
  is all Sparkle needs to detect an update. If you later want a full version
  history in the feed, switch the workflow to Sparkle's `generate_appcast` tool.
- **Notarization of Sparkle's helpers:** Sparkle embeds XPC services and an
  updater helper that must be signed with the hardened runtime and notarized.
  The archive/export in `release.yml` signs nested code, but verify the first
  signed build passes notarization (it's the classic Sparkle CI gotcha).
