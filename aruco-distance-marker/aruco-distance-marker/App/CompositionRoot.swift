import Foundation

@MainActor
struct CompositionRoot {

    func makeCameraViewModel() -> CameraViewModel {
        let cameraRepository = AVFoundationCameraRepository()
        let detectionRepository = OpenCVMarkerDetectionRepository(
            dictionary: ArucoConfig.dictionary
        )
        let permissionRepository = AVCaptureDevicePermissionRepository()

        let detectMarkersUseCase = DefaultDetectMarkersUseCase(
            cameraRepository: cameraRepository,
            detectionRepository: detectionRepository,
            markerSideMeters: ArucoConfig.markerSideMeters
        )
        let cameraSessionUseCase = DefaultCameraSessionUseCase(
            cameraRepository: cameraRepository
        )
        let permissionUseCase = DefaultCameraPermissionUseCase(
            repository: permissionRepository
        )

        return CameraViewModel(
            previewSession: cameraRepository.previewSession,
            initialPermission: permissionUseCase.currentStatus(),
            detectMarkersUseCase: detectMarkersUseCase,
            cameraSessionUseCase: cameraSessionUseCase,
            permissionUseCase: permissionUseCase
        )
    }
}
