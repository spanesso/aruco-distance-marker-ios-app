# Source File Guide

If you're new to the project or to iOS in general, this document walks through what each file does and why it exists. It follows the path data takes through the app — from the moment the camera captures a frame to the distance number appearing on screen.

---

## First: the four layers

The project is split into four folders that represent four separate worlds:

```
App/            Entry point. Connects everything at startup.
Domain/         App rules. No UIKit, AVFoundation, or OpenCV imports.
Data/           Where the real technical code lives: camera, OpenCV, permissions.
Presentation/   What the user sees. Pure SwiftUI.
```

The most important rule: **Domain knows nothing about the other three**. If you ever replace AVFoundation with another camera library, you only touch `Data/`. The Domain doesn't know. Neither does the UI.

This feels like bureaucracy at first, but makes a lot of sense once the project grows.

---

## App/

### `aruco_distance_markerApp.swift`

The app's entry point. iOS runs this first.

It does one thing: creates the `CameraViewModel` (through `CompositionRoot`) and stores it with `@StateObject`. That `@StateObject` matters — it guarantees the ViewModel lives for the entire app session, not destroyed every time SwiftUI redraws the screen.

```swift
@main
struct aruco_distance_markerApp: App {
    @StateObject private var cameraViewModel: CameraViewModel

    init() {
        let composer = CompositionRoot()
        _cameraViewModel = StateObject(wrappedValue: composer.makeCameraViewModel())
    }
}
```

One rule enforced throughout the project: **`@StateObject` is only used here**. No other View creates a ViewModel with `@StateObject`. This prevents SwiftUI from destroying and recreating the ViewModel mid-stream when it rebuilds its view hierarchy, which would kill the camera session.

---

### `CompositionRoot.swift`

The project's factory. The only place where concrete objects are created and connected.

When `makeCameraViewModel()` is called, it builds the full dependency graph in order:

1. `AVFoundationCameraRepository` — real camera access
2. `OpenCVMarkerDetectionRepository` — OpenCV-based marker detector
3. `AVCaptureDevicePermissionRepository` — permission handling
4. The three use cases, each receiving the repositories they need
5. `CameraViewModel` with everything wired up

Without this file, every object would have to create its own dependencies, making changes a cascade of modifications. With the factory, swapping out the detection implementation is a one-line change here — nothing else notices.

This pattern is called **Dependency Injection**: instead of `CameraViewModel` creating its own detector, it receives one through its initializer. The ViewModel only knows the protocol (the interface), not the concrete implementation.

---

## Domain/

This layer imports only `Foundation`, `CoreGraphics`, and `simd`. No UIKit, AVFoundation, SwiftUI, or OpenCV. It's the layer we care most about keeping pure.

### `ArucoConfig.swift`

An empty enum that acts as a control panel. Every value you'd reasonably want to tune is here:

| Constant | Value | Purpose |
|---|---|---|
| `markerSideMeters` | `0.10` | Physical size of the marker. **If the distance is wrong, this is what you change.** |
| `dictionary` | `.dict4x4_50` | The ArUco dictionary the detector uses |
| `expectedMarkerId` | `0` | Documentation — the detector reports whatever it finds |

Using a caseless `enum` (rather than a struct or global variables) means Swift guarantees nobody can instantiate `ArucoConfig`. It's just a namespace for constants.

---

### `Domain/Entities/CameraFrame.swift`

A data package representing one camera frame with everything needed to analyze it:

```
CameraFrame
  ├── pixelBuffer   The frame's pixels (raw BGRA)
  ├── intrinsics    The camera calibration matrix
  ├── imageSize     Width × height in pixels (1280 × 720)
  └── timestamp     When it was captured
```

The least obvious part is `intrinsics`. Think of the camera as a mathematical funnel. The intrinsic matrix describes that funnel: how much "zoom" it has (focal length) and where the optical center sits. Without this, OpenCV can only see pixels — not meters. iOS delivers it for free, calibrated per individual unit at the factory.

