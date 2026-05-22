import CoreGraphics
import Foundation

/// Adapts the Obj-C++ ArucoDetector bridge to the Domain MarkerDetectionRepository protocol.
///
/// `@unchecked Sendable`: ArucoDetector is an immutable Obj-C class after init;
/// detection is internally serialized inside the .mm via OpenCV's own behavior.
final class OpenCVMarkerDetectionRepository: MarkerDetectionRepository, @unchecked Sendable {
    private let detector: ArucoDetector

    init(dictionary: ArucoDictionary) {
        self.detector = ArucoDetector(dictionaryType: dictionary.rawValue)
    }

    func detectMarkers(
        in frame: CameraFrame,
        markerSideMeters: Double
    ) async -> [MarkerDetection] {
        // Synchronous call into OpenCV. Runs on whatever task invoked us
        // (typically the detection task from DefaultDetectMarkersUseCase).
        let results = detector.detect(
            in: frame.pixelBuffer,
            intrinsicMatrix: frame.intrinsics,
            markerSideMeters: markerSideMeters
        )

        return results.map { r in
            MarkerDetection(
                id: r.markerId,
                cornersInImageSpace: [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft],
                imageSize: r.imageSize,
                distanceMeters: r.distanceMeters
            )
        }
    }
}
