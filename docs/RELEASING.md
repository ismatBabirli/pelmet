# Releasing Pelmet

Releases are automated. Pushing a `vX.Y.Z` tag triggers
[`.github/workflows/release.yml`](../.github/workflows/release.yml), which:

1. builds `Pelmet.app` (Release, via XcodeGen + xcodebuild),
2. code-signs it with your **Developer ID Application** identity (hardened runtime),
3. **notarizes** the app and the DMG with Apple and staples the tickets,
4. packages `Pelmet-<version>.dmg` + `Pelmet-<version>.zip`,
5. creates the GitHub Release with generated notes + checksums, and
6. bumps the cask in the `ismatBabirli/homebrew-pelmet` tap.

The **git tag is the source of truth** for the released version — the workflow
patches `project.yml`'s `CFBundleShortVersionString` from it, so you don't edit
version numbers by hand.

---

## One-time setup

You need a **paid Apple Developer Program** membership. (You already have Apple
Development / Apple Distribution certs, but neither can notarize — only a
*Developer ID Application* certificate can.)

### 1. Developer ID Application certificate → `.p12`

1. Xcode → Settings → Accounts → your team → **Manage Certificates** → **+** →
   **Developer ID Application**. (Or create it at
   <https://developer.apple.com/account/resources/certificates>.)
2. In **Keychain Access**, find *"Developer ID Application: Ismat Babirli (…)"*,
   right-click → **Export** → save as `DeveloperID.p12`, set an export password.

### 2. App Store Connect API key → `.p8` (for notarization)

1. <https://appstoreconnect.apple.com> → **Users and Access** → **Integrations**
   → **App Store Connect API** → **+**. Give it the **Developer** role.
2. Download `AuthKey_XXXXXXXXXX.p8` (**once only**). Note the **Key ID** (the
   `XXXXXXXXXX`) and the **Issuer ID** (UUID shown on that page).

### 3. Tap token (for the automatic cask bump)

Create a **fine-grained PAT** (<https://github.com/settings/tokens>) with
**Contents: Read and write** scoped to `ismatBabirli/homebrew-pelmet`.

### 4. Add the GitHub secrets

Run from the repo (macOS `base64` shown):

```bash
R=ismatBabirli/pelmet
base64 -i DeveloperID.p12            | gh secret set DEVELOPER_ID_CERT_P12_BASE64 --repo "$R"
echo -n 'YOUR_P12_EXPORT_PASSWORD'   | gh secret set DEVELOPER_ID_CERT_PASSWORD  --repo "$R"
base64 -i AuthKey_XXXXXXXXXX.p8      | gh secret set NOTARY_KEY_P8_BASE64         --repo "$R"
echo -n 'XXXXXXXXXX'                 | gh secret set NOTARY_KEY_ID                --repo "$R"
echo -n 'YOUR-ISSUER-UUID'           | gh secret set NOTARY_ISSUER_ID            --repo "$R"
echo -n 'ghp_yourTapToken'           | gh secret set HOMEBREW_TAP_TOKEN          --repo "$R"
```

| Secret | What |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | base64 of the exported `.p12` |
| `DEVELOPER_ID_CERT_PASSWORD` | the `.p12` export password |
| `NOTARY_KEY_P8_BASE64` | base64 of the App Store Connect API `.p8` |
| `NOTARY_KEY_ID` | the API key ID |
| `NOTARY_ISSUER_ID` | the API issuer UUID |
| `HOMEBREW_TAP_TOKEN` | PAT with write access to the tap repo |

### 5. Bootstrap the Homebrew tap (once)

```bash
./scripts/bootstrap-tap.sh
```

Creates `ismatBabirli/homebrew-pelmet` and seeds `Casks/pelmet.rb`. The release
workflow keeps its `version`/`sha256` current from then on.

---

## Cutting a release

```bash
# 1. Update the changelog (move Unreleased → the new version).
$EDITOR CHANGELOG.md

# 2. Tag and push. The workflow does the rest.
git tag v0.1.0
git push origin v0.1.0
```

Watch the run under the repo's **Actions** tab. When it's green you'll have a
GitHub Release with the `.dmg`/`.zip`, and `brew upgrade --cask pelmet` will pick
up the new version.

## Testing the build without secrets

Use the manual **dry run** — it builds the app and uploads it as a workflow
artifact, skipping every signing/notarizing/publishing step:

Actions → **Release** → **Run workflow** → set a version, leave **dry_run** on.

## Verifying a real release locally

```bash
spctl -a -vvv -t install /Applications/Pelmet.app   # → accepted, source=Notarized Developer ID
xcrun stapler validate /Applications/Pelmet.app
```
