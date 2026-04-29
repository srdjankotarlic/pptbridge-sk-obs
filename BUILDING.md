# Building PPTBridge SK for OBS

This is the developer build path for the native OBS plugin.

## Requirements

- macOS 12 or newer
- OBS Studio installed at `/Applications/OBS.app`
- CMake 3.21 or newer
- Apple Command Line Tools or Xcode
- SIMDe headers, usually from Homebrew: `brew install simde`
- OBS source headers at `native-plugin/third_party/obs-studio`

The OBS source tree is used for headers only. It is intentionally ignored by Git.

Verified locally on April 29, 2026:

- macOS 26.4.1
- OBS Studio 32.1.1
- CMake 4.3.1
- SIMDe 0.8.2
- Apple clang 21.0.0
- OBS source headers at commit `e04b883`

To prepare the ignored OBS source header tree in a fresh clone:

```bash
mkdir -p native-plugin/third_party
git clone --depth 1 https://github.com/obsproject/obs-studio.git native-plugin/third_party/obs-studio
```

## Clean Build

From the repo root:

```bash
cd native-plugin
./build.sh
```

The script removes `native-plugin/build`, configures CMake, and builds the plugin bundle at:

```text
native-plugin/build/bundle/pptbridge-obs.plugin
```

## Manual Build

```bash
cd native-plugin
rm -rf build
cmake -S . -B build -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

If full Xcode is installed and selected with `xcode-select`, you can use:

```bash
cmake -S . -B build -G Xcode -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

On machines with only Command Line Tools selected, CMake may list the Xcode generator but fail to create an Xcode project. In that case, use `./build.sh` or the `Unix Makefiles` command above.

## Release Package

After a successful build:

```bash
cd native-plugin
./scripts/make-release.sh
```

Expected outputs:

```text
native-plugin/dist/PPTBridge-SK-for-OBS-Installer.pkg
native-plugin/release/PPTBridge-SK-for-OBS-v0.2.0-macOS.zip
native-plugin/release/pptbridge-obs-macos-arm64.zip
```
