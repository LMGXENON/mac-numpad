# PRD: TouchPad Keypad for macOS

Oct 23, 2026 · @honey

## Overview

TouchPad Keypad is a macOS menu-bar app that turns your MacBook trackpad into a numeric keypad plus volume and brightness sliders, but only while you hold Control. Release Control and the trackpad is a normal mouse again. A small window mirrors the trackpad live, so you can see where your finger is and which key you just pressed.

Assumptions in this draft: it is a personal tool for one Mac, built in Swift, and not for the Mac App Store, because it relies on private Apple frameworks. Version 1 supports the built-in MacBook trackpad only.

## Problem and goals

The trackpad can move a pointer but cannot type digits or set system levels, so you reach for the number row or function keys. The goal is to do both from the trackpad without giving up normal mouse use.

**Goals**

- Type digits 0 to 9 into any focused field (for example the Google search box) by clicking a region of the trackpad.
- Change volume and brightness by dragging up or down on two strips at the left edge.
- Stay safe: everything is active only while Control is held, so the trackpad still works as a mouse otherwise.
- Show every touch and keypress live in a mirror window.

**Non-goals for v1**

- External mice, Magic Trackpad, Windows or Linux.
- Mac App Store distribution.
- Letters, symbols or custom gestures.
- Brightness control for external displays.
- User-designed layouts or themes.

## Target user and use cases

The user is one person on a MacBook who wants quick number entry and level changes without leaving the trackpad.

1. **Type a number into a search box.** Release Control and click the Google search field with the normal pointer. Hold Control, then click digits on the trackpad. The digits appear in the field.
2. **Change volume.** Hold Control and drag a finger up or down the left strip.
3. **Change brightness.** Hold Control and drag up or down the second strip.

## Touchpad layout

The trackpad is mapped as a flat rectangle with two slider strips on the left and a 3 by 4 key grid filling the rest. Positions are normalized: x runs 0 to 1 left to right and y runs 0 to 1 bottom to top, so the layout works on any MacBook trackpad size.

&#91;embedded content: touchpad layout · 2 slider strips, 12 keys\]

The strips sit at the left edge and the keys fill the rest, with a gap between them that keeps slider drags off the keys.

| Region | x range | y range | Behaviour |
| --- | --- | --- | --- |
| Volume strip | 0.03 to 0.12 | 0.06 to 0.94 | Drag up raises, drag down lowers |
| Brightness strip | 0.14 to 0.22 | 0.06 to 0.94 | Drag up raises, drag down lowers |
| Dead zone | 0.22 to 0.28 | all | Ignored, so a slider drag never lands on a key |
| Key grid | 0.28 to 0.97 | 0.06 to 0.94 | 3 columns by 4 rows, click types the digit |

The values are starting points and will be tunable in settings.

## Functional requirements

P0 means required for v1, P1 means soon after, P2 means later.

| ID | Requirement | Priority |
| --- | --- | --- |
| FR1 | The app is active only while Control is held. On release it is inactive within one frame and the trackpad acts as a normal mouse. | P0 |
| FR2 | While active, the pointer stays frozen and trackpad clicks, taps and scrolls are not passed to other apps. | P0 |
| FR3 | A physical click or tap-to-click while a finger rests on a key types that digit into the frontmost app. The key fires on press, not release. | P0 |
| FR4 | Typed digits carry no modifier flags, so the held Control key does not turn a digit into a shortcut such as Control+1. | P0 |
| FR5 | Dragging a finger that started in a slider strip changes volume or brightness by the distance moved. Touching the strip alone changes nothing. | P0 |
| FR6 | A finger that starts in a strip stays a slider finger until it lifts, so it cannot press keys. | P0 |
| FR7 | The mirror window shows finger positions, the key under the finger, the last key pressed, both slider levels and the active state in real time. | P0 |
| FR8 | A menu-bar icon enables, pauses and quits the app. | P0 |
| FR9 | Backspace and Return keys in the bottom row, so a typed search can be corrected and submitted. | P1 |
| FR10 | Settings for the activation modifier, region sizes and slider sensitivity. | P2 |

## GUI

The GUI is a small always-on-top window that mirrors the trackpad, so you can use the pad without looking at your hands. It must never take keyboard focus, or the digits would type into the app itself instead of the Google search box.

