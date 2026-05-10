# PPTBridge SK Companion Control

This guide is for running PPTBridge SK from a control surface without relying on keyboard focus.
It is the recommended first Companion workflow before adding a native OSC listener.

## Why This Path

PPTBridge SK v0.3.0 intentionally ignores OBS hotkey callbacks while OBS is not the active app.
That protects the show operator from accidentally changing slides while typing in another window.

For Companion, use OBS WebSocket requests instead of keyboard hotkeys.
The request targets one exact PPTBridge source by name and presses the built-in source property button.

## Requirements

- OBS Studio with the built-in obs-websocket server enabled.
- Bitfocus Companion with an OBS Studio connection.
- A scene containing a `PPTBridge SK Slide` or `PPTBridge SK Presenter` source.

In OBS, enable the server in:

`Tools > WebSocket Server Settings`

Recommended local settings:

- Host: `127.0.0.1`
- Port: `4455`
- Authentication: enabled for real shows

Do not commit or publish your OBS WebSocket password.

## OBS WebSocket Request

Use the obs-websocket request:

`PressInputPropertiesButton`

Request data:

```json
{
  "inputName": "PPTBridge SK Presenter",
  "propertyName": "pptbridge_next_btn"
}
```

Replace `PPTBridge SK Presenter` with the exact OBS source name in your scene.

The request is documented by obs-websocket as a way to press a button in an input's properties.
PPTBridge exposes its slide controls as OBS source property buttons, so Companion can call them directly.
See the official obs-websocket protocol entry:

`https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md#pressinputpropertiesbutton`

## PPTBridge Button Names

| Action | `propertyName` |
| --- | --- |
| Previous slide | `pptbridge_prev_btn` |
| Next slide | `pptbridge_next_btn` |
| First slide | `pptbridge_first_btn` |
| Last slide | `pptbridge_last_btn` |
| Toggle black screen | `pptbridge_black_btn` |
| Reload presentation | `pptbridge_reload_btn` |

## Companion Setup

1. In Companion, add an `OBS Studio` connection.
2. Point it to the OBS WebSocket server, usually `127.0.0.1:4455`.
3. Add a button.
4. Add an action from the OBS connection.
5. Use `Custom Command`.
6. Set `Request Type` to:

```text
PressInputPropertiesButton
```

7. Set `Request Data` for next slide:

```json
{
  "inputName": "PPTBridge SK Presenter",
  "propertyName": "pptbridge_next_btn"
}
```

8. Duplicate the button for previous, first, last, black screen, and reload by changing only `propertyName`.

## Suggested Button Layout

| Button | Request Data |
| --- | --- |
| Previous | `{"inputName":"PPTBridge SK Presenter","propertyName":"pptbridge_prev_btn"}` |
| Next | `{"inputName":"PPTBridge SK Presenter","propertyName":"pptbridge_next_btn"}` |
| First | `{"inputName":"PPTBridge SK Presenter","propertyName":"pptbridge_first_btn"}` |
| Last | `{"inputName":"PPTBridge SK Presenter","propertyName":"pptbridge_last_btn"}` |
| Black | `{"inputName":"PPTBridge SK Presenter","propertyName":"pptbridge_black_btn"}` |
| Reload | `{"inputName":"PPTBridge SK Presenter","propertyName":"pptbridge_reload_btn"}` |

## Multi-Deck Shows

For multiple decks, use clear source names and create one Companion button set per source:

- `PPTBridge - Main Hall`
- `PPTBridge - Breakout`
- `PPTBridge - Backup`

The WebSocket request targets the source named in `inputName`.
It does not depend on OBS keyboard focus and does not use the scene-aware hotkey router.

## Test Checklist

1. Open OBS.
2. Confirm the PPTBridge source changes slides from its source `Properties` buttons.
3. Enable OBS WebSocket.
4. Connect Companion to OBS.
5. Press the Companion `Next` button.
6. Click into another app and type.
7. Confirm typing does not move slides.
8. Press the Companion `Next` button again.
9. Confirm Companion still moves the chosen PPTBridge source.

## Next Native OSC Phase

This WebSocket workflow is the low-risk first step for Companion.
The next native phase can add an OSC listener inside PPTBridge SK, with addresses such as:

- `/pptbridge/next`
- `/pptbridge/previous`
- `/pptbridge/first`
- `/pptbridge/last`
- `/pptbridge/black`
- `/pptbridge/reload`

That should be implemented separately from v0.3.0 presenter customization and tested as its own release scope.

## References

- obs-websocket protocol: `https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md`
- Companion OBS Studio module: `https://github.com/bitfocus/companion-module-obs-studio`
