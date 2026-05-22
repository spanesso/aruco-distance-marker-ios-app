import SwiftUI

struct PermissionRequestView: View {
    let onRequest: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("ArucoDistance needs camera access")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: onRequest) {
                Text("Allow Camera")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.04, green: 0.52, blue: 1.0))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

#Preview {
    PermissionRequestView(onRequest: {})
}
