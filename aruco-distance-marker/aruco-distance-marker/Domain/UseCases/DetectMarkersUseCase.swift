import Foundation

protocol DetectMarkersUseCase: Sendable {
    /// Stream of detection arrays — one emission per processed frame.
    func detections() -> AsyncStream<[MarkerDetection]>
}

final class DefaultDetectMarkersUseCase: DetectMarkersUseCase {
    private let cameraRepository: CameraFeedRepository
    private let detectionRepository: MarkerDetectionRepository
    private let markerSideMeters: Double

    init(
        cameraRepository: CameraFeedRepository,
        detectionRepository: MarkerDetectionRepository,
        markerSideMeters: Double
    ) {
        self.cameraRepository = cameraRepository
        self.detectionRepository = detectionRepository
        self.markerSideMeters = markerSideMeters
    }

    func detections() -> AsyncStream<[MarkerDetection]> {
        AsyncStream<[MarkerDetection]>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let cameraRepository = self.cameraRepository
            let detectionRepository = self.detectionRepository
            let markerSideMeters = self.markerSideMeters

            let task = Task.detached(priority: .userInitiated) {
                for await frame in cameraRepository.frames {
                    if Task.isCancelled { break }
                    let results = await detectionRepository.detectMarkers(
                        in: frame,
                        markerSideMeters: markerSideMeters
                    )
                    continuation.yield(results)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