`CVPixelBuffer` is `@MainActor` in the iOS 26 SDK, so `nonisolated(unsafe)` lets us access the buffer from the camera queue. It's read-only after creation, so there's no real race condition risk despite the annotation.

---

### `Domain/Entities/MarkerDetection.swift`

The result of detecting a marker. What comes out of OpenCV and travels all the way to the screen:

```
MarkerDetection
  ├── id                  Marker number (0, 1, 5...)
  ├── cornersInImageSpace 4 corners in pixels [TL, TR, BR, BL]
  ├── imageSize           Resolution of the image it was detected in
  ├── distanceMeters      Distance in meters
  └── distanceCentimeters Same in cm (computed property, just × 100)
```

`imageSize` is stored alongside the corners because the overlay view needs it to scale from image coordinates to screen coordinates. Without it, the view would need to know the camera resolution from somewhere else.

---

### `Domain/Entities/ArucoDictionary.swift`

An enum listing the available ArUco dictionaries, mapping each name to the integer OpenCV expects internally.

```swift
enum ArucoDictionary: Int {
    case dict4x4_50  = 0   // 0 is what gets passed to OpenCV
    case dict4x4_100 = 1
    // ...
}
```

Without this enum, call sites would have magic numbers like `0` or `8` with no context. With it, the code says `dictionary: .dict4x4_50` and it's clear.

---

### `Domain/Entities/CameraPermissionStatus.swift`

The four possible camera permission states on iOS:

```
.notDetermined  The user hasn't responded yet
.authorized     They tapped Allow
.denied         They tapped Don't Allow
.restricted     Device has restrictions (parental controls, MDM, etc.)
```

This exists to avoid importing `AVFoundation` from the Presentation layer. If `CameraScreenView` used `AVAuthorizationStatus` directly, it would depend on AVFoundation — violating the layer rule. This enum acts as a neutral translator.

---

### `Domain/Repositories/` (the three protocols)

Three protocols live here: `CameraFeedRepository`, `MarkerDetectionRepository`, and `CameraPermissionRepository`. Each defines what the app expects any concrete implementation to provide.

A protocol is a contract: "whoever wants to be a camera source has to be able to do this." The protocol says nothing about how — only what. The concrete implementation in `Data/` handles the how.

```swift
protocol CameraFeedRepository: Sendable {
    var frames: AsyncStream<CameraFrame> { get }
    func configure() async throws
    func start() async
    func stop() async
}
```

If you ever want to replace AVFoundation with another camera library, you create a new class that satisfies `CameraFeedRepository`, plug it into `CompositionRoot`, and nothing else in the codebase changes.

---

### `Domain/UseCases/CameraSessionUseCase.swift`

Manages the camera session lifecycle: `configure()`, `start()`, `stop()`. `DefaultCameraSessionUseCase` is a thin delegator — it calls through to the repository.

It exists so `CameraViewModel` depends on a protocol, not a concrete class. That boundary is also where you'd add retry logic, timeout handling, or format negotiation later — without touching the ViewModel or the AVFoundation repo.

---

### `Domain/UseCases/DetectMarkersUseCase.swift`

The most important use case. It joins the frame stream with the detector to produce a continuous `AsyncStream<[MarkerDetection]>`.

What it does internally:

```
detections() → AsyncStream<[MarkerDetection]>
  └─ Task.detached (background thread, never main)
       └─ for await frame in cameraRepository.frames
              └─ await detectMarkers(in: frame)   (~5–20ms with OpenCV)
                     └─ continuation.yield(results)
```

`AsyncStream` is essentially an asynchronous data river. The consumer uses `for await` to receive one element each time the producer emits one. If the producer (camera) runs faster than the consumer (detection), `bufferingPolicy: .bufferingNewest(1)` drops the previous result and keeps only the latest. The app never builds a lag queue.

---

### `Domain/UseCases/CameraPermissionUseCase.swift`

Checks and requests camera permission. `DefaultCameraPermissionUseCase` delegates to `CameraPermissionRepository`. Straightforward.

---

## Data/

The "plumbing" — code that touches real hardware, Apple APIs, and OpenCV.

### `Data/Camera/AVFoundationCameraRepository.swift`

