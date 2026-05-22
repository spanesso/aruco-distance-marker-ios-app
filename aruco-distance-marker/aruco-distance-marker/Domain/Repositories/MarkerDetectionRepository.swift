protocol MarkerDetectionRepository: Sendable {
    /// Detects ArUco markers in the given frame.
    /// Pure function: no internal state, no side effects.
    func detectMarkers(
        in frame: CameraFrame,
        markerSideMeters: Double
    ) async -> [MarkerDetection]
}
