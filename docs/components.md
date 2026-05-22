# Component Reference

What each file does and how it fits in the bigger picture.

---

## Layer map

```
┌────────────────────────────────────────────────────────────────┐
│ App layer                                                       │
│  aruco_distance_markerApp  ←  CompositionRoot                   │
└────────────┬───────────────────────────────────────────────────┘
             │ owns + injects
  ┌──────────┼────────────────────────────────────┐
  ▼          ▼                                    ▼
Presentation           Domain                  Data
CameraViewModel        Entities                AVFoundationCameraRepository
CameraScreenContainer  Repository protocols    OpenCVMarkerDetectionRepository
CameraScreenView       Use cases               AVCaptureDevicePermissionRepository
DetectionOverlayView   ArucoConfig             ArucoDetector (.h / .mm)
CameraContentView                              CameraIntrinsicsExtractor
CameraPreviewView
PermissionRequestView
PermissionDeniedView
```

**Dependency rule:** Domain knows nothing about the other layers. Presentation and Data depend only on Domain protocols and entities. App depends on all three — it's the only place that knows the full picture.

---

## App layer

### `aruco_distance_markerApp.swift`

The `@main` entry point. The only place in the codebase that uses `@StateObject` to own a ViewModel — and that's intentional.

```
aruco_distance_markerApp
  └── @StateObject var cameraViewModel: CameraViewModel
        (created by CompositionRoot, held here for the app's lifetime)
  └── body → WindowGroup → CameraScreenContainer(viewModel: cameraViewModel)
```

`@StateObject` ties the object's lifetime to the view's lifetime. Placing it at the `@main` struct means the ViewModel — and the camera session and detection loop inside it — live for the entire app session. If a reusable View owned a ViewModel with `@StateObject`, SwiftUI could recreate it during view tree rebuilds and kill the camera session mid-stream.

---

### `CompositionRoot.swift`

A `@MainActor struct` with one job: build the dependency graph. It's the only place that touches concrete types from both `Presentation` and `Data`.

```
makeCameraViewModel()
  ├── AVFoundationCameraRepository()            (Data)
  ├── OpenCVMarkerDetectionRepository(dict:)    (Data)
  ├── AVCaptureDevicePermissionRepository()     (Data)
  ├── DefaultDetectMarkersUseCase(...)          (Domain)
  ├── DefaultCameraSessionUseCase(...)          (Domain)
  ├── DefaultCameraPermissionUseCase(...)       (Domain)
  └── CameraViewModel(previewSession:, ...)     (Presentation)
```

No business logic here — just wiring. This is where Dependency Injection happens: the ViewModel receives repositories through its initializer, so it never needs to know which concrete implementation it's working with.

---

## Domain layer

The Domain layer imports only `Foundation`, `CoreGraphics`, `CoreMedia`, and `simd`. No AVFoundation, no UIKit, no SwiftUI, no OpenCV. It could compile on Linux.

### `ArucoConfig.swift`

A pure enum of static constants — the single place to tune the app's behavior.

| Constant | Default | What it does |
|---|---|---|
| `markerSideMeters` | `0.10` | Physical outer side of the printed marker in meters. Wrong value = wrong distance. |
| `dictionary` | `.dict4x4_50` | ArUco dictionary for the detector. |
| `expectedMarkerId` | `0` | Documentation only — the detector reports whatever IDs it finds. |

Using a caseless `enum` (instead of a struct or global variables) means Swift prevents anyone from instantiating `ArucoConfig`. It's a pure namespace.

---

### `Entities/CameraFrame.swift`

A value type that bundles one camera frame with its calibration metadata.

```swift
struct CameraFrame: @unchecked Sendable {
    nonisolated(unsafe) let pixelBuffer: CVPixelBuffer   // raw BGRA pixel data
    let intrinsics: simd_float3x3                         // 3×3 camera matrix (column-major)
    let imageSize: CGSize
    let timestamp: CMTime
}
```

