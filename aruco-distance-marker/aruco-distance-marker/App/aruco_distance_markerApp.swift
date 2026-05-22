import SwiftUI

@main
struct aruco_distance_markerApp: App {

    @StateObject private var cameraViewModel: CameraViewModel

    init() {
        let composer = CompositionRoot()
        _cameraViewModel = StateObject(wrappedValue: composer.makeCameraViewModel())
    }

    var body: some Scene {
        WindowGroup {
            CameraScreenContainer(viewModel: cameraViewModel)
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}
