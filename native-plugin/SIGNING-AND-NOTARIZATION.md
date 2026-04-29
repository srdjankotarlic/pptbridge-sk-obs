# Signing and Notarization Notes

This build is currently usable for local installs and release sharing, but the v1.0 public macOS release should be signed and notarized.

## What you need

- Apple Developer account
- Developer ID Application certificate
- Developer ID Installer certificate
- Xcode command line tools
- `notarytool` configured with Apple credentials, either as a keychain profile or explicit Apple ID credentials

## High-level flow

1. codesign the plugin bundle
2. build the installer package
3. sign the installer package
4. submit the package to Apple notarization
5. staple the notarization ticket
6. upload the notarized package to GitHub Releases

## Scripted flow

After `./build.sh` succeeds, export the certificate names exactly as they appear in Keychain:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export DEVELOPER_ID_INSTALLER="Developer ID Installer: Your Name (TEAMID)"
```

Recommended notary setup:

```bash
xcrun notarytool store-credentials pptbridge-notary
export NOTARYTOOL_PROFILE="pptbridge-notary"
```

Then run:

```bash
./scripts/sign-and-notarize.sh
```

The script creates:

```text
dist/PPTBridge-SK-for-OBS-Installer-signed.pkg
```

It signs the plugin bundle, rebuilds the installer package, signs the `.pkg`, submits it to Apple notarization, staples the ticket, and runs `spctl -a -t install`.

## Why it matters

- reduces macOS warning friction on other laptops
- looks more professional for hiring and portfolio use
- makes the public release easier for non-technical users

## Recommendation

Do not call the macOS release v1.0 until `spctl` accepts the signed installer and a second Mac can open it without Gatekeeper warnings.
