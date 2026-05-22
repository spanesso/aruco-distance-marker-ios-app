import AVFoundation
import SwiftUI
import UIKit

/// Pure screen-level view. Takes state + callbacks; emits no observable side effects.
/// Reusable: can be previewed with any synthetic state, no VM needed.
struct CameraScreenView: View {
    let permissionStatus: CameraPermissionStatus
    let previewSession: AVCaptureSession
    let detections: [MarkerDetection]

    let onAppear: () async -> Void
    let onRequestPermission: () async -> Void
    let onOpenSettings: () -> Void
    let onDisappear: () -> Void

    var body: some View {
        Group {
            switch permissionStatus {
            case .authorized:
                CameraContentView(session: previewSession, detections: detections)
            case .notDetermined:
                PermissionRequestView(onRequest: {
                    Task { await onRequestPermission() }
                })
            case .denied, .restricted:
                PermissionDeniedView(onOpenSettings: onOpenSettings)
            }
        }
        .task { await onAppear() }
        .onDisappear { onDisappear() }
    }
}

#Preview("Authorized — empty") {
    CameraScreenView(
        permissionStatus: .authorized,
        previewSession: AVCaptureSession(),
        detections: [],
        onAppear: {}, onRequestPermission: {}, onOpenSettings: {}, onDisappear: {}
    )
}

#Preview("Not determined") {
    CameraScreenView(
        permissionStatus: .notDetermined,
        previewSession: AVCaptureSession(),
        detections: [],
        onAppear: {}, onRequestPermission: {}, onOpenSettings: {}, onDisappear: {}
    )
}
