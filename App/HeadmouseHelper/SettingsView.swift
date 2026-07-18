import HeadmouseCore
import SwiftUI

/// Thin ObservableObject bridging the pure TrackingController to SwiftUI.
final class SettingsModel: ObservableObject {
    private let controller: TrackingController
    @Published private var version = 0

    init(controller: TrackingController) {
        self.controller = controller
        controller.observe { [weak self] in
            DispatchQueue.main.async { self?.version += 1 }
        }
    }

    var status: TrackingController.Status { controller.status }
    var deviceName: String { controller.activeDevice?.name ?? "No tracker connected" }
    var canToggle: Bool { status != .noDevice }

    func toggle() { controller.toggle() }
}

/// The window's content: a big circular Stop/Start button, with the connected
/// tracker's name and a green/red status dot beneath it. The window chrome
/// (title bar + system traffic lights) is provided by AppKit, not drawn here.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 20) {
            Button(action: model.toggle) {
                ZStack {
                    Circle()
                        .strokeBorder(ringColor, lineWidth: 4)
                        .frame(width: 150, height: 150)
                    Text(circleTitle)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                }
            }
            .buttonStyle(.plain)
            .disabled(!model.canToggle)
            .opacity(model.canToggle ? 1 : 0.5)

            Divider()

            HStack(spacing: 8) {
                Circle().fill(stateColor).frame(width: 10, height: 10)
                Text(model.deviceName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, 8)
        .frame(width: 260)
    }

    private var circleTitle: String {
        switch model.status {
        case .tracking: return "Stop\ntracking"
        case .stopped: return "Start\ntracking"
        case .noDevice: return "No\ntracker"
        }
    }

    /// Neutral ring colour — the toggle circle itself is not state-coloured.
    private var ringColor: Color { .secondary }

    /// The small status dot beside the device name keeps the state colour.
    private var stateColor: Color {
        switch model.status {
        case .tracking: return .green
        case .stopped: return .red
        case .noDevice: return .secondary
        }
    }
}