The real `CameraFeedRepository` implementation using AVFoundation. Inherits from `NSObject` because `AVCaptureVideoDataOutputSampleBufferDelegate` requires it.

Internally there's a serial queue called `cameraQueue`. AVFoundation delivers frames on its own background thread, and you need to make sure nothing else touches the session at the same time. The serial queue acts as a gatekeeper: one operation at a time.

`configure()` handles one-time setup: back wide-angle camera, 720p BGRA format, intrinsics enabled, portrait orientation.

`captureOutput(_:didOutput:from:)` is what iOS calls automatically for each frame (up to 30 times per second). It extracts the `CVPixelBuffer`, reads the intrinsic matrix, packages everything into a `CameraFrame`, and sends it to the stream with `framesContinuation.yield(frame)`.

BGRA format isn't arbitrary: `cvtColor(BGRA→GRAY)` in OpenCV is a single vectorized pass. YUV420 would need two steps and is slower.

---

### `Data/Camera/CameraIntrinsicsExtractor.swift`

A utility with two static methods:

**`extract(from: CMSampleBuffer)`** — reads `kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix` from the sample buffer. Apple attaches the factory-calibrated matrix to every frame as a `Data` blob containing a `simd_float3x3`. This method unpacks it.

**`approximated(device:, imageSize:)`** — fallback for very old devices. Estimates from the camera's field of view: `fx = width / (2 × tan(fov / 2))`. Introduces ~5–15% error but lets the app function on more hardware.

One detail that's easy to miss: `simd_float3x3` is column-major (`.columns[i]` is the i-th column), but OpenCV expects row-major. The matrix gets transposed in `ArucoDetector.mm` when building `cameraMatrix`.

---

### `Data/Detection/ArucoDetector.h`

The Objective-C header defining the detector interface — the gateway between Swift and C++/OpenCV.

Swift can't import C++ directly. The classic iOS solution is an Objective-C++ class in the middle. The `.h` defines what it can do:

```objc
@interface ArucoDetector : NSObject
- (instancetype)initWithDictionaryType:(NSInteger)dictionaryType;
- (NSArray<ArucoDetectionResult *> *)detectInPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                         intrinsicMatrix:(simd_float3x3)intrinsicMatrix
                                        markerSideMeters:(double)markerSideMeters;
@end
```

Also defines `ArucoDetectionResult` — the Objective-C object carrying the 4 corners and distance for each detected marker.

Objective-C++ (`.mm` files) can mix Objective-C with C++. That's what lets us call OpenCV from Swift.

---

### `Data/Detection/ArucoDetector.mm`

The Objective-C++ implementation. All real OpenCV code lives here.

**OpenCV headers go first, before anything from Apple.** Apple defines the macros `NO` and `YES` (as `false`/`true`). Some OpenCV files use `NO` as a C++ variable name. If Apple's macros land first, OpenCV fails to compile. The include order is not optional.

What happens on each detection call:

```
1. Lock the pixel buffer (safe read access)
2. Wrap pixels in cv::Mat without copying
3. Convert BGRA → grayscale
4. Unlock the buffer
5. _detector.detectMarkers(gray, corners, ids)
6. For each detected marker:
   a. Define 4 points in real-world coordinates (in meters, centered at origin)
   b. cv::solvePnP() → rvec, tvec
   c. distance = √(tx² + ty² + tz²)
7. Return array of ArucoDetectionResult
```

`solvePnP` answers: "if I know where these 4 points are in the real world (in meters) and I see them at these positions in the image (in pixels), how far away is the object and at what angle?" The result `tvec = (tx, ty, tz)` is the translation vector from camera to marker, and its length is the distance.

`CORNER_REFINE_SUBPIX` refines detected corners to sub-pixel accuracy, reducing distance error by ~5% at no meaningful performance cost.

---

### `Data/Detection/OpenCVMarkerDetectionRepository.swift`

The Swift adapter that wraps `ArucoDetector` (Obj-C) and makes it conform to `MarkerDetectionRepository` (Domain protocol).

