import SwiftUI
import NetCore

public struct SpeedMeterMenuBarLabel: View {
    @ObservedObject var viewModel: SpeedMeterViewModel

    public init(viewModel: SpeedMeterViewModel) {
        self.viewModel = viewModel
    }

    private var speedState: FluxSpeedMenuBarRenderer.FormattedSpeedState {
        FluxSpeedMenuBarRenderer.format(
            uploadBytes: Double(viewModel.currentSpeed.bytesOutPerSec),
            downloadBytes: Double(viewModel.currentSpeed.bytesInPerSec)
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Row 1: Upload (Top)
            HStack(spacing: 0) {
                Text("↑")
                    .font(.system(size: 8.5, weight: .heavy))
                    .frame(width: 10, alignment: .center)
                Text(speedState.uploadValue)
                    .font(.system(size: 9.0, weight: .medium, design: .monospaced))
                    .frame(width: 26, alignment: .trailing)
                Text(speedState.uploadUnit)
                    .font(.system(size: 8.5, weight: .medium))
                    .frame(width: 20, alignment: .leading)
                    .padding(.leading, 1)
            }
            .opacity(speedState.isUploadDimmed ? 0.40 : 1.00)
            .frame(height: 10)

            // Row 2: Download (Bottom)
            HStack(spacing: 0) {
                Text("↓")
                    .font(.system(size: 8.5, weight: .heavy))
                    .frame(width: 10, alignment: .center)
                Text(speedState.downloadValue)
                    .font(.system(size: 9.0, weight: .medium, design: .monospaced))
                    .frame(width: 26, alignment: .trailing)
                Text(speedState.downloadUnit)
                    .font(.system(size: 8.5, weight: .medium))
                    .frame(width: 20, alignment: .leading)
                    .padding(.leading, 1)
            }
            .opacity(speedState.isDownloadDimmed ? 0.40 : 1.00)
            .frame(height: 10)
        }
        .frame(width: 58, height: 22)
    }
}
