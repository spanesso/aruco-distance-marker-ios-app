import AVFoundation
import CoreMedia
import simd

/// Extracts the camera intrinsic matrix from a CMSampleBuffer attachment.
///
/// Primary path: read `kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix`,
/// which iOS attaches when `connection.isCameraIntrinsicMatrixDeliveryEnabled = true`.
/// This gives the REAL factory-calibrated intrinsics for the active format.
///
/// Fallback path: approximate from `AVCaptureDevice.activeFormat.videoFieldOfView`.
/// Less accurate but still functional.
enum CameraIntrinsicsExtractor {

    nonisolated static func extract(from sampleBuffer: CMSampleBuffer) -> simd_float3x3? {
        guard let attachment = CMGetAttachment(
            sampleBuffer,
            key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
            attachmentModeOut: nil
        ) as? Data else { return nil }

        return attachment.withUnsafeBytes { buffer -> simd_float3x3? in
            guard buffer.count == MemoryLayout<simd_float3x3>.size else { return nil }
            return buffer.load(as: simd_float3x3.self)
        }
    }

    nonisolated static func approximated(device: AVCaptureDevice, imageSize: CGSize) -> simd_float3x3 {
        let fovDegrees = Double(device.activeFormat.videoFieldOfView)
        let fovRadians = fovDegrees * .pi / 180.0
        let fx = Float(Double(imageSize.width) / (2.0 * tan(fovRadians / 2.0)))
        let fy = fx
        let cx = Float(imageSize.width) / 2.0
        let cy = Float(imageSize.height) / 2.0

        return simd_float3x3(
            simd_float3(fx, 0, 0),
            simd_float3(0, fy, 0),
            simd_float3(cx, cy, 1)
        )
    }
}
