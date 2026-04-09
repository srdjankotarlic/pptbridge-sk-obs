# PPTBridge SK Pro Audio Mode for macOS

This guide is for the case where you want PowerPoint audio to be controlled by OBS, not just heard locally from macOS or PowerPoint.

## Why this guide exists

In `True Live PowerPoint Mode`, PPTBridge SK lets OBS capture the PowerPoint slideshow and can also bring PowerPoint audio into OBS for recording and streaming.

However, on macOS, PowerPoint can still play its own local output directly to your Mac audio device. That means:

- OBS can receive the audio
- but your local speakers may still hear PowerPoint directly
- so muting or lowering the OBS fader may not fully mute what you hear in the room

If you want full OBS-controlled local monitoring, the clean fix is to route PowerPoint audio through a virtual audio device first, then let OBS handle monitoring.

## Best options

### Option 1: BlackHole

Best if you want a free solution.

- Cost: free
- Control: good
- Difficulty: medium
- Best for: single-show laptop, budget setup, testing

Official links:

- BlackHole download: https://existential.audio/blackhole/
- BlackHole support: https://existential.audio/blackhole/support/

### Option 2: Loopback

Best if you want the cleanest pro workflow.

- Cost: paid
- Control: excellent
- Difficulty: easier to manage than BlackHole once installed
- Best for: conferences, client work, repeatable live production

Official links:

- Loopback: https://www.rogueamoeba.com/loopback/
- Loopback manual: https://www.rogueamoeba.com/support/manuals/loopback/
- Loopback permissions: https://www.rogueamoeba.com/support/manuals/loopback/?page=permissions

## Recommended choice

If you want the best professional setup, use Loopback.

If you want the best free setup, use BlackHole 2ch.

## BlackHole setup

This setup makes OBS the place where you control and hear PowerPoint audio.

### 1. Install BlackHole 2ch

Use the official installer and choose `BlackHole 2ch` unless you already know you need more channels.

### 2. Set macOS output to BlackHole

On your Mac:

1. Open `System Settings > Sound`
2. Under `Output`, choose `BlackHole 2ch`

Important:

- after this, PowerPoint audio will no longer go straight to your speakers
- it will go into BlackHole instead

### 3. Tell OBS where to monitor audio

In OBS:

1. Open `Settings > Audio`
2. Set `Monitoring Device` to your headphones, speakers, or interface output

This is the device you will use to actually hear the show locally.

### 4. Add BlackHole as an OBS input

In OBS:

1. In `Sources`, click `+`
2. Add `Audio Input Capture`
3. Name it something like `PowerPoint Bus`
4. Choose device: `BlackHole 2ch`

This source is now your PowerPoint audio path inside OBS.

### 5. Turn monitoring on

In OBS:

1. Open `Edit > Advanced Audio Properties`
2. Find `PowerPoint Bus`
3. Set `Audio Monitoring` to `Monitor and Output`

Now:

- OBS outputs the audio to stream and recording
- OBS also sends it to your monitoring device
- OBS mute and fader control now affect what you hear locally

### 6. Keep PPTBridge SK Slide for video and slide control

Your workflow becomes:

- `PPTBridge SK Slide` = video, slideshow, hotkeys, presentation control
- `PowerPoint Bus` = audio path you control in OBS

### 7. Important warning

With this BlackHole setup, all audio going to your Mac system output may end up on BlackHole, not just PowerPoint.

That means:

- PowerPoint works
- but browser sounds, notifications, and other app audio can also get captured if they play during the show

For live events, this is safest when:

- you use a dedicated show laptop
- you silence system notifications
- you keep non-show apps closed

## Loopback setup

This is the cleaner pro setup because it can route only Microsoft PowerPoint into OBS.

### 1. Install Loopback

Install Loopback and allow the required permissions and ARK component.

### 2. Create a virtual device for PowerPoint

In Loopback:

1. Create a new virtual device
2. Name it `PPTBridge PowerPoint Audio`
3. Add source: `Microsoft PowerPoint`

Do not add a local monitor inside Loopback if your goal is strict OBS-only control.

### 3. Add the Loopback device to OBS

In OBS:

1. Add `Audio Input Capture`
2. Choose device: `PPTBridge PowerPoint Audio`

### 4. Turn monitoring on in OBS

In OBS:

1. Open `Edit > Advanced Audio Properties`
2. For `PPTBridge PowerPoint Audio`, choose `Monitor and Output`

### 5. Set OBS monitoring device

In `Settings > Audio`, choose your speakers, headphones, or interface as the `Monitoring Device`.

### 6. Keep PPTBridge SK Slide for visuals

Your clean pro workflow becomes:

- `PPTBridge SK Slide` = live PowerPoint slideshow in OBS
- `PPTBridge PowerPoint Audio` = PowerPoint audio under OBS fader and mute control

This is the cleanest approach because:

- only PowerPoint gets routed
- system sounds stay separate
- OBS becomes the single audio control point

## Which one should you actually use?

Use BlackHole if:

- you want free
- you are okay with routing the whole Mac output during the show

Use Loopback if:

- you want the cleanest conference workflow
- you want only PowerPoint audio in OBS
- you want fewer surprise sounds from other apps

## Recommended live conference workflow

For a serious event setup:

1. `PPTBridge SK Slide` for live slideshow
2. `PPTBridge SK Presenter` for notes and confidence monitor
3. `Loopback` virtual device for PowerPoint-only audio
4. OBS mixer for all show-time level control
5. Headphones or interface as OBS monitoring output

That is the most reliable route if you want PowerPoint to behave like a real show playback source while still being mixed from OBS.

## Official references

- BlackHole main page: https://existential.audio/blackhole/
- BlackHole support: https://existential.audio/blackhole/support/
- Loopback main page: https://www.rogueamoeba.com/loopback/
- Loopback manual: https://www.rogueamoeba.com/support/manuals/loopback/
- Loopback permissions: https://www.rogueamoeba.com/support/manuals/loopback/?page=permissions
