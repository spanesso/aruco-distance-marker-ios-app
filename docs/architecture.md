# Architecture

ArucoDistance uses Clean Architecture with three layers plus a composition root.

## Layer diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ App                                                              │
│  aruco_distance_markerApp (@main, @StateObject CameraViewModel)  │
│  CompositionRoot — wires concrete Data → use cases → ViewModels  │
└────────────────────┬────────────────────────────────────────────┘
                     │ instantiates and connects
       ┌─────────────┴──────────────┬────────────────────┐
       ▼                            ▼                    ▼
┌──────────────────┐  ┌───────────────────┐  ┌──────────────────┐
│ Presentation     │  │ Domain            │  │ Data             │
│  ViewModels      │  │  Entities         │  │  Camera repo     │
│  Views (pure)    │──▶│  UseCases        │◀─│  Detection repo  │
│  Containers      │  │  Repo protocols   │  │  Permission repo │
│  UIKit hosts     │  │  ArucoConfig      │  │  OpenCV bridge   │
└──────────────────┘  └───────────────────┘  └──────────────────┘
   depends on Domain      depends on nothing     depends on Domain
   (protocols only)       (just Foundation/simd) (protocols only)
```

## Dependency rule

`Domain` has no framework dependencies. `Presentation` and `Data` depend only on `Domain` protocols and entities. `App` is the only layer that may depend on all three.

This rule has practical consequences:
- `Domain` can be moved to a separate package and built without UIKit/SwiftUI/AVFoundation/OpenCV.
- `Presentation` Views can be previewed in isolation, since they don't pull in OpenCV.
- Replacing OpenCV with Vision framework would only touch files in `Data/Detection/`.

## MVVM with decoupled ViewModels

The rule that drives the View hierarchy:

> No reusable View owns a ViewModel. ViewModels are owned only by the composition root.

Practical implementation:
- `aruco_distance_markerApp` (App layer, the composition root) holds `@StateObject var cameraViewModel`.
- `CameraScreenContainer` (Presentation) is a thin adapter — it has `@ObservedObject var viewModel: CameraViewModel` and forwards values/callbacks to `CameraScreenView`.
- `CameraScreenView` and every leaf view (`CameraContentView`, `DetectionOverlayView`, `PermissionRequestView`, `PermissionDeniedView`) take only pure init parameters: state values and callbacks.

Result: every reusable View is previewable, testable, and decoupled from the rest of the system.

## Data flow

```
AVFoundation delegate (cameraQueue)
  └── AVFoundationCameraRepository
        └── frames: AsyncStream<CameraFrame> (bufferingNewest(1))
              └── DefaultDetectMarkersUseCase
                    └── detections(): AsyncStream<[MarkerDetection]>
                          └── CameraViewModel.detectionTask (MainActor)
                                └── @Published var detections
                                      └── CameraScreenContainer observes
                                            └── CameraScreenView (pure render)
```
