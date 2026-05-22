# iOS Camera Intrinsics — Technical Notes

## How iOS delivers them

```swift
connection.isCameraIntrinsicMatrixDeliveryEnabled = true
// later, in captureOutput(_:didOutput:from:):
let data = CMGetAttachment(
    sampleBuffer,
    key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
    attachmentModeOut: nil
) as? Data
// data is exactly sizeof(simd_float3x3) = 36 bytes (9 floats, column-major)
```

## Checking device support

```swift
connection.isCameraIntrinsicMatrixDeliverySupported  // Bool
```

Supported on every iPhone with A11 (iPhone 8/X) or newer using `builtInWideAngleCamera` or `builtInDualCamera`. **Not supported** on `builtInTelephotoCamera` on some models.

## Caveats

- Intrinsics change with the `sessionPreset` (buffer resolution). iOS reports those matching the active preset.
- If you enable digital zoom (`videoZoomFactor > 1`), the reported intrinsics are NOT automatically adjusted for zoom. The app doesn't use zoom, so this is safe.
- HDR / Smart HDR doesn't affect intrinsics (only exposure bracketing, not geometry).
