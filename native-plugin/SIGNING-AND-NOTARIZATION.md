# Signing and Notarization Notes

This build is currently usable for local installs and release sharing, but for a polished public macOS release you should eventually sign and notarize it.

## What you need

- Apple Developer account
- Developer ID Application certificate
- Xcode command line tools
- `notarytool` configured with Apple credentials

## High-level flow

1. codesign the plugin bundle
2. build the installer package
3. sign the installer package
4. submit the package to Apple notarization
5. staple the notarization ticket
6. upload the notarized package to GitHub Releases

## Why it matters

- reduces macOS warning friction on other laptops
- looks more professional for hiring and portfolio use
- makes the public release easier for non-technical users

## Recommendation

Launch the first public version as free and unsigned if needed, then add signing/notarization as the next polish milestone.