`CVPixelBuffer` is `@MainActor` in the iOS 26 SDK, so `nonisolated(unsafe)` allows access from the camera queue. The buffer is read-only after creation — no mutation ever crosses isolation boundaries, so this is actually safe despite the annotation.

The intrinsic matrix (`fx, fy, cx, cy`) is what lets `solvePnP` compute a real distance in meters. iOS delivers a per-unit factory-calibrated version on every frame; no chessboard calibration needed.

---

### `Entities/MarkerDetection.swift`

The result of detecting one marker in one frame. Travels from Data → Domain → Presentation.

```swift
struct MarkerDetection: Sendable {
    let id: Int
    let cornersInImageSpace: [CGPoint]   // TL, TR, BR, BL in pixel coordinates
    let imageSize: CGSize
    let distanceMeters: Double

    var distanceCentimeters: Double { distanceMeters * 100 }
}
```

`imageSize` is stored alongside the corners so the overlay view can compute the image→view coordinate transform independently, without needing to know the camera resolution from somewhere else.

---

### `Entities/ArucoDictionary.swift`

An enum mapping human-readable dictionary names to `cv::aruco::PredefinedDictionaryType` integer values. Keeps OpenCV integer constants out of Swift call sites.

---

### `Entities/CameraPermissionStatus.swift`

A Swift enum mirroring `AVAuthorizationStatus` for `.video` — the four possible permission states. Exists so `Presentation` can make decisions based on permission status without importing AVFoundation directly.

---

### `Repositories/CameraFeedRepository.swift`

The protocol that defines what any camera source must provide.

```swift
protocol CameraFeedRepository: Sendable {
    nonisolated var frames: AsyncStream<CameraFrame> { get }
    var previewSession: AVCaptureSession { get }
    nonisolated func configure() async throws
    nonisolated func start() async
    nonisolated func stop() async
}
```

`frames` and the lifecycle methods are `nonisolated` so they're consumable from `Task.detached` without a MainActor hop. `previewSession` leaks `AVCaptureSession` into the protocol — that's a deliberate trade-off, since `AVCaptureVideoPreviewLayer` needs the concrete type and abstracting it further buys nothing.

---

### `Repositories/MarkerDetectionRepository.swift`

```swift
protocol MarkerDetectionRepository: Sendable {
    func detectMarkers(in frame: CameraFrame, markerSideMeters: Double) async -> [MarkerDetection]
}
```

One concrete implementation: `OpenCVMarkerDetectionRepository`. The `async` lets callers `await` it without blocking the main thread.

---

### `Repositories/CameraPermissionRepository.swift`

```swift
protocol CameraPermissionRepository: Sendable {
    func currentStatus() -> CameraPermissionStatus
    func requestPermission() async -> CameraPermissionStatus
}
```

---

### `UseCases/CameraSessionUseCase.swift`

Manages configure → start → stop. `DefaultCameraSessionUseCase` is a thin pass-through to `CameraFeedRepository`.

It exists so `CameraViewModel` depends on a protocol, not a concrete class. This also means the use case boundary is the right place to add retry logic, timeout handling, or format negotiation if you ever need it — without touching the ViewModel or the AVFoundation repo.

---

### `UseCases/DetectMarkersUseCase.swift`

The core of the pipeline. Joins the frame stream with the detector to produce `AsyncStream<[MarkerDetection]>`.

```
detections()
  └── AsyncStream { continuation in
        Task.detached(priority: .userInitiated) {
          for await frame in cameraRepository.frames {
            let result = await detectionRepository.detectMarkers(in: frame, ...)
            continuation.yield(result)
          }
          continuation.finish()
        }
      }
```

`Task.detached` keeps the detection loop off `@MainActor`. `bufferingPolicy: .bufferingNewest(1)` on the output means if the ViewModel is still processing the previous update, the old unread detection is dropped — never more than one frame of lag builds up.

---

### `UseCases/CameraPermissionUseCase.swift`

Checks and requests camera permission. `DefaultCameraPermissionUseCase` is a thin adapter over `CameraPermissionRepository`.

---

