protocol CameraPermissionRepository: Sendable {
    func currentStatus() -> CameraPermissionStatus
    func requestPermission() async -> CameraPermissionStatus
}
