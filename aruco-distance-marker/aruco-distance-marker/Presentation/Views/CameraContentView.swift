import AVFoundation
import SwiftUI

/// Pure view: shows the live preview + overlay. No VM dependency.
struct CameraContentView: View {
    let session: AVCaptureSession
    let detections: [MarkerDetection]

    var body: some View {
        ZStack {
            CameraPreviewView(session: session)
                .ignoresSafeArea()
            DetectionOverlayView(detections: detections)
                .ignoresSafeArea()
        }
    }
}