## Data layer

### `Data/Camera/AVFoundationCameraRepository.swift`

The AVFoundation implementation of `CameraFeedRepository`. Inherits `NSObject` for the `AVCaptureVideoDataOutputSampleBufferDelegate` protocol.

All AVFoundation objects are `@MainActor` in the iOS 26 SDK. They're stored as `nonisolated(unsafe)` and accessed exclusively on `cameraQueue` (a dedicated serial `DispatchQueue`). All mutations go through that queue — the `@unchecked Sendable` on the class documents this contract.

Lifecycle methods (`configure`, `start`, `stop`) bridge `async/await` callers to the serial queue via `withCheckedContinuation`.

`captureOutput(_:didOutput:from:)` fires on `cameraQueue` for every incoming frame. It:
1. Extracts the `CVPixelBuffer`
2. Reads the intrinsic matrix from the sample buffer attachment
3. Builds a `CameraFrame`
4. Yields it to the frames `AsyncStream`

**Format choice:** `sessionPreset = .hd1280x720`, `kCVPixelFormatType_32BGRA`. BGRA is one vectorized pass through `cvtColor(BGRA→GRAY)`. YUV420 would need two passes.

**Rotation:** `connection.videoRotationAngle = 90` (iOS 17+) or `connection.videoOrientation = .portrait` (iOS 15–16) — pixel buffer arrives portrait-oriented before OpenCV sees it.

---

### `Data/Camera/CameraIntrinsicsExtractor.swift`

Two `nonisolated static` methods:

**`extract(from:)`** — reads `kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix`. iOS delivers a raw `Data` blob containing a `simd_float3x3` (column-major). This method unpacks it.

**`approximated(device:imageSize:)`** — fallback for older devices. Computes `fx = width / (2 × tan(fov/2))`, centers the optical center at `(width/2, height/2)`. Less accurate but functional.

Note: `simd_float3x3` is column-major; OpenCV's `cv::Mat` is row-major. The transpose happens in `ArucoDetector.mm` when building `cameraMatrix`.

---

### `Data/Detection/ArucoDetector.h`

The Objective-C interface for the OpenCV bridge. Two classes:

**`ArucoDetectionResult`** — carries one marker's data: `markerId`, four corner `CGPoint`s (image coordinates), `distanceMeters`, `imageSize`.

**`ArucoDetector`** — initialized with a `dictionaryType` integer. Exposes one method:
```objc
- (NSArray<ArucoDetectionResult *> *)detectInPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                         intrinsicMatrix:(simd_float3x3)intrinsicMatrix
                                        markerSideMeters:(double)markerSideMeters;
```

Swift bridging renames `detectIn…` → `detect(in:…)`.

---

### `Data/Detection/ArucoDetector.mm`

The Objective-C++ implementation. **OpenCV headers must be included before any Apple headers** — Apple defines `NO`/`YES` as `false`/`true`, and some OpenCV headers use `NO` as a C++ identifier. If Apple's macros land first, OpenCV won't compile. This is non-negotiable.

Detection pipeline:

```
CVPixelBufferLockBaseAddress()
  └── wrap in cv::Mat (BGRA, zero-copy)
        └── cv::cvtColor(BGRA → GRAY)
CVPixelBufferUnlockBaseAddress()
  └── _detector.detectMarkers(gray, corners, ids, rejected)
        └── for each marker:
              cv::solvePnP(objectPoints, corners[i], K, zeros, rvec, tvec,
                           false, SOLVEPNP_IPPE_SQUARE)
                └── distance = √(tx² + ty² + tz²)
```

Object points (model coordinates, centered at origin — required by `SOLVEPNP_IPPE_SQUARE`):

```
(-s/2,  s/2, 0)  TL     ( s/2,  s/2, 0)  TR
(-s/2, -s/2, 0)  BL     ( s/2, -s/2, 0)  BR
```

`CORNER_REFINE_SUBPIX` refines corner positions to sub-pixel accuracy — reduces distance error by ~5% at no meaningful performance cost.

