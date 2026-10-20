# Design System — Forest Fire Monitor app

A calm, flat field tool. **Colour is reserved for meaning** — risk, status, severity, air quality — never for
decoration. Text is written for a forest officer on a phone, not for an engineer.

| Principle | In practice |
|---|---|
| **Plain language** | "Fire seen by camera", "Sensor went offline", "Restarted after it stopped responding" — no codes, no ALL CAPS except the fire pop-up |
| **Always say how sure** | camera confidence on every camera alert; "Live" vs "Last reading"; stale data says so |
| **Calm by default** | neutral surfaces, 1 px hairlines, no shadows on cards; red only when something is wrong |
| **Urgent means urgent** | a fire takes over the screen with a red pop-up and alarm; everything else is quiet |

Source: [`lib/theme/app_theme.dart`](lib/theme/app_theme.dart), labels in [`lib/utils/friendly.dart`](lib/utils/friendly.dart).

## 1. Colour

### Neutrals

| Token | Value | Use |
|---|---|---|
| background | `#F6F7F6` | page canvas, app bar |
| surface | `#FFFFFF` | cards, inputs, dialogs, navigation bar |
| border | `#E3E6E3` | hairlines on cards, inputs, chips, dividers |
| ink | `#1B1F1B` | titles and body text |
| muted | `Colors.grey.shade600–700` | secondary text, hints |
| accent (primary) | `#2E7D32` forest green | buttons, selected tab, links |

### Meaning

| Meaning | Colour |
|---|---|
| Risk Low / Moderate / High / Critical | green / orange / deep orange / red (`risk_utils.dart`) |
| Severity of an alert | same scale (`severityColor`) |
| Online / stale / offline | green / orange / red (`NodeStatusChip`) |
| Air at sensor | clean green · slight amber · smoke orange · heavy smoke red · gas purple · learning/unknown grey |
| Fire areas on the map | active red `#E53935` (22% fill) · possible spread amber `#FFB300` (12% fill), dashed borders |
| Directions | blue `#1E88E5` route, dashed for the walk at the end |
| Camera result | Fire red · Smoke orange · Normal green |

## 2. Typography

Material 3 type scale with the platform font.

| Role | Style |
|---|---|
| App bar title | 20 px, 600 |
| Card title | 15 px, 600 |
| Section label | 12 px, bold, uppercase, primary colour |
| Value in a row | 15 px, 600 |
| Label / hint | 12–12.5 px, muted |
| Live panel figure | 15 px, 700, scales down to fit |
| Fire pop-up headline | 32 px, 900, white on red |

## 3. Shape and spacing

- Cards 16 px radius with a 1 px border, no elevation; buttons and inputs 12 px; chips 20 px; dialogs 20 px.
- Screen padding 16 px; cards 12 px apart; row padding 6 px.
- Buttons at least 44–46 px tall (thumb-sized, also with gloves).
- Floating map controls: white circles, 3 px elevation, right edge.

## 4. Components

| Component | Notes |
|---|---|
| **Live panel** | translucent white card over the map: status dot, five figure tiles, air row, fire-prediction row |
| **Sensor marker** | name label + coloured circle (risk, grey when offline); tap opens details |
| **Details sheet** | draggable bottom sheet; sections Live readings · Power · Wi-Fi · Sensors · Board · Place |
| **Trend chart** | card with legend + latest values; pinch-zoom chip shows "3.2x · Reset" |
| **Alert card** | icon in a tinted circle, title, sensor · time, status pill, message, verdict / action buttons |
| **Timeline** | vertical line with tinted icon dots, title, time and detail |
| **Pill** | 10% tinted background, coloured 12 px 600 text |
| **Fire pop-up** | full-screen red dialog, not dismissible by tapping outside, alarm until acknowledged or dismissed |
| **Banners** | update available (top), alert service offline (red), demo mode (orange) |

## 5. Motion

Material defaults only: sheets slide, snack bars float, the map animates to fit a route. Nothing loops except the
alarm sound during a fire pop-up.

## 6. Accessibility

- Every icon button has a tooltip; status is never shown by colour alone (always a word: "Live", "Offline", "Low").
- Text meets contrast on white and on the background; the fire pop-up uses white on dark red.
- Large touch targets; the map works with one hand (controls on the right edge, panel collapsible).
- Light theme only for now; dark mode is a proposed improvement for night patrols.
