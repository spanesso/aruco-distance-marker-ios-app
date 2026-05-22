import AVFoundation

/// Source of camera frames and provider of the preview session.
///
/// Note on the leaky abstraction: `previewSession` is intentionally an AVCaptureSession
/// because SwiftUI/UIKit preview layers MUST be wired to this concrete type for
/// hardware-accelerated zero-copy rendering. We do not abstract it further.
protocol CameraFeedRepository: Sendable {
    /// Async stream of frames; bufferingNewest(1) — late frames are dropped.
    /// `nonisolated`: must be accessible from Task.detached without a MainActor hop.
    nonisolated var frames: AsyncStream<CameraFrame> { get }
    /// The session to wire into AVCaptureVideoPreviewLayer for preview.
    var previewSession: AVCaptureSession { get }

    nonisolated func configure() async throws
    nonisolated func start() async
    nonisolated func stop() async
}
