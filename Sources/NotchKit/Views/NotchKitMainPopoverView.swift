import SwiftUI
import AppKit
import ClipCore
import NetCore
import PowerCore

public enum NotchKitTab: String, CaseIterable, Identifiable, Sendable {
    case clipboard = "Clipboard"
    case battery = "Battery"
    case speedMeter = "Speed"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .clipboard:
            return "doc.on.doc.fill"
        case .battery:
            return "bolt.batteryblock.fill"
        case .speedMeter:
            return "network"
        }
    }

    public var accentColor: Color {
        switch self {
        case .clipboard:
            return Color(red: 0.22, green: 0.68, blue: 1.0) // Vivid Sky Blue
        case .battery:
            return Color(red: 0.05, green: 0.88, blue: 0.62) // Neon Emerald
        case .speedMeter:
            return Color(red: 0.72, green: 0.44, blue: 1.0) // Cyber Lavender
        }
    }
}

@MainActor
public struct NotchKitMainPopoverView: View {
    @ObservedObject var clipVM: ClipBarViewModel
    @ObservedObject var speedVM: SpeedMeterViewModel
    @ObservedObject var batteryVM: BatteryViewModel
    @ObservedObject var statusManager: StatusBarManager

    @MainActor
    public init(
        clipVM: ClipBarViewModel,
        speedVM: SpeedMeterViewModel,
        batteryVM: BatteryViewModel,
        statusManager: StatusBarManager
    ) {
        self.clipVM = clipVM
        self.speedVM = speedVM
        self.batteryVM = batteryVM
        self.statusManager = statusManager
    }

    public var body: some View {
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .behindWindow, state: .active)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.04),
                            Color.clear,
                            Color.black.opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .ignoresSafeArea()

            if clipVM.showingSettings {
                SettingsView(viewModel: clipVM)
            } else {
                VStack(spacing: 0) {
                    // Unified Top Bar with NotchKit Brand, Segmented Switcher, and Close Button
                    topNavigationHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 13)
                        .padding(.bottom, 11)

                    Divider().opacity(0.12)

                    // Tab Content Switcher
                    Group {
                        switch statusManager.selectedTab {
                        case .clipboard:
                            PopoverRootView(viewModel: clipVM)
                        case .battery:
                            BatteryPopoverView(batteryVM: batteryVM, clipVM: clipVM)
                        case .speedMeter:
                            SpeedMeterPopoverView(speedVM: speedVM, clipVM: clipVM)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 485, height: 640)
    }

    // MARK: - Top Navigation Header

    private var topNavigationHeader: some View {
        HStack(spacing: 10) {
            // App Branding
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 22, height: 22)
                        .shadow(color: Color.cyan.opacity(0.35), radius: 4, x: 0, y: 1)

                    Image(systemName: "circle.grid.2x2.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }

                Text("NotchKit")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            .fixedSize()

            Spacer(minLength: 4)

            // Segmented Glass Tab Switcher (Order: Clipboard -> Battery -> Speed Meter)
            HStack(spacing: 3) {
                ForEach(NotchKitTab.allCases) { tab in
                    let isSelected = statusManager.selectedTab == tab
                    Button(action: {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                            statusManager.selectedTab = tab
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? tab.accentColor : .secondary)

                            Text(tab.rawValue)
                                .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? .white : .secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.18),
                                                tab.accentColor.opacity(0.15)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 1)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(
                                                LinearGradient(
                                                    colors: [
                                                        tab.accentColor.opacity(0.55),
                                                        Color.white.opacity(0.2)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 0.75
                                            )
                                    }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.black.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .fixedSize()

            Spacer(minLength: 4)

            // Settings Button
            Button(action: {
                clipVM.showingSettings = true
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("NotchKit Settings")

            // Prominent ✕ Close Button
            Button(action: {
                StatusBarManager.shared.closePopover()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close Popover (Esc)")
        }
    }
}
