# Publishing PPTBridge SK

Author credit:
- Product name: `PPTBridge SK for OBS`
- Creator line: `Created by Srdjan Kotarlic`
- Short credit: `by Srdjan Kotarlic`

Recommended free launch:
1. Publish the source code on GitHub.
2. Attach one clear Apple Silicon release ZIP to a GitHub Release.
3. Publish the plugin on the OBS Forums / obsproject.com resources section.
4. Treat LinkedIn as a secondary announcement channel, not the main distribution path.

Official links:
- GitHub Releases docs: [Releasing projects on GitHub](https://docs.github.com/en/repositories/releasing-projects-on-github?apiVersion=2022-11-28)
- OBS Forums resources: [OBS Studio Plugins category](https://obsproject.com/forum/plugins/)
- OBS resources directory: [Resources](https://obsproject.com/forum/resources/)
- OBS plugin template reference: [obs-plugintemplate](https://github.com/obsproject/obs-plugintemplate)

## Best Publish Order

1. Prepare release assets locally
2. Create the GitHub repository
3. Push the source code
4. Create the GitHub Release and upload only the canonical ZIP plus checksum
5. Prepare signing/notarization for the next trust-focused package
6. Create the OBS Forums / obsproject.com resource page
7. Link the GitHub Release from the OBS resource page

## 1. Prepare Release Assets

Run:

```bash
cd native-plugin
./scripts/make-release.sh
```

Main outputs:

- `release/pptbridge-obs-macos-apple-silicon.zip`
- `release/pptbridge-obs-macos-apple-silicon.zip.sha256`
- `dist/PPTBridge-SK-for-OBS-Installer.pkg`

## 2. Create The GitHub Repository

Suggested repo name:

- `pptbridge-sk-obs`

Suggested repository description:

- `PowerPoint/PDF slide and presenter sources for OBS on macOS. Apple Silicon and Intel builds.`

Suggested visibility:

- start as `Public`

## 3. Push The Code

Typical flow:

```bash
git init
git add .
git commit -m "Initial public release of PPTBridge SK for OBS"
git branch -M main
git remote add origin <your-github-repo-url>
git push -u origin main
git tag v0.4.7
git push origin v0.4.7
```

## 4. Create The GitHub Release

In GitHub:

1. Open the repository
2. Click `Releases`
3. Click `Draft a new release`
4. Choose tag `v0.4.7`
5. Title it `PPTBridge SK for OBS v0.4.7`
6. Paste the text from `GITHUB-RELEASE.md`
7. Upload:
   - `pptbridge-obs-macos-apple-silicon.zip`
   - `pptbridge-obs-macos-apple-silicon.zip.sha256`
8. Publish the release

Do not upload a second, longer-named duplicate ZIP for the same build. One stable download path is easier for OBS users and keeps download metrics readable.

## 5. Signing / Notarization Priority

Before pushing hard outside GitHub, make signing/notarization the next trust item:

1. Use `SIGNING-AND-NOTARIZATION.md` as the working checklist.
2. Produce a signed/notarized `.pkg` when Apple Developer credentials are ready.
3. Keep the ZIP available for technical users, but make the signed installer the recommended public path once it exists.
4. Use OBS Forums/resource traffic as the main audience signal after the signed installer is available.

## 6. Create The OBS Forums Resource

In OBS Forums:

1. Open the `OBS Studio Plugins` resources category
2. Create a new resource
3. Use title `PPTBridge SK for OBS`
4. Paste the text from `OBS-FORUM-POST.md`
5. Add screenshots
6. Link the GitHub Release page as the download page if needed
7. Publish the resource

## 6. Recommended Screenshots

Take these 2 screenshots:

1. `PPTBridge SK Slide` source showing a clean slide in OBS
2. `PPTBridge SK Presenter` source showing notes and next slide preview

If possible, also record a short 20-30 second demo:

- load `.pptx`
- add both sources
- press next/previous on a clicker with Spotlight/Clicker Capture enabled while another app is focused
- show clean slide vs presenter view

Suggested repository:
- Name: `pptbridge-sk-obs`
- Description: `PowerPoint/PDF slide and presenter sources for OBS on macOS. Apple Silicon and Intel builds.`

Suggested release title:
- `PPTBridge SK for OBS v0.4.7`

Suggested release assets:
- `pptbridge-obs-macos-apple-silicon.zip`
- `pptbridge-obs-macos-apple-silicon.zip.sha256`

Suggested OBS Forums title:
- `PPTBridge SK for OBS`

Suggested short pitch:
- `Native macOS OBS plugin that adds live PowerPoint/PDF slide and presenter sources, safe OBS hotkeys, Companion/OSC control, and manual PowerPoint startup for conference workflows. Created by Srdjan Kotarlic.`

Release checklist:
1. Run `./scripts/make-release.sh`
2. Build the Apple Silicon ZIP
3. Verify the source picker shows `PPTBridge SK Slide` and `PPTBridge SK Presenter`
4. Verify default/manual PowerPoint startup, optional auto-start, close-on-quit, OBS-focused hotkeys, and Spotlight/Clicker Capture
5. Verify local OSC or Companion can send `/pptbridge/next`
6. Upload only `pptbridge-obs-macos-apple-silicon.zip` and its `.sha256` to GitHub Release
7. Copy the short pitch into the OBS Forums / obsproject.com resource listing

Portfolio angle:
- Keep the plugin free first to maximize adoption and visibility.
- Put `Created by Srdjan Kotarlic` in the README, release page, installer text, and forum post.
- Add 2 screenshots: clean slide output and presenter view with notes.

Important note:
- The package is currently unsigned and not notarized.
- For public distribution outside your own machines, code signing and notarization are the next trust step, not distant v1.0 polish.
