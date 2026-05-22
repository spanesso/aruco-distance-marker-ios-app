# Marker Guide

How to print, calibrate, and detect the ArUco marker included in the project.

---

## The marker

The file `aruco-distance-marker/marker/aruco-id0-4x4-50mm.pdf` is the official project marker. Printed correctly it measures **10 × 10 cm** on the outer black border.

- Dictionary: `DICT_4X4_50` (4×4 bits, 50 IDs)
- ID: 0
- Also available as PNG at `assets/marker.png` for visual reference

---

## How to print

Open the PDF in Preview (macOS) or any PDF viewer. In the print dialog:

- Choose **"Actual Size"** or **"100%"**. Never "Fit to Page" — that option scales the content and breaks calibration.
- If your printer's minimum margins clip the border, enable "Fit to Printable Area" and then measure the result with a ruler.

Standard white paper (80–90 g/m²). Matte finish is better than glossy — it doesn't reflect ceiling lights or the camera flash.

**After printing, verify with a ruler.** Measure the black square from outer corner to outer corner — don't include the white margin:

```
┌──────────────────────────────────┐
│         (white margin)           │
│   ┌──────────────────────┐       │
│   │ ← measure this side  │       │ ← outer black border
│   │  ███░░███░██░░░░███  │       │
│   │  ░░░███░░░███████░░  │       │
│   │  ██░░░███░░░░███░██  │       │
│   │  ░░░░░░░░░░░░░░░░░░  │       │
│   └──────────────────────┘       │
│         (white margin)           │
└──────────────────────────────────┘
         ↑ measure from here to here ↑
                should be 10 cm
```

If the printer respected 100%, the square measures exactly 10 cm. If not, note the actual measurement — you'll need it for calibration.

---

## Calibrating the size in the app

Open `aruco-distance-marker/aruco-distance-marker/Domain/ArucoConfig.swift` and update `markerSideMeters`:

```swift
enum ArucoConfig {
    static let markerSideMeters: Double = 0.10  // 10 cm → 0.10
}
```

Change the value (always in meters), hit ⌘B and run on device again.

### If the distance is still off

Even with the right size it can happen that the app reports something different from the real distance. To fix it without measuring the PDF precisely:

1. Place the marker at a known distance — a table at 30 cm works fine.
2. Note what the app reports.
3. Apply this correction:

```
new_value = current_value × (actual_distance_cm / reported_distance_cm)
```

Concrete example: the app says 24.5 cm but your tape measure reads 30 cm.

```
0.10 × (30 / 24.5) = 0.122
```

Set `markerSideMeters = 0.122`, compile, and test. Check at two or three different distances to confirm the correction holds.

---

## Using the app

1. Print the marker and place it on a flat surface. A white or light grey background works best — fewer false positives.
2. Even lighting, no shadows crossing the black square.
3. Open the app. On first launch iOS asks for camera permission — tap Allow. If you accidentally deny it: **Settings → ArucoDistance → Camera → Allow**.
4. Point the back camera at the marker. Detection is automatic — when the marker is found, the green contour appears and the distance shows at the bottom.

### Working conditions

| Condition | Good range |
|---|---|
| Minimum distance | ~20 cm (closer and it may leave the frame) |
| Maximum distance | ~100 cm with a 10 cm marker |
| Angle | Up to ~45° tilt; more and the contour starts flickering |
| Lighting | ~50 lux minimum — normal office light is fine |
| Orientation | Portrait only |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Detects nothing | Marker too far away | Get closer |
| Detects nothing | Not enough light | Turn on more lights |
| Detects nothing | Marker is bent or wrinkled | Tape it to a rigid surface |
| Contour flickers | Too oblique an angle | Hold the phone more parallel to the marker |
| Distance is way off | `markerSideMeters` not calibrated | Use the correction formula above |
| Detects the wrong thing | False positive on a background pattern | Move the marker to a plain background |

---

## What distance is measured

The app reports the distance **from the rear camera module to the center of the marker**, along the optical axis:

```
                     ┌───────────┐
  iPhone             │  Marker   │
  [📷]─ ─ ─ ─ ─ ─ ─│     ·     │
                     └───────────┘
  ←──── D (what you see on screen) ────→
```

Not from the screen — from the lens. The difference is ~8–10 mm, irrelevant at typical working distances.

**Expected accuracy:** ±5–10% in the 20–100 cm range, with the marker centered in frame. The biggest source of error is `markerSideMeters` not matching the actual printed marker.

---

## Usable range with a 10 cm marker

| Distance | Size in image | Reliability |
|---|---|---|
| 15 cm | ~480 px | Very high (may fill the FOV) |
| 30 cm | ~240 px | Very high |
| 50 cm | ~145 px | High |
| 80 cm | ~90 px | High |
| 100 cm | ~72 px | Medium-high |
| 150 cm | ~48 px | Medium — starts to miss |
| > 200 cm | < 36 px | Unreliable |

For distances beyond 150 cm, print the marker bigger (e.g. 20 cm) and set `markerSideMeters = 0.20`.
