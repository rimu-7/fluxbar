import SwiftUI
import NetCore

public struct SpeedMeterMenuBarLabel: View {
    @ObservedObject var viewModel: SpeedMeterViewModel

    public init(viewModel: SpeedMeterViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text("↓")
                .font(.system(size: 11, weight: .semibold))
            Text(viewModel.currentSpeed.formattedDownload)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()

            Text("↑")
                .font(.system(size: 11, weight: .semibold))
            Text(viewModel.currentSpeed.formattedUpload)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
        }
    }
}
