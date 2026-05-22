import AVFoundation
import Combine
import Foundation

@MainActor
final class CameraViewModel: ObservableObject {

    @Published private(set) var detections: [MarkerDetection] = []
    @Published private(set) var permissionStatus: CameraPermissionStatus

    /// Exposed only so the preview UIView can wire AVCaptureVideoPreviewLayer to it.
    /// This is a leak we accept; documented in CameraFeedRepository.
    let previewSession: AVCaptureSession

    private let detectMarkersUseCase: DetectMarkersUseCase
    private let cameraSessionUseCase: CameraSessionUseCase
    private let permissionUseCase: CameraPermissionUseCase

    private var detectionTask: Task<Void, Never>?
    private var didConfigureSession = false

    init(
        previewSession: AVCaptureSession,
        initialPermission: CameraPermissionStatus,
        detectMarkersUseCase: DetectMarkersUseCase,
        cameraSessionUseCase: CameraSessionUseCase,
        permissionUseCase: CameraPermissionUseCase
    ) {
        self.previewSession = previewSession
        self.permissionStatus = initialPermission
        self.detectMarkersUseCase = detectMarkersUseCase
        self.cameraSessionUseCase = cameraSessionUseCase
        self.permissionUseCase = permissionUseCase
    }

    func onAppear() async {
        permissionStatus = permissionUseCase.currentStatus()
        if permissionStatus == .authorized {
            await startCaptureIfNeeded()
        }
    }

    func requestPermission() async {
        permissionStatus = await permissionUseCase.requestPermission()
        if permissionStatus == .authorized {
            await startCaptureIfNeeded()
        }
    }

    func onDisappear() {
        detectionTask?.cancel()
        detectionTask = nil
        Task { await cameraSessionUseCase.stop() }
    }

    private func startCaptureIfNeeded() async {
        if !didConfigureSession {
            do {
                try await cameraSessionUseCase.configure()
                didConfigureSession = true
            } catch {
                // Camera unavailable. permissionStatus remains as-is; UI will show empty preview.
                // For a production app, surface this as an error state on the VM.
                return
            }
        }
        await cameraSessionUseCase.start()

        detectionTask?.cancel()
        detectionTask = Task { [weak self] in
            guard let self else { return }
            for await newDetections in self.detectMarkersUseCase.detections() {
                if Task.isCancelled { break }
                self.detections = newDetections
            }
        }
    }
}
