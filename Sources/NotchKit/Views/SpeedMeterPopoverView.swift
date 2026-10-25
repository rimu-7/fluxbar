import SwiftUI
import AppKit
import NetCore
import ClipCore

public struct SpeedMeterPopoverView: View {
    @ObservedObject var speedVM: SpeedMeterViewModel
    @ObservedObject var clipVM: ClipBarViewModel

    @State private var showingResetMonthConfirmation: Bool = false
    @State private var showingResetAllConfirmation: Bool = false
    @State private var startAtLogin: Bool = LaunchAtLoginHelper.isEnabled

    public init(speedVM: SpeedMeterViewModel, clipVM: ClipBarViewModel) {
        self.speedVM = speedVM
        self.clipVM = clipVM
    }

    public var body: some View {
        ZStack {
            if speedVM.showingSettings {
                SettingsView(viewModel: clipVM)
            } else {
                mainContentView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider().opacity(0.2)

            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    // 1. Live Speed Gauge Cards
                    liveSpeedCard

                    // 2. Monthly Usage Card (High Priority Feature)
                    monthlyUsageCard

                    // 3. Today & Session Usage Card
                    todayAndSessionCard

                    // 4. Quick Controls & Settings
                    quickControlsCard
                }
                .padding(13)
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            HStack(spacing: 7) {
                Circle()
                    .fill(speedVM.interfaceInfo.isConnected ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                    .shadow(color: (speedVM.interfaceInfo.isConnected ? Color.green : Color.red).opacity(0.5), radius: 3)

                Text("Speed Meter")
                    .font(.system(size: 13, weight: .semibold))
            }

            Spacer()

            // Active Interface Pill
            HStack(spacing: 4.5) {
                Image(systemName: speedVM.interfaceInfo.typeName == "Wi-Fi" ? "wifi" : "cable.connector")
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
                Text(speedVM.interfaceInfo.displayName)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))

            // Settings Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    speedVM.showingSettings = true
                }
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6.5, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Open NotchKit Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.14))
    }

    // MARK: - Live Speed Dashboard Card

    private var liveSpeedCard: some View {
        HStack(spacing: 9) {
            // Download Speed
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.cyan)
                    Text("DOWNLOAD")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Text(speedVM.currentSpeed.formattedDownload)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(.cyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cyan.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.cyan.opacity(0.25), lineWidth: 0.5))

            // Upload Speed
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    Text("UPLOAD")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Text(speedVM.currentSpeed.formattedUpload)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.green.opacity(0.25), lineWidth: 0.5))
        }
    }

    // MARK: - Monthly Usage Card

    private var monthlyUsageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                    Text("MONTHLY USAGE (\(speedVM.monthUsage.periodKey))")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(speedVM.monthUsage.formattedTotal)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }

            // Visual Progress Ratio Bar
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let dlRatio = CGFloat(speedVM.monthUsage.downloadPercentage)
                let dlWidth = max(2, totalWidth * dlRatio)
                let ulWidth = max(2, totalWidth * (1.0 - dlRatio))

                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.cyan.opacity(0.85))
                        .frame(width: max(0, dlWidth - 1))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green.opacity(0.85))
                        .frame(width: max(0, ulWidth - 1))
                }
            }
            .frame(height: 7)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())

            // Breakdown Rows
            HStack {
                HStack(spacing: 4) {
                    Circle().fill(Color.cyan).frame(width: 6, height: 6)
                    Text("Download:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(speedVM.monthUsage.formattedDownload)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("Upload:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(speedVM.monthUsage.formattedUpload)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }

            Divider().opacity(0.15).padding(.vertical, 1)

            // Reset Month Action
            if showingResetMonthConfirmation {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reset data counters for this month?")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Button("Cancel") {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                showingResetMonthConfirmation = false
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))

                        Button("Confirm Reset") {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                speedVM.resetMonthUsage()
                                showingResetMonthConfirmation = false
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 5.5, style: .continuous).strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.5))
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showingResetMonthConfirmation = true
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                        Text("Reset Month Counters")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }

    // MARK: - Today & Session Usage Card

    private var todayAndSessionCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("DATA USAGE BREAKDOWN")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundColor(.secondary.opacity(0.8))

            // Today Row
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Today")
                        .font(.system(size: 11.5, weight: .medium))
                }

                Spacer()

                Text("↓ \(speedVM.todayUsage.formattedDownload)   ↑ \(speedVM.todayUsage.formattedUpload)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                Text(speedVM.todayUsage.formattedTotal)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }

            Divider().opacity(0.15)

            // Session Row
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "bolt")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("This Session")
                        .font(.system(size: 11.5, weight: .medium))
                }

                Spacer()

                Text("↓ \(speedVM.sessionUsage.formattedDownload)   ↑ \(speedVM.sessionUsage.formattedUpload)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                Text(speedVM.sessionUsage.formattedTotal)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }

    // MARK: - Quick Controls Card

    private var quickControlsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Start at Login
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "power.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                    Text("Start at Login")
                        .font(.system(size: 11.5, weight: .medium))
                }

                Spacer()

                Toggle("", isOn: $startAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: startAtLogin) { newValue in
                        LaunchAtLoginHelper.setEnabled(newValue)
                    }
            }

            Divider().opacity(0.15)

            // Open Full Settings
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    speedVM.showingSettings = true
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Open NotchKit Settings")
                        .font(.system(size: 11.5, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)

            Divider().opacity(0.15)

            // Quit
            Button(action: { NSApplication.shared.terminate(nil) }) {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Quit NotchKit")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}