```swift
func detectMarkers(in frame: CameraFrame, markerSideMeters: Double) async -> [MarkerDetection] {
    let results = detector.detect(in: frame.pixelBuffer, ...)
    return results.map { r in
        MarkerDetection(id: r.markerId,
                        cornersInImageSpace: [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft],
                        imageSize: r.imageSize,
                        distanceMeters: r.distanceMeters)
    }
}
```

Converts `ArucoDetectionResult` (Obj-C) to `MarkerDetection` (Domain entity). The Domain never knows OpenCV exists.

---

### `Data/Permission/AVCaptureDevicePermissionRepository.swift`

The real camera permission implementation:

- `currentStatus()` calls `AVCaptureDevice.authorizationStatus(for: .video)` and translates to `CameraPermissionStatus`
- `requestPermission()` calls `AVCaptureDevice.requestAccess(for: .video)`, which shows the iOS system dialog and waits. The `await` suspends until the user makes a choice — could be several seconds

---

## Presentation/

Only what the user sees. No AVFoundation or OpenCV imports here — it works entirely with Domain types.

### `Presentation/ViewModels/CameraViewModel.swift`

The UI brain. `@MainActor` guarantees all `@Published` updates happen on the main thread, which is what SwiftUI requires.

Published state:

```swift
@Published var detections: [MarkerDetection]          // current markers
@Published var permissionStatus: CameraPermissionStatus  // which screen to show
let previewSession: AVCaptureSession                  // for the camera preview
```

Lifecycle in pseudocode:

```
onAppear()
  ├─ have permission?
  │   ├─ yes → configure() + start() + start detection loop
  │   └─ no  → show permission screen

requestPermission()
  └─ ask for permission → if granted → configure() + start() + loop

onDisappear()
  └─ cancel loop → stop()
```

The detection loop:

```swift
detectionTask = Task { [weak self] in
    for await newDetections in self.detectMarkersUseCase.detections() {
        self.detections = newDetections
    }
}
```

The `[weak self]` prevents a retain cycle: without it, the task holds the ViewModel and the ViewModel holds the task, and neither would ever be released.

---

### `Presentation/Views/CameraScreenContainer.swift`

The only View that knows `CameraViewModel` exists. It holds `@ObservedObject var viewModel: CameraViewModel` and forwards everything to `CameraScreenView` as plain init parameters.

If the ViewModel's interface changes, only this file needs updating. The rest of the views stay untouched.

---

### `Presentation/Views/CameraScreenView.swift`

The main screen in "pure" form. All dependencies come in through the `init` — no `@StateObject`, no `@EnvironmentObject`, no global access.

Decides what to show based on permission:

```swift
switch permissionStatus {
case .authorized:          CameraContentView(...)
case .notDetermined:       PermissionRequestView(...)
case .denied, .restricted: PermissionDeniedView(...)
}
```

Because it's pure, it can be previewed in Xcode with any synthetic state without a real camera:

```swift
#Preview("No permission") {
    CameraScreenView(
        permissionStatus: .notDetermined,
        previewSession: AVCaptureSession(),
        detections: [],
        onAppear: {}, onRequestPermission: {}, onOpenSettings: {}, onDisappear: {}
    )
}
```

---

### `Presentation/Views/CameraContentView.swift`

The active camera screen. A `ZStack` with two layers: the live video preview at the bottom, the detection overlay on top. Both use `.ignoresSafeArea()` to cover the full screen including the notch.

---

### `Presentation/Views/DetectionOverlayView.swift`

Draws the green contour and the distance number over the video.

Uses SwiftUI's `Canvas` — a GPU-accelerated vector drawing surface. No `UIView` backing needed. For each detected marker:

1. **Maps coordinates:** corners arrive in image pixels (1280×720). The screen is a different size. `mapImagePoint()` computes the scale factor and offset so the contour lands in the right place.

2. **Draws the contour:** a `Path` through the 4 corners, stroked in `#00FF6A` at lineWidth 4.

3. **Draws the reference dot:** a 12 px filled circle at the top-left corner.

4. **Shows the distance:** white SF Pro Rounded 28pt text on a black semi-transparent capsule, anchored at the bottom of the screen.

