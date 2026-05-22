import CoreGraphics
import CoreMedia
import CoreVideo
import simd

/// A single frame from the camera, with its calibration metadata.
///
/// `@unchecked Sendable` because CVPixelBuffer is a CoreFoundation reference type
/// that Swift can't auto-verify; in practice we read it once per frame and never
/// share mutation, so cross-isolation transfer is safe.
struct CameraFrame: @unchecked Sendable {
    // CVPixelBuffer is @MainActor in iOS 26 SDK; nonisolated(unsafe) since the buffer
    // is read-only after creation and all access is serialised through cameraQueue.
    nonisolated(unsafe) let pixelBuffer: CVPixelBuffer
    /// Camera intrinsic matrix (column-major), in pixels.
    let intrinsics: simd_float3x3
    let imageSize: CGSize
    let timestamp: CMTime

    // Explicit nonisolated init: CVPixelBuffer is @MainActor in the iOS 26 SDK,
    // which would infer the memberwise init as @MainActor. We override that here
    // since CameraFrame is created on cameraQueue, not on MainActor.
    nonisolated init(
        pixelBuffer: CVPixelBuffer,
        intrinsics: simd_float3x3,
        imageSize: CGSize,
        timestamp: CMTime
    ) {
        self.pixelBuffer = pixelBuffer
        self.intrinsics = intrinsics
        self.imageSize = imageSize
        self.timestamp = timestamp
    }
}
