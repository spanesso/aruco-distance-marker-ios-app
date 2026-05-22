protocol CameraPermissionUseCase: Sendable {
    func currentStatus() -> CameraPermissionStatus
    func requestPermission() async -> CameraPermissionStatus
}

final class DefaultCameraPermissionUseCase: CameraPermissionUseCase {
    private let repository: CameraPermissionRepository

    init(repository: CameraPermissionRepository) {
        self.repository = repository
    }

    func currentStatus() -> CameraPermissionStatus { repository.currentStatus() }
    func requestPermission() async -> CameraPermissionStatus { await repository.requestPermission() }
}
