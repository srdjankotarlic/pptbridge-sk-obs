## PPTBridge SK v0.5.13 for Apple Silicon

PPTBridge SK adds native PowerPoint and PDF Slide and Presenter sources to OBS Studio.

- Navigation and Black Screen now keep their state when PowerPoint notes and media finish loading.
- With Stage Manager enabled, PPTBridge shows the current slide while PowerPoint is in the background. Turn Stage Manager off for background live video and animations.
- The macOS installer checks its bundle before replacement and restores the previous copy if activation fails.
- PDF decks open directly in both source types without Microsoft PowerPoint.

**Install** by downloading and extracting the Apple Silicon ZIP, quitting OBS, and opening `1-Install-PPTBridge-SK.command`. The ZIP includes the Companion OSC template and a setup guide.

Use OBS Studio 32.2.2 or newer on macOS 26. On macOS 27, use OBS Studio 33.0.1 or newer. The Apple Silicon release was tested with OBS 33.0.1 and desktop PowerPoint, including embedded video and audio. See the [validation notes](https://github.com/srdjankotarlic/pptbridge-sk-obs/blob/v0.5.13/qa/V0513-PLATFORM-QA.md) for the tested configurations.

For Windows x64, the production download is [v0.5.10](https://github.com/srdjankotarlic/pptbridge-sk-obs/releases/tag/v0.5.10).
