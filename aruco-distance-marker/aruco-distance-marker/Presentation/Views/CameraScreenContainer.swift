import SwiftUI
import UIKit

/// Thin adapter: binds CameraViewModel to the pure CameraScreenView.
/// This is the ONLY place that knows about both CameraViewModel and CameraScreenView.
struct CameraScreenContainer: View {

    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        CameraScreenView(
            permissionStatus: viewModel.permissionStatus,
            previewSession: viewModel.previewSession,
            detections: viewModel.detections,
            onAppear: { await viewModel.onAppear() },
            onRequestPermission: { await viewModel.requestPermission() },
            onOpenSettings: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            },
            onDisappear: { viewModel.onDisappear() }
        )
    }
}
