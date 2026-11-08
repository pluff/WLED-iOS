import SwiftUI

/// Full-screen brightness control: drag the bar for a quick change,
/// use the Digital Crown for fine adjustment.
struct BrightnessView: View {
    @ObservedObject var controller: DeviceController
    @FocusState private var crownFocused: Bool

    private let range = DeviceController.minBrightness...DeviceController.maxBrightness

    private var fraction: Double {
        (controller.brightness - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sun.max.fill")
                .font(.title3)
                .foregroundStyle(.yellow)
            Text("\(Int(controller.brightness.rounded()))")
                .font(.system(size: 48, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(.yellow)
                        .frame(width: max(proxy.size.height, proxy.size.width * fraction))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let x = min(max(drag.location.x / proxy.size.width, 0), 1)
                            controller.brightness = (range.lowerBound + x * (range.upperBound - range.lowerBound)).rounded()
                        }
                )
            }
            .frame(height: 28)
        }
        .padding(.horizontal, 4)
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation(
            $controller.brightness,
            from: range.lowerBound,
            through: range.upperBound,
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear { crownFocused = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(Int(controller.brightness.rounded())) of 255")
        .accessibilityAdjustableAction { direction in
            let step = 15.0
            switch direction {
            case .increment: controller.brightness = min(controller.brightness + step, range.upperBound)
            case .decrement: controller.brightness = max(controller.brightness - step, range.lowerBound)
            @unknown default: break
            }
        }
    }
}