- **Pad mirror.** A rectangle with the trackpad's aspect ratio showing the two strips and the key grid at the same normalized positions as the real layout.
- **Finger dots.** One dot per touch, updated on every touch frame.
- **Key feedback.** The key under the finger is lightly highlighted. On a press it flashes for about 150 ms and stays marked as the last key pressed.
- **Sliders.** Each strip shows its current level as a fill and a percentage, and follows the real system value if it changes by other means.
- **Input strip.** The last 12 digits the app typed, shown as running text, with a clear button. It shows what the app sent, not what the target field contains.
- **Status pill.** Active while Control is held, Idle otherwise, and a red state with a link to System Settings when a permission is missing.

## Technical approach

Build a native Swift app (SwiftUI for the window, AppKit for system hooks) targeting macOS 13 or later. One input engine takes touch frames plus the Control state, decides which region each finger is in, and emits actions (type a digit, change a level) and UI state for the mirror window. These details come from general knowledge of macOS and must be confirmed in the first spike.

| Need | Approach | Caveat |
| --- | --- | --- |
| Finger positions anywhere on screen | Apple's private MultitouchSupport framework, which reports each finger with normalized x and y | Private API, can break on a macOS update. The public NSTouch route only works inside the app's own focused window, so it cannot be used here. |
| Detect Control and block the mouse | An active CGEventTap watching modifier changes and mouse events. While Control is held it drops move, click and scroll events. | macOS can switch a tap off if it is slow, so the app must re-enable it. If the app quits, the tap disappears and the mouse works normally. |
| Type digits | Post keyboard events with the character set directly and all modifier flags cleared | Sending the character rather than a key code keeps it correct on non-US keyboard layouts. |
| Volume | CoreAudio main volume on the default output device, with an AppleScript volume command as fallback | Some outputs, such as certain HDMI or USB devices, expose no software volume. |
| Brightness | The private DisplayServices framework for the built-in display | No public API exists for this. External displays are out of scope. |
| Mirror window | A non-activating floating NSPanel hosting a SwiftUI view driven by the engine's state | It must not become the key window. |

Hit testing uses the finger's position when the click happens. Sliders use the change in y between touch frames for the same finger, so a touch never makes the level jump.

## Permissions, safety and edge cases

The app needs two macOS permissions: Accessibility, to post key events and block mouse events, and Input Monitoring, to see the Control key. On first launch it checks both, links to the right System Settings pages, and shows a red status until they are granted.

**Safety**

- If the app crashes or quits, its event tap disappears and the trackpad behaves normally at once.
- The menu-bar icon can pause the app, and it pauses itself when the Mac sleeps or locks.
- Slider changes are relative and capped per update, so a stray touch cannot blast the volume.
- Releasing Control mid-gesture cancels any slider drag and fires no key.

**Edge cases**

- Control+click is normally a right-click. While active, the click is swallowed, so no context menu opens.
- Control+number can trigger Mission Control desktop switching if that shortcut is on. Injected digits must carry no modifiers, and the spike must verify this.
- Control+scroll zoom and other trackpad shortcuts that use Control stop working while it is held.
- With two fingers down, a click uses the finger that landed most recently.
- Password fields use secure input, which may block synthetic typing. Digits may not appear there, and that is expected.
- If the display or output device has no software brightness or volume, that slider is greyed out.

## Success, milestones, risks and open questions

**Success metrics (proposed targets)**

- A digit click types within 50 ms.
- A slider follows the finger within one display frame.
- No stray click reaches another app while Control is held, and none is blocked when it is not.
- The app runs a full day without a restart.

**Milestones**

1. **Spike.** Print live finger coordinates and confirm Control freezes the pointer. Done when both work from a bare script.
2. **Keys.** Hit-test the grid and type digits into the Google search box. Done when 0 to 9 type correctly with no modifier side effects.
3. **Sliders.** Volume first, then brightness. Done when both track a finger without jumps.
4. **GUI.** Floating mirror with finger dots, key flash, input strip and status pill.
5. **Hardening.** Permission onboarding, sleep and wake handling, tap re-enable and settings.

**Risks**

| Risk | Impact | Mitigation |
| --- | --- | --- |
| A macOS update changes the private touch or brightness frameworks | Keys or brightness stop working | Keep each behind a small adapter so only one file changes |
| Permissions reset after each rebuild | Repeated re-granting | Sign every build with the same developer identity |
| Control+digit triggers a system shortcut | Wrong action instead of typing | Send digits with modifiers cleared and test early |

**Open questions**

1. Key order: phone style with 1 2 3 on top, as drafted here, or calculator style with 7 8 9 on top?
2. Should the sliders move by finger distance, as drafted, or follow the finger's absolute position?
3. Are Backspace and Return wanted in v1? Without Return a search cannot be submitted from the trackpad.
4. Which MacBook and macOS version will this run on?
