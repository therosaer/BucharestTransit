# Changelog

## 1.4

Native feel pass on the existing Leaflet map. The Apple Maps version lives on the `v1.4-apple-maps` branch.

### Navigation
- Floating liquid glass tab selector with a sliding glass indicator. Tabs: Hartă, Linii, Bilete.
- Renamed "Elevi/Stud." to "Bilete". Removed the Statistici tab and its screen.
- Active-ticket dot on Bilete is green.
- App display name is now BTranzit (bundle ID and module name unchanged).

### Linii
- Rows show the line plate, route terminals and "N vehicule în circulație" with a live dot, instead of the repeated vehicle type and the English "active".
- Favorites: swipe or long-press a line to favorite it. A Favorite section appears at the top.
- Empty and search-empty states. One-color filter chips with selected trait. Selection haptic on filter change.
- Shared `LinePlate` view: white text on every plate, with the background darkened only as far as needed for 4.5:1 contrast.

### Line sheet
- Everything under the header scrolls as one view, which fixes the station list being cut off at the half-height detent.
- Collapsed detent is shorter (92pt) with less empty space. Removed the floating duplicate close button.
- Sentence-case section labels, no emoji, no bounce, tabular figures for arrival times.

### Bilete
- Left-aligned login with one intro line, plain fields and a button. Removed the duplicate heading and the film-strip icon.
- Ticket card puts the QR first. Quiet status line, tabular remaining time, accessibility labels on the card and QR.

### Map controls and sheets
- Round glass buttons at a fixed 52pt for settings, locate and search.
- Ticket countdown pill moved to the top left, away from the settings button.
- Stop and vehicle sheets: sentence-case labels, no heavy rounded fonts, 44pt close buttons with labels.

### Typography, color and motion
- Heavy rounded fonts replaced with semibold system fonts. Hairline borders and lighter shadows replace large shadows.
- Bouncy springs replaced with `.smooth`. Animations respect Reduce Motion.
- Dynamic Type text styles replace fixed font sizes.

### Accessibility
- VoiceOver traits on tabs and filter chips, labels on icon-only buttons, 44pt touch targets, combined row reading.
- Search field: shorter prompt, no forced capitals, labeled clear button.

### Fixes and tooling
- Build releases with `xtool dev build -c release` or `xtool dev run --usb -c release`. Debug builds are much slower and run hot.
- `.gitignore` now excludes `.ipa`, `.app`, `xtool/`, `Payload/`, `.dSYM` and `.xcarchive`.

## 1.3.1
- Fix wrong line data and refresh GTFS data.
