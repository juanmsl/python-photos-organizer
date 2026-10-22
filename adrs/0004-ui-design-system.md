# ADR 0004: UI design system and custom controls

- **Status:** Accepted
- **Date:** 2026-10-22
- **Deciders:** Project owner
- **Builds on:** [ADR 0003](0003-native-swift-macos-app.md). It changes only the SwiftUI layer
  (`Sources/PhotosOrganizer/`); `AppModel`, `PhotosOrganizerCore` and every behaviour decision in
  ADR 0001–0003 are unchanged.

## Context

The first SwiftUI version (ADR 0003) mirrored the Qt window with stock controls. The owner asked for
a "high-end boutique minimalist" redesign: a dominant dark/light background with one sharp accent,
depth from layered materials, a strict 4-pt spacing grid, 44-pt hit targets, clear typographic
hierarchy, spring animations, and clean loading/empty/dark-mode states.

The brief was written for iOS, so parts of it had to be adapted for a Mac app that works on large
file lists and can delete files.

## Decision

### 1. All styling comes from `AppTheme` tokens

`Sources/PhotosOrganizer/AppTheme.swift` is the only place that defines visual values:

| Token group | Contents |
|-------------|----------|
| `Colors` | Background layers, surface tint, well, hover, borders, two text levels, `accent`, `warning`, `danger`, and their foregrounds. Each one has a light and a dark value. |
| `Spacing` | `xs 4`, `s 8`, `m 16`, `l 24`, `xl 32` |
| `Radius` | `xs 4`, `small 8`, `medium 12`, `large 16`, always drawn with continuous corners (`RoundedRectangle.themed`) |
| `Metrics` | `hitTarget 44`, `sidebarWidth 248` |
| `Motion` | `spring` (response 0.35, damping 0.75) for state changes; `press` (0.22 / 0.8) for press feedback |

**Rule:** views don't hard-code colours, spacing, radii, sizes or animations; they use these tokens
and the shared components in `Components.swift`. New visual values are added to `AppTheme` first.

### 2. One accent colour; status colours stay semantic

- The only brand colour is **chartreuse** (`#C6F35E`) in dark mode and **deep olive** (`#3F6E00`) in
  light mode. It marks the primary action, selection, checked items, progress and success.
- `danger` (red) is used only for deleting and errors, and `warning` (amber) only for skipped files
  (duplicates, no date). Neutral states (planned, trashed) use secondary text.
- Text and its background, and button labels and their fill, are at least **4.5:1** (WCAG AA) in
  both modes.
- New features must not add a second accent colour.

### 3. Custom controls instead of stock ones

Buttons (`ThemeButtonStyle`), the segmented control (`SegmentedPicker`), the switch
(`ThemeSwitchStyle`), the file-type checkboxes, the progress bar and the surfaces are custom.

- **Why:** stock macOS controls can't take the accent colour, materials and spacing consistently, and
  are smaller than 44 pt.
- **Cost:** custom controls don't get every native behaviour for free. Each one must keep:
  - **Accessibility:** the selected state is exposed with `.isSelected`; the switch provides a native
    `Toggle` through `accessibilityRepresentation`; rows have an `accessibilityLabel`.
  - **Keyboard shortcuts:** Return for *Organize* (not for *Delete*), Escape for *Cancel*.
  - **Disabled state:** read from `\.isEnabled`, shown at 40 % opacity.

### 4. Deliberate departures from the brief

- **Actions run on release; feedback starts on press.** The brief asked for interactions to trigger on
  pointer-down. Controls react visually as soon as they're pressed (`isPressed` → scale 0.97), but the
  action runs on release, as everywhere on macOS, so a press can be cancelled by dragging away. Running
  on press would make *Delete* fire on the first click with no way back.
- **Table rows keep the native height.** Every control has a 44-pt target, but the file table's rows
  don't: they're for reading, not clicking, and 44-pt rows would make lists of thousands of files much
  harder to scan. The table stays a native SwiftUI `Table` for performance.

### 5. Window, states and motion

- Hidden title bar with a large-title header; minimum window size **1040 × 720** (default 1240 × 820)
  so the control bar fits on one row.
- Depth: a three-layer background (base colour, vertical lift, faint accent glow) under
  `.ultraThinMaterial` surfaces with a hairline border and a soft shadow.
- The file area has explicit states: no folder chosen, scanning, empty folder, no file types
  selected, and the table.
- The progress bar shows while work runs and afterwards only while the table still shows that run's
  results.
- State changes use `AppTheme.Motion.spring`. SwiftUI springs retarget from their current value, so
  animations stay interruptible, including the progress bar fed by live updates.
- The app icon (`scripts/make-icon.swift`) uses the same palette: graphite tile, chartreuse symbol.

## Consequences

### Positive

- A consistent, distinctive look in light and dark mode, following the system appearance.
- Restyling means editing `AppTheme`, not every view.
- Bigger targets and clear empty states make the app easier to use, especially on first launch.

### Negative / risks

- **More code to maintain:** custom controls are about 300 lines that stock controls would provide.
- **Not every native behaviour is replicated:** custom buttons and segments show no keyboard focus
  ring and aren't reachable with Tab unless *Keyboard navigation* is on in System Settings.
  VoiceOver works but has had only light testing.
- **Larger minimum window:** 1040 × 720 doesn't fit on very small displays.
- The design was checked with off-screen renders, not on a range of real displays.

### Follow-ups (not yet decided)

- Focus rings and full keyboard navigation for custom controls.
- A VoiceOver pass and Increase Contrast / Reduce Motion support (for example, crossfades instead of
  springs when *Reduce Motion* is on).
- A snapshot test target that renders the main states in both modes, to catch visual regressions.
