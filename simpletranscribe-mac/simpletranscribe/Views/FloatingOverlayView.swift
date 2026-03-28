import SwiftUI

enum OverlayState: Equatable {
    case idle
    case recording
    case transcribing
    case done
    case error(String)
}

struct FloatingOverlayView: View {
    let state: OverlayState

    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .idle:
                EmptyView()

            case .recording:
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .opacity(pulseOpacity)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                            pulseOpacity = 0.3
                        }
                    }
                    .onDisappear { pulseOpacity = 1.0 }
                Text("Recording...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

            case .transcribing:
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
                Text("Done!")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

            case .error(let message):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 14))
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 36)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