Intrinsic matrix transpose: `.columns[i]` of `simd_float3x3` is the i-th column; OpenCV needs row-major layout. The `.mm` file transposes element by element when building `cameraMatrix`.

---

### `Data/Detection/OpenCVMarkerDetectionRepository.swift`

Swift adapter conforming `ArucoDetector` (Obj-C) to `MarkerDetectionRepository` (Domain protocol).

```swift
func detectMarkers(in frame: CameraFrame, markerSideMeters: Double) async -> [MarkerDetection] {
    let results = detector.detect(in: frame.pixelBuffer,
                                  intrinsicMatrix: frame.intrinsics,
                                  markerSideMeters: markerSideMeters)
    return results.map { r in
        MarkerDetection(id: r.markerId,
                        cornersInImageSpace: [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft],
                        imageSize: r.imageSize,
                        distanceMeters: r.distanceMeters)
    }
}
```

The Domain layer never imports `ArucoDetector`.

---

### `Data/Permission/AVCaptureDevicePermissionRepository.swift`

Bridges `AVCaptureDevice.authorizationStatus(for: .video)` and `AVCaptureDevice.requestAccess(for: .video)` to the `CameraPermissionRepository` protocol. The `requestAccess` call suspends until the user responds to the system dialog.

---

## Presentation layer

### `Presentation/ViewModels/CameraViewModel.swift`

`@MainActor final class` conforming to `ObservableObject`. All `@Published` mutations happen on the main actor — SwiftUI observes safely.

State:
- `detections: [MarkerDetection]` — current frame's detections, drives the overlay
- `permissionStatus: CameraPermissionStatus` — drives which screen shows
- `previewSession: AVCaptureSession` — passed to `CameraPreviewView`

Lifecycle:
```
onAppear()
  └── check permission
        ├── .authorized → configure() + start() + detectionTask
        └── other → show permission UI

requestPermission()
  └── await permissionUseCase.requestPermission()
        └── if .authorized → startCaptureIfNeeded()

onDisappear()
  └── detectionTask.cancel() + Task { await stop() }
```

The detection task runs on `@MainActor` (because `CameraViewModel` is `@MainActor`), but the body suspends at `for await` — actual detection work happens in `Task.detached` inside `DefaultDetectMarkersUseCase`. The `[weak self]` capture prevents the task from keeping the ViewModel alive indefinitely if the view disappears.

---

### `Presentation/Views/CameraScreenContainer.swift`

The only View that knows `CameraViewModel` exists. Holds `@ObservedObject var viewModel: CameraViewModel` and forwards state and callbacks to `CameraScreenView` as plain init parameters.

This is the adapter boundary: ViewModel interface changes affect only this file. `CameraScreenView` stays stable.

---

### `Presentation/Views/CameraScreenView.swift`

Pure view. Takes permission status, preview session, detections, and four callbacks as init parameters. No ViewModel, no `@StateObject`, no `@EnvironmentObject`.

```swift
switch permissionStatus {
case .authorized:             CameraContentView(session:, detections:)
case .notDetermined:          PermissionRequestView(onRequest:)
case .denied, .restricted:    PermissionDeniedView(onOpenSettings:)
}
```

Because it's pure, it can be previewed in Xcode with synthetic state without a real camera or ViewModel.

---

### `Presentation/Views/CameraContentView.swift`

Composes the live preview and detection overlay in a `ZStack`:

```
ZStack
  ├── CameraPreviewView(session:)      .ignoresSafeArea()   (video, bottom layer)
  └── DetectionOverlayView(detections:) .ignoresSafeArea()  (contour + label, top)
```

---

### `Presentation/Views/DetectionOverlayView.swift`

Pure SwiftUI view. Uses `Canvas` (GPU-accelerated, no UIView backing) to draw the green contour and distance label.

**Image → view coordinate mapping:** camera outputs 720×1280 pixels; the view is a different size and aspect ratio. `mapImagePoint(_:imageSize:viewSize:)` computes the aspect-fill scale and centering offset so corners land in the right screen position.

