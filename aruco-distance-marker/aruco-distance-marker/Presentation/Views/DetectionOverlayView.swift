import SwiftUI

/// Renders marker contours and distance label.
/// Pure: takes detections, produces a view. No VM, no observation.
struct DetectionOverlayView: View {

    let detections: [MarkerDetection]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { context, _ in
                    for detection in detections {
                        let viewPoints = detection.cornersInImageSpace.map {
                            mapImagePoint($0, imageSize: detection.imageSize, viewSize: geo.size)
                        }
                        guard viewPoints.count == 4 else { continue }

                        var path = Path()
                        path.move(to: viewPoints[0])
                        path.addLine(to: viewPoints[1])
                        path.addLine(to: viewPoints[2])
                        path.addLine(to: viewPoints[3])
                        path.closeSubpath()
                        context.stroke(
                            path,
                            with: .color(Color(red: 0, green: 1, blue: 0.416)),
                            lineWidth: 4
                        )

                        let dotRect = CGRect(
                            x: viewPoints[0].x - 6, y: viewPoints[0].y - 6,
                            width: 12, height: 12
                        )
                        context.fill(
                            Path(ellipseIn: dotRect),
                            with: .color(Color(red: 0, green: 1, blue: 0.416))
                        )
                    }
                }

                if let first = detections.first {
                    VStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text(String(format: "%.1f cm", first.distanceCentimeters))
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            Text("ID \(first.id)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .padding(.bottom, 60)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Maps an image-buffer point (pixels) to view space, assuming aspect-fill.
    private func mapImagePoint(
        _ point: CGPoint,
        imageSize: CGSize,
        viewSize: CGSize
    ) -> CGPoint {
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height

        let scale: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat

        if imageAspect > viewAspect {
            scale = viewSize.height / imageSize.height
            offsetX = (viewSize.width - imageSize.width * scale) / 2.0
            offsetY = 0
        } else {
            scale = viewSize.width / imageSize.width
            offsetX = 0
            offsetY = (viewSize.height - imageSize.height * scale) / 2.0
        }

        return CGPoint(x: point.x * scale + offsetX, y: point.y * scale + offsetY)
    }
}

#Preview("With detection") {
    DetectionOverlayView(detections: [
        MarkerDetection(
            id: 0,
            cornersInImageSpace: [
                CGPoint(x: 100, y: 100),
                CGPoint(x: 600, y: 110),
                CGPoint(x: 590, y: 700),
                CGPoint(x: 110, y: 690)
            ],
            imageSize: CGSize(width: 720, height: 1280),
            distanceMeters: 0.42
        )
    ])
    .background(.black)
}

#Preview("Empty") {
    DetectionOverlayView(detections: [])
        .background(.black)
}
