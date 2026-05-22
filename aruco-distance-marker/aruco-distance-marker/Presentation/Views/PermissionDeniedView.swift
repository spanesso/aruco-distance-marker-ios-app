import SwiftUI

struct PermissionDeniedView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Camera access denied")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
            Text("Enable the permission in Settings → ArucoDistance → Camera.")
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Open Settings", action: onOpenSettings)
                .foregroundColor(Color(red: 0.04, green: 0.52, blue: 1.0))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

#Preview {
    PermissionDeniedView(onOpenSettings: {})
}
