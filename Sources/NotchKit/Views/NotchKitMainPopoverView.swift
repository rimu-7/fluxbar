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
                            Color.black.opacity(0.12)
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
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 10)

                    Divider().opacity(0.15)

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
        .frame(width: 440, height: 600)
    }

    // MARK: - Top Navigation Header

    private var topNavigationHeader: some View {
        HStack(spacing: 10) {
            // App Branding
            HStack(spacing: 6) {
                Image(systemName: "circle.grid.2x2.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.cyan)

                Text("NotchKit")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }

            Spacer(minLength: 4)

            // Segmented Glass Tab Switcher (Order: Clipboard -> Battery -> Speed Meter)
            HStack(spacing: 2) {
                ForEach(NotchKitTab.allCases) { tab in
                    let isSelected = statusManager.selectedTab == tab
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            statusManager.selectedTab = tab
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4.5)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                    .fill(Color.white.opacity(0.18))
                                    .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                                    }
                            }
                        }
                        .foregroundColor(isSelected ? .white : .secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2.5)
            .background(Color.black.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }

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
