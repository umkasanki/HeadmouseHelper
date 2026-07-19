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

    var movement: MovementSettings { controller.movement }
    func updateMovement(_ movement: MovementSettings) { controller.updateMovement(movement) }
}

/// The window's content: Control (big Stop/Start circle) + Movement (tuning) tabs.
/// Window chrome (title bar + system traffic lights) is provided by AppKit.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            // A segmented control (not TabView) — centered under the title bar,
            // stable across macOS versions (TabView collapses to an overflow
            // menu on macOS 26).
            Picker("", selection: $tab) {
                Text("Control").tag(0)
                Text("Movement").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            if tab == 0 {
                ControlTab(model: model)
            } else {
                MovementTab(model: model)
            }
        }
        .frame(width: 300)
    }
}

private struct ControlTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 20) {
            Button(action: model.toggle) {
                ZStack {
                    Circle()
                        .strokeBorder(.secondary, lineWidth: 4)
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
        .padding(20)
    }

    private var circleTitle: String {
        switch model.status {
        case .tracking: return "Stop\ntracking"
        case .stopped: return "Start\ntracking"
        case .noDevice: return "No\ntracker"
        }
    }

    private var stateColor: Color {
        switch model.status {
        case .tracking: return .green
        case .stopped: return .red
        case .noDevice: return .secondary
        }
    }
}

private struct MovementTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Disable acceleration", isOn: disableAcceleration)

            StepperSlider(title: "Acceleration", value: acceleration, range: 0 ... 40, step: 1)
                .disabled(model.movement.disableAcceleration)
                .opacity(model.movement.disableAcceleration ? 0.4 : 1)

            StepperSlider(title: "Speed", value: speed, range: 0 ... 1, step: 0.05)

            Button("Restore defaults") { model.updateMovement(MovementSettings()) }
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
    }

    private var speed: Binding<Double> {
        Binding(get: { model.movement.speed },
                set: { var m = model.movement; m.speed = $0; model.updateMovement(m) })
    }
    private var acceleration: Binding<Double> {
        Binding(get: { model.movement.acceleration },
                set: { var m = model.movement; m.acceleration = $0; model.updateMovement(m) })
    }
    private var disableAcceleration: Binding<Bool> {
        Binding(get: { model.movement.disableAcceleration },
                set: { var m = model.movement; m.disableAcceleration = $0; model.updateMovement(m) })
    }
}

/// A labelled slider flanked by − / + step buttons, with a numeric entry field
/// centered below it. All inputs are clamped to `range`.
private struct StepperSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var decimals: Int = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline)
            HStack(spacing: 8) {
                Button { set(value - step) } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Slider(value: clamped, in: range)

                Button { set(value + step) } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            TextField("", value: clamped, format: .number.precision(.fractionLength(0 ... decimals)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 72)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var clamped: Binding<Double> {
        Binding(get: { value }, set: { set($0) })
    }

    private func set(_ newValue: Double) {
        value = min(max(newValue, range.lowerBound), range.upperBound)
    }
}
