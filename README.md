# Mac Numpad

A lightweight macOS menu-bar app that transforms your MacBook's built-in trackpad into a numeric keypad and system control strip—**activated only while holding the Control key**.

---

## Features

- **Control-Activated Numpad:** Hold `⌃ Control` to instantly map the trackpad into a calculator-style keypad. Touches type immediately without requiring a click, while physical clicks and tap-to-click are fully supported.
- **System Sliders:** Drag along the two dedicated left-edge strips to seamlessly adjust **brightness** (left) and **volume** (right) based on finger distance. Strip drags are strictly isolated from key presses.
- **Instant Reset:** Releasing `⌃ Control` immediately unfreezes the pointer, stops key emission, and cancels ongoing gestures.
- **Floating Mirror HUD:** A non-activating, frosted-glass overlay displays the live layout, highlights active fingers, flashes triggered keys, and reports system states (Active/Idle/Permissions).
- **Smart Modifiers:** Typed digits carry no modifier flags, ensuring held keys like Control never accidentally trigger system shortcuts (e.g., Control + 1).

---

## Requirements

- A MacBook with a **built-in trackpad** (Apple Silicon, macOS 13+; tested on macOS 26).
- Xcode Command Line Tools (`swiftc`) for building.

---

## Permissions

On first launch, the app prompts for two essential system permissions:

- **Accessibility:** Required to post synthetic keystrokes and intercept mouse events while Control is held.
- **Input Monitoring:** Required to monitor the `Control` modifier state.

> **Note:** Builds are signed with a stable self-signed identity (`TouchPad Keypad Dev`) so permission grants persist across rebuilds.

---

## Build & Run

Compile, bundle, and sign the application using the build script:

    ./build.sh && open build/TouchPadKeypad.app

### Setting Up the Stable Signing Identity

To generate the local code-signing identity required by `build.sh`, run the following OpenSSL and security commands:

    openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout key.pem -out cert.pem -days 3650 \
      -subj "/CN=TouchPad Keypad Dev" \
      -addext "keyUsage=critical,digitalSignature" \
      -addext "extendedKeyUsage=codeSigning" \
      -addext "basicConstraints=critical,CA:FALSE"
    openssl pkcs12 -export -out identity.p12 -inkey key.pem -in cert.pem -passout pass:choose-one
    security import identity.p12 -P choose-one -T /usr/bin/codesign
    security add-trusted-cert -r trustRoot -p codeSign cert.pem

---

## Technical Architecture

| Component | Implementation Detail |
| --- | --- |
| **Touch Tracking** | Private `MultitouchSupport` framework (`MTRegisterContactFrameCallback` → `MTDeviceStart`), reading 96-byte contact records. |
| **Event Tap** | Active session-level `CGEventTap` to freeze pointer movement, clicks, and scrolls when Control is held. |
| **Keyboard Injection** | Direct `CGEvent` keyboard posts with cleared flags for layout independence. |
| **Audio Control** | CoreAudio `kAudioDevicePropertyVolumeScalar` on default output with AppleScript fallback. |
| **Brightness Control** | Private `DisplayServices` framework for built-in displays. |
| **UI Overlay** | Non-activating floating `NSPanel` built with SwiftUI. |

---

## Project Structure

    Sources/TouchPadKeypad/
      ├── PadLayout.swift      # Trackpad region map (strips, dead zone, key grid)
      ├── PadEngine.swift      # Touch frames & Control state logic
      ├── Multitouch.swift     # MultitouchSupport private-framework adapter
      ├── EventTap.swift       # CGEventTap: Control detection, pointer freeze
      ├── SystemControls.swift # Keyboard typing, CoreAudio, DisplayServices
      ├── MirrorWindow.swift   # Floating frosted-glass HUD mirror
      ├── AppState.swift       # Shared ObservableObject state
      └── main.swift           # App delegate, lifecycle, and menu bar

---

## Limitations & Safety

- **Private Frameworks:** Apple's private APIs may change across macOS versions; they are isolated inside dedicated adapter files.
- **External Hardware:** External USB outputs or external displays may lack software volume/brightness properties, causing those strips to gracefully grey out.
- **Secure Input:** Password fields with secure-input enabled may block synthetic typing by design.
- **Safety Defaults:** If the app quits or crashes, the event tap unbinds immediately and the trackpad returns to normal. The app also automatically pauses during sleep/lock states.

---

## License

Distributed under the MIT License.