No animations. At 30 fps any easing on appear/disappear introduces visible lag. The overlay snaps in and out instantly.

---

### `Presentation/UIKit/CameraPreviewUIView.swift`

A `UIView` subclass whose backing layer is `AVCaptureVideoPreviewLayer`. This is where the live video actually appears on screen.

Why UIKit and not SwiftUI for this? Because `AVCaptureVideoPreviewLayer` processes frames directly on the GPU, never touching CPU or Swift. There's no SwiftUI equivalent — rendering video by converting each frame to a SwiftUI `Image` would miss real-time performance entirely. UIKit is the only option here.

`attach(session:)` connects the capture session and sets portrait orientation with a version guard:

```swift
if #available(iOS 17.0, *) {
    connection.videoRotationAngle = 90   // iOS 17+
} else {
    connection.videoOrientation = .portrait  // iOS 15-16
}
```

---

### `Presentation/UIKit/CameraPreviewView.swift`

The UIKit-to-SwiftUI bridge. A `UIViewRepresentable` wrapping `CameraPreviewUIView` so SwiftUI can use it like any other view.

- `makeUIView()` — called once, creates the UIView and connects it to the session
- `updateUIView()` — empty, since the session reference doesn't change at runtime

Thanks to this file, `CameraContentView` can simply write `CameraPreviewView(session: session)` as if it were a native SwiftUI view.

---

### `Presentation/Views/PermissionRequestView.swift` and `PermissionDeniedView.swift`

Two simple views for the permission states.

`PermissionRequestView` appears the first time, before the user has responded. Has one button that calls `onRequest()`.

`PermissionDeniedView` appears if the user already denied permission. Its button opens the app's Settings screen directly (`UIApplication.openSettingsURLString`) so the user can re-enable it manually.

Both are pure: they don't know what their callback does, they just call it.

---

### `Support/Info.plist`

The app configuration file iOS reads at install and launch. Key entries:

| Key | Purpose |
|---|---|
| `NSCameraUsageDescription` | The text the user sees in the camera permission dialog |
| `UISupportedInterfaceOrientations` | Portrait only — no rotation |
| `UIRequiresFullScreen` | Disables split-screen on iPad; exempts from needing a LaunchScreen |
| `CFBundleIdentifier` | The app's unique ID. Uses `$(PRODUCT_BUNDLE_IDENTIFIER)` — Xcode substitutes this at build time |

Values with `$(...)` are Build Settings variables that Xcode expands automatically. If you see "CFBundleIdentifier missing" during install, it means this key wasn't added here — it happens because `GENERATE_INFOPLIST_FILE = NO`.

---

### `aruco-distance-marker-Bridging-Header.h`

One line:

```objc
#import "ArucoDetector.h"
```

This lets all Swift code in the project use `ArucoDetector` and `ArucoDetectionResult` as if they were Swift types. Configured in Build Settings under `Swift Objective-C Bridging Header`.

---

## Full frame journey

```
Camera hardware
    ↓  30 fps
AVFoundationCameraRepository.captureOutput()     [cameraQueue]
    ↓  packages pixelBuffer + intrinsics → CameraFrame
    ↓  framesContinuation.yield(frame)

DefaultDetectMarkersUseCase                      [Task.detached]
    ↓  for await frame in frames
    ↓  await detectMarkers(in: frame)

OpenCVMarkerDetectionRepository
    ↓  ArucoDetector.mm:
    ↓    BGRA → grayscale → detectMarkers → solvePnP → distance
    ↓  [ArucoDetectionResult] → [MarkerDetection]
    ↓  continuation.yield([MarkerDetection])

CameraViewModel                                  [@MainActor]
    ↓  self.detections = newDetections

CameraScreenContainer → CameraScreenView → CameraContentView
    ↓
DetectionOverlayView: Canvas draws green contour + distance label
    ↓
iPhone screen
```

Running in parallel, independent of all the above:

```
AVCaptureVideoPreviewLayer                       [GPU, never touches Swift]
    →  live video directly to screen
```
