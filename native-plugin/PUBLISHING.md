# Publishing PPTBridge SK

Author credit:
- Product name: `PPTBridge SK for OBS`
- Creator line: `Created by Srdjan Kotarlic`
- Short credit: `by Srdjan Kotarlic`

Recommended free launch:
1. Publish the source code on GitHub.
2. Attach the release zip and `.pkg` to a GitHub Release.
3. Publish the plugin on the OBS Forums plugin/resources section.

Official links:
- GitHub Releases docs: [Releasing projects on GitHub](https://docs.github.com/en/repositories/releasing-projects-on-github?apiVersion=2022-11-28)
- OBS Forums resources: [OBS Studio Plugins category](https://obsproject.com/forum/resources/?prefix_id=9)
- OBS plugin template reference: [obs-plugintemplate](https://github.com/obsproject/obs-plugintemplate)

## Best Publish Order

1. Prepare release assets locally
2. Create the GitHub repository
3. Push the source code
4. Create the GitHub Release and upload assets
5. Create the OBS Forums resource page
6. Link the GitHub Release from the OBS Forums post

## 1. Prepare Release Assets

Run:

```bash
cd native-plugin
./scripts/make-release.sh
```

Main outputs:

- `release/PPTBridge-SK-for-OBS-v0.1.0-macOS.zip`
- `dist/PPTBridge-SK-for-OBS-Installer.pkg`

## 2. Create The GitHub Repository

Suggested repo name:

- `pptbridge-sk-obs`

Suggested repository description:

- `Native macOS OBS plugin for PowerPoint slide and presenter sources, created by Srdjan Kotarlic.`

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
git tag v0.1.0
git push origin v0.1.0
```

## 4. Create The GitHub Release

In GitHub:

1. Open the repository
2. Click `Releases`
3. Click `Draft a new release`
4. Choose tag `v0.1.0`
5. Title it `PPTBridge SK for OBS v0.1.0`
6. Paste the text from `GITHUB-RELEASE.md`
7. Upload:
   - `PPTBridge-SK-for-OBS-v0.1.0-macOS.zip`
   - `PPTBridge-SK-for-OBS-Installer.pkg`
8. Publish the release

## 5. Create The OBS Forums Resource

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
- press next/previous on a clicker
- show clean slide vs presenter view

Suggested repository:
- Name: `pptbridge-sk-obs`
- Description: `PPTBridge SK for OBS is a native macOS OBS plugin for PowerPoint slide and presenter sources, created by Srdjan Kotarlic.`

Suggested release title:
- `PPTBridge SK for OBS v0.1.0`

Suggested release assets:
- `PPTBridge-SK-for-OBS-v0.1.0-macOS.zip`
- `PPTBridge-SK-for-OBS-Installer.pkg`

Suggested OBS Forums title:
- `PPTBridge SK for OBS`

Suggested short pitch:
- `Native OBS plugin for macOS that adds PowerPoint slide and presenter sources, with clicker-friendly hotkeys and PowerPoint fallback export. Created by Srdjan Kotarlic.`

Release checklist:
1. Run `./scripts/make-release.sh`
2. Test the `.pkg` on a second Mac or clean user account
3. Verify the source picker shows `PPTBridge SK Slide` and `PPTBridge SK Presenter`
4. Verify hotkeys work with `Right Arrow` / `Page Down` and `Left Arrow` / `Page Up`
5. Upload the zip and `.pkg` to GitHub Release
6. Copy the short pitch into the OBS Forums listing

Portfolio angle:
- Keep the plugin free first to maximize adoption and visibility.
- Put `Created by Srdjan Kotarlic` in the README, release page, installer text, and forum post.
- Add 2 screenshots: clean slide output and presenter view with notes.

Important note:
- The package is currently unsigned and not notarized.
- For public distribution outside your own machines, code signing and notarization are the next polish step.
