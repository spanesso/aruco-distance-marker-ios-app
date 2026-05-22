import AVFoundation
import CoreMedia
import Foundation
import simd

/// AVFoundation-backed CameraFeedRepository.
///
/// `@unchecked Sendable`: this class owns a private serial queue (`cameraQueue`).
/// All mutable state is touched only on that queue.
///
/// `nonisolated` methods/properties: NSObject is @MainActor in the iOS 26 SDK, which
/// would make the entire class @MainActor. We opt individual members out so they can
/// run on `cameraQueue` without actor-hop overhead.
final class AVFoundationCameraRepository: NSObject, CameraFeedRepository, @unchecked Sendable {

    // AsyncStream is Sendable; `nonisolated` is valid and lets Task.detached consumers
    // iterate without a MainActor hop.
    nonisolated let frames: AsyncStream<CameraFrame>
    nonisolated private let framesContinuation: AsyncStream<CameraFrame>.Continuation

    // AVFoundation types are @MainActor in iOS 26 SDK; nonisolated(unsafe) since all
    // access is serialised through cameraQueue.
    nonisolated(unsafe) let previewSession = AVCaptureSession()
    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private var device: AVCaptureDevice?

    private let cameraQueue = DispatchQueue(
        label: "com.spanesso.ArucoDistance.camera",
        qos: .userInteractive
    )

    override init() {
        var continuation: AsyncStream<CameraFrame>.Continuation!
        self.frames = AsyncStream<CameraFrame>(
            bufferingPolicy: .bufferingNewest(1)
        ) { c in continuation = c }
        self.framesContinuation = continuation
        super.init()
    }

    nonisolated func configure() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            cameraQueue.async { [self] in
                do {
                    try configureSession()
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    nonisolated func start() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            cameraQueue.async { [self] in
                if !previewSession.isRunning { previewSession.startRunning() }
                cont.resume()
            }
        }
    }

    nonisolated func stop() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            cameraQueue.async { [self] in
                if previewSession.isRunning { previewSession.stopRunning() }
                cont.resume()
            }
        }
    }

    nonisolated private func configureSession() throws {
        previewSession.beginConfiguration()
        defer { previewSession.commitConfiguration() }

        previewSession.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back
        ) else {
            throw NSError(domain: "ArucoDistance.Camera", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No back wide-angle camera available."
            ])
        }
        self.device = device

        let input = try AVCaptureDeviceInput(device: device)
        guard previewSession.canAddInput(input) else {
            throw NSError(domain: "ArucoDistance.Camera", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Cannot add camera input to session."
            ])
        }
        previewSession.addInput(input)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: cameraQueue)

        guard previewSession.canAddOutput(videoOutput) else {
            throw NSError(domain: "ArucoDistance.Camera", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Cannot add video output to session."
            ])
        }
        previewSession.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            } else {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
            if connection.isCameraIntrinsicMatrixDeliverySupported {
                connection.isCameraIntrinsicMatrixDeliveryEnabled = true
            }
        }
    }
}

extension AVFoundationCameraRepository: AVCaptureVideoDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let imageSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        let intrinsics: simd_float3x3
        if let real = CameraIntrinsicsExtractor.extract(from: sampleBuffer) {
            intrinsics = real
        } else if let device = device {
            intrinsics = CameraIntrinsicsExtractor.approximated(device: device, imageSize: imageSize)
        } else {
            return
        }

        let frame = CameraFrame(
            pixelBuffer: pixelBuffer,
            intrinsics: intrinsics,
            imageSize: imageSize,
            timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        )

        framesContinuation.yield(frame)
    }
}
