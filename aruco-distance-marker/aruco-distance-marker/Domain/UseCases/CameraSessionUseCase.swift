protocol CameraSessionUseCase: Sendable {
    nonisolated func configure() async throws
    nonisolated func start() async
    nonisolated func stop() async
}

final class DefaultCameraSessionUseCase: CameraSessionUseCase {
    // nonisolated let: CameraFeedRepository is Sendable so it's safe to read from
    // any isolation context — required because configure/start/stop are nonisolated.
    nonisolated private let cameraRepository: CameraFeedRepository

    init(cameraRepository: CameraFeedRepository) {
        self.cameraRepository = cameraRepository
    }

    nonisolated func configure() async throws {
        try await cameraRepository.configure()
    }
    nonisolated func start() async { await cameraRepository.start() }
    nonisolated func stop() async  { await cameraRepository.stop() }
}