Per-marker drawing:
1. Build a `Path` from the 4 corners (TL → TR → BR → BL → close)
2. `context.stroke(path, with: .color(#00FF6A), lineWidth: 4)`
3. Filled 12×12 circle at the top-left corner

Distance label: SF Pro Rounded 28pt, white, on a black capsule (opacity 0.55), anchored at the bottom.

No animations — any easing introduces visible lag at 30 fps.

---

### `Presentation/UIKit/CameraPreviewUIView.swift`

A `UIView` subclass whose `layerClass` is `AVCaptureVideoPreviewLayer`. The only way to get hardware-accelerated, zero-copy camera preview — SwiftUI `Canvas` can't render a live feed without copying pixels per frame, which kills real-time performance.

`attach(session:)` wires the session to the preview layer and sets portrait rotation via `#available(iOS 17.0, *)` / fallback.

---

### `Presentation/UIKit/CameraPreviewView.swift`

A `UIViewRepresentable` hosting `CameraPreviewUIView` in SwiftUI. `makeUIView` calls `attach(session:)`; `updateUIView` is a no-op because the session reference doesn't change at runtime.

---

### `Presentation/Views/PermissionRequestView.swift`

Shown when `permissionStatus == .notDetermined`. Single "Allow Camera" button that calls `onRequest()`. Pure — has no idea what `onRequest()` does.

---

### `Presentation/Views/PermissionDeniedView.swift`

Shown when `permissionStatus == .denied` or `.restricted`. "Open Settings" button deep-links to `UIApplication.openSettingsURLString`.

---

## Communication diagram

```
                    ┌──────────────────┐
                    │ AVFoundation     │
                    │ (cameraQueue)    │
                    └────────┬─────────┘
                             │ CMSampleBuffer (every frame)
                             ▼
               AVFoundationCameraRepository
                    │  extract intrinsics
                    │  build CameraFrame
                    │  yield → frames AsyncStream
                             │
                    ┌────────┘ Task.detached (background)
                    ▼
       DefaultDetectMarkersUseCase
                    │  for await frame in frames
                    │  await detectMarkers(in: frame)
                             │
                    ┌────────┘
                    ▼
       OpenCVMarkerDetectionRepository
                    │  ArucoDetector.mm (sync)
                    │    lock pixel buffer
                    │    BGRA → gray
                    │    detectMarkers()
                    │    solvePnP() → tvec → distance
                    │  map to [MarkerDetection]
                    │
                    └──── continuation.yield([MarkerDetection])
                             │
                    ┌────────┘ @MainActor hop
                    ▼
            CameraViewModel
                    │  @Published detections = newDetections
                    │
            ┌───────┘ SwiftUI re-render
            ▼
  CameraScreenContainer (@ObservedObject)
            │  forward values to CameraScreenView
            ▼
  CameraScreenView → CameraContentView → DetectionOverlayView
                                             │  Canvas draws contour + label
                                             ▼
                                        iPhone screen
```

**Parallel GPU path:** `AVCaptureVideoPreviewLayer` (inside `CameraPreviewUIView`) renders the live video feed independently via Metal/CoreAnimation — it never goes through Swift. The detection overlay is composited on top by SwiftUI.

---

## Threading summary

| Thread / Queue | Runs there |
|---|---|
| `cameraQueue` (serial, `.userInteractive`) | AVFoundation delegate, `AsyncStream.yield`, `start/stop/configure` |
| Cooperative thread pool (`Task.detached`) | Detection loop, OpenCV `solvePnP` |
| `@MainActor` | `@Published` updates, all SwiftUI rendering |
| GPU (Metal / CoreAnimation) | `AVCaptureVideoPreviewLayer`, SwiftUI `Canvas` compositing |

Frame drops happen at two points: `alwaysDiscardsLateVideoFrames = true` (AVFoundation drops before the delegate fires) and `bufferingPolicy: .bufferingNewest(1)` (detection stream drops if the consumer is still on the previous frame).
