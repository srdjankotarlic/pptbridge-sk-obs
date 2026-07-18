# PPTBridge SK Companion Control

This guide is for running PPTBridge SK from a control surface without relying on keyboard focus.
The safest production path is OBS WebSocket through Companion.
PPTBridge SK also includes an experimental local OSC listener for direct control.

## Why This Path

Since v0.3.0, PPTBridge SK intentionally ignores OBS hotkey callbacks while OBS is not the active app.
That protects the show operator from accidentally changing slides while typing in another window.

For Companion, use OBS WebSocket requests instead of keyboard hotkeys.
The request targets one exact PPTBridge source by name and presses the built-in source property button.

For direct OSC, enable PPTBridge's local listener from the OBS `Tools` menu.
It listens only on `127.0.0.1`, so it is intended for a control app running on the same machine.

For a physical Logitech Spotlight or presenter clicker, use `Tools > PPTBridge
SK: Spotlight/Clicker Capture On/Off` instead of Companion. It captures common
presenter keys globally, routes them to the current OBS program scene, and
suppresses those captured key presses from the focused app. Built-in clicker
keys are `PageDown` for next and `PageUp` for previous. Normal left/right
arrows stay free for OBS controls and other apps. Custom PPTBridge hotkeys are
captured too if you bind them in OBS Settings, except plain typing/navigation
keys that should remain available to the operator.

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
| Toggle current cue checked | `pptbridge_cue_toggle_current_btn` |
| Toggle next cue checked | `pptbridge_cue_toggle_next_btn` |
| Clear checked cues | `pptbridge_cue_clear_checks_btn` |
| Send OSC status now | `pptbridge_send_osc_status_btn` |

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

## Companion OSC Starter Template

A small Generic OSC starter template lives at:

`native-plugin/companion/PPTBridge-SK-Companion-OSC-Template.json`

Use it as a reference when building a Companion page. It includes the common
control buttons and the status feedback addresses. Companion versions differ in
how they import/export button pages, so treat the file as a clean setup map:
create a `Generic OSC` connection to `127.0.0.1:57130`, then copy the listed
OSC paths into your buttons.

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

## Native OSC Control

PPTBridge SK can also listen for local OSC messages without going through keyboard hotkeys.

In OBS, use:

`Tools > PPTBridge SK: Local OSC Control On/Off`

The enabled/disabled state and port are stored in OBS app configuration, not in a scene collection.

Default listener:

- Host: `127.0.0.1`
- Port: `57130`
- Protocol: UDP OSC

Supported OSC addresses:

| Action | OSC address |
| --- | --- |
| Previous slide | `/pptbridge/previous` |
| Previous slide alias | `/pptbridge/prev` |
| Next slide | `/pptbridge/next` |
| First slide | `/pptbridge/first` |
| Last slide | `/pptbridge/last` |
| Toggle black screen | `/pptbridge/black` |
| Toggle black screen alias | `/pptbridge/blank` |
| Reload presentation | `/pptbridge/reload` |

The OSC listener routes commands to the PPTBridge source in the current OBS program scene.
If no PPTBridge source is in Program, it falls back to the last active PPTBridge document.
This matches the stage-friendly hotkey routing, but it does not require OBS to be the focused app.
For multiple live PowerPoint decks, keep one deck per OBS scene. PPTBridge locks each open slideshow to the exact selected deck path (or its fallback copy), and OSC follows the current Program scene.
Spotlight/Clicker Capture uses the same current Program scene routing for physical presenter clickers.

Example terminal test after enabling OSC in OBS:

```bash
native-plugin/scripts/send-osc.sh /pptbridge/next
```

Companion can use a generic OSC action to send the same address to `127.0.0.1:57130`.

## OSC Status Feedback

PPTBridge SK can also send lightweight local OSC status feedback for Companion, TouchDesigner, QLab, or another show-control tool.

In the PPTBridge source `Properties`, open `Show Control (Operator Mode)` and enable:

- `Send OSC Status Feedback`
- `OSC Status Host/IP`, usually `127.0.0.1`
- `OSC Status Port`, default `57131`

Feedback is sent when the deck state changes and once per timer second while enabled.
Use `Send OSC Status Now` to test the output immediately.

Status addresses:

| Status | OSC address | Type |
| --- | --- | --- |
| Current slide number | `/pptbridge/status/current` | integer |
| Total slides | `/pptbridge/status/total` | integer |
| Current slide title | `/pptbridge/status/title` | string |
| Next slide title | `/pptbridge/status/next_title` | string |
| Deck file name | `/pptbridge/status/deck_name` | string |
| Deck file path | `/pptbridge/status/deck_path` | string |
| OBS source name | `/pptbridge/status/source_name` | string |
| Loading state | `/pptbridge/status/loading` | integer, `0` or `1` |
| Loaded state | `/pptbridge/status/loaded` | integer, `0` or `1` |
| Last issue/error text | `/pptbridge/status/error` | string |
| Timer seconds | `/pptbridge/status/timer` | integer |
| Live PowerPoint ready | `/pptbridge/status/live` | integer, `0` or `1` |
| Black screen state | `/pptbridge/status/black` | integer, `0` or `1` |
| Current cue checked | `/pptbridge/status/cue_current_checked` | integer, `0` or `1` |
| Next cue checked | `/pptbridge/status/cue_next_checked` | integer, `0` or `1` |
| Checked cue count | `/pptbridge/status/cue_checked_count` | integer |

`deck_path` is intended for trusted local show-control systems. If you stream or
log OSC feedback publicly, prefer `deck_name` and `source_name`.

For cue tracking, use the source property buttons directly through OBS WebSocket:

```json
{
  "inputName": "PPTBridge SK Presenter",
  "propertyName": "pptbridge_cue_toggle_current_btn"
}
```

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
10. Enable OSC status feedback and confirm your receiver gets `/pptbridge/status/current`.

## Next OSC Phase

The current native OSC listener is intentionally small and local-only.
The next OSC phase can add:

- configurable port and bind address
- richer deck selection for multi-room shows
- packaged Companion button templates

## References

- obs-websocket protocol: `https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md`
- Companion OBS Studio module: `https://github.com/bitfocus/companion-module-obs-studio`
