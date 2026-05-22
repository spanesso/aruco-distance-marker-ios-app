import CoreGraphics
import Foundation

/// Result of a single ArUco marker detection.
/// Pure value type — no framework dependencies.
struct MarkerDetection: Identifiable, Equatable, Sendable {
    let id: Int
    /// Four corners in image-buffer pixel space (origin top-left).
    /// Order: top-left, top-right, bottom-right, bottom-left.
    let cornersInImageSpace: [CGPoint]
    /// Size of the source image buffer in pixels.
    let imageSize: CGSize
    /// Camera-to-marker distance, in meters.
    let distanceMeters: Double

    var distanceCentimeters: Double { distanceMeters * 100.0 }
}
