# Mac Numpad

A macOS menu-bar app that turns your MacBook's built-in trackpad into a numeric keypad
plus brightness and volume sliders — **but only while you hold Control**. Release Control
and the trackpad is your normal mouse again, instantly.

## What it does

- **Hold ⌃ Control** → the trackpad becomes a keypad. A touch on any key types it straight
  into the focused app (no click needed; physical clicks and tap-to-click work too, and the
  same touch never types twice).
- **Drag the two left strips** → brightness (left) and volume (right), by finger distance —
  a touch alone changes nothing, and a strip finger can never press keys.
- **Release Control** → pointer unfreezes on the spot, keys stop firing, drags cancel.

A small floating mirror shows the live layout, highlights the key under your finger,
flashes whichever key just fired, and reports the Active/Idle/Permission state.

The keypad is calculator-style: `+ × − ÷` on top, digits `7 8 9 / 4 5 6 / 1 2 3`,
a tall `0`, `.`, `⌫` and a tall `⏎` so a typed search can be corrected and submitted.
Typed digits carry no modifier flags, so the held Control never turns a digit into a
shortcut such as Control+1.

## Requirements

- A MacBook with a **built-in trackpad** (Apple Silicon, macOS 13+; tested on macOS 26).
- Xcode Command Line Tools (`swiftc`) to build.

## Permissions

Launch asks for two System Settings grants on first run:

- **Accessibility** — to post keys and block mouse events while Control is held.
- **Input Monitoring** — to watch the Control key.

Both links are shown in the mirror's red status pill until granted; the app arms itself
automatically the moment both are on. Builds are signed with a stable self-signed code
signing identity ("TouchPad Keypad Dev"), so the grants survive rebuilds.

## Build & run

```sh
./build.sh && open build/TouchPadKeypad.app
```

`build.sh` compiles with `swiftc -O` (Swift 5 language mode), assembles the .app bundle,
and signs it. To create the stable signing identity used by the script:

```sh
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout key.pem -out cert.pem -days 3650 \
  -subj "/CN=TouchPad Keypad Dev" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" \
  -addext "basicConstraints=critical,CA:FALSE"
openssl pkcs12 -export -out identity.p12 -inkey key.pem -in cert.pem -passout pass:choose-one
security import identity.p12 -P choose-one -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign cert.pem
```

## How it works

| Need | Approach |
| --- | --- |
| Finger positions system-wide | Private `MultitouchSupport` framework (`MTRegisterContactFrameCallback` → `MTDeviceStart(dev, 0)`), 96-byte contact records read by byte offset |
| Control detection + pointer freeze | Active `CGEventTap` (session, head-insert); while Control is held it drops moves, clicks, scrolls and re-enables itself if macOS times it out |
| Typing | `CGEvent` keyboard posts with the character set directly and all flags cleared |
| Volume | CoreAudio `kAudioDevicePropertyVolumeScalar` on the default output, AppleScript fallback |
| Brightness | Private `DisplayServices` framework, built-in display only |
| Mirror | Non-activating floating `NSPanel` + SwiftUI, never takes keyboard focus |

Safety: if the app quits or crashes, the event tap disappears and the trackpad is a
normal mouse again immediately; the app pauses itself on sleep/lock and from the
menu-bar menu; slider changes are capped per touch frame.

## Project layout

```
Sources/TouchPadKeypad/
  PadLayout.swift      trackpad region map (strips, dead zone, key grid)
  PadEngine.swift      touch frames + Control state → actions and mirror state
  Multitouch.swift     MultitouchSupport private-framework adapter
  EventTap.swift       CGEventTap: Control detection, pointer freeze, clicks
  SystemControls.swift keyboard typing, CoreAudio volume, DisplayServices brightness, logger
  MirrorWindow.swift   floating frosted-glass mirror
  AppState.swift       shared ObservableObject state
  main.swift           app delegate, engine lifecycle, menu bar
build.sh               build + bundle + sign
```

## Known limits

- Private Apple frameworks can change with macOS updates (each is behind a single
  adapter file on purpose).
- Some external/USB outputs expose no software volume: that strip greys out, as brightness
  does on external displays (out of scope).
- Secure-input fields (passwords) may block synthetic typing by design.

## License

MIT — use it, fork it, ship it.
