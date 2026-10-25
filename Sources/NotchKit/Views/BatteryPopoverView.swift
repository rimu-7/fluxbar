import SwiftUI
import AppKit
import PowerCore
import ClipCore

@MainActor
public struct BatteryPopoverView: View {
    @ObservedObject var batteryVM: BatteryViewModel
    @ObservedObject var clipVM: ClipBarViewModel

    @State private var hoveredPreset: Int? = nil

    @MainActor
    public init(batteryVM: BatteryViewModel, clipVM: ClipBarViewModel) {
        self.batteryVM = batteryVM
        self.clipVM = clipVM
    }

    @MainActor
    public init() {
        self.batteryVM = .shared
        self.clipVM = .shared
    }

    public var body: some View {
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                Divider().opacity(0.12)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        heroBatteryCard
                        chargeLimitCard
                        diagnosticsGrid
                        hardwareHelperCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                Divider().opacity(0.12)

                footerView
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .frame(width: 380, height: 540)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusAccentColor.opacity(0.16))
                    .frame(width: 32, height: 32)
                Image(systemName: batteryVM.telemetry.menuBarSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(statusAccentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Battery Charge Limiter")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    if batteryVM.isBypassActive {
                        Text("BYPASS")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [Color.green, Color.teal],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ))
                            )
                    }
                }

                Text(statusSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                batteryVM.refresh()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Refresh Battery Telemetry")

            Button(action: {
                clipVM.showingSettings = true
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Open NotchKit Settings")
        }
    }

    // MARK: - Hero Battery Card

    private var heroBatteryCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                // Circular Gauge
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 9)
                        .frame(width: 86, height: 86)

                    Circle()
                        .trim(from: 0.0, to: CGFloat(batteryVM.telemetry.percentage) / 100.0)
                        .stroke(
                            LinearGradient(
                                colors: [statusAccentColor, statusAccentColor.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 86, height: 86)
                        .animation(.easeInOut(duration: 0.3), value: batteryVM.telemetry.percentage)

                    VStack(spacing: 0) {
                        Text("\(batteryVM.telemetry.percentage)%")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text(batteryVM.telemetry.isCharging ? "CHARGING" : (batteryVM.isBypassActive ? "BYPASS" : "BATTERY"))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(statusAccentColor)
                            .tracking(0.5)
                    }
                }

                // Status Details
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: batteryVM.isBypassActive ? "powerplug.fill" : (batteryVM.telemetry.isCharging ? "bolt.fill" : "battery.75"))
                            .font(.system(size: 12))
                            .foregroundColor(statusAccentColor)

                        Text(batteryVM.isBypassActive ? "Adapter Bypass Active" : batteryVM.telemetry.chargingState.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                    }

                    Text(powerBehaviorDescription)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let adapterWatts = batteryVM.telemetry.adapterWatts {
                        HStack(spacing: 4) {
                            Text("Adapter:")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("\(adapterWatts)W \(batteryVM.telemetry.adapterName ?? "Charger")")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Charge Limit Card

    private var chargeLimitCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CHARGE LIMIT THRESHOLD")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(.secondary.opacity(0.8))

                    Text("Stop at \(batteryVM.chargeLimit)% & use power from adapter")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.primary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { batteryVM.isLimiterEnabled },
                    set: { batteryVM.setLimiterEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if batteryVM.isLimiterEnabled {
                // Slider
                VStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { Double(batteryVM.chargeLimit) },
                            set: { batteryVM.setChargeLimit(Int($0)) }
                        ),
                        in: 50...100,
                        step: 5
                    )
                    .tint(statusAccentColor)

                    HStack {
                        Text("50% (Storage)")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("80% (Recommended)")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(batteryVM.chargeLimit == 80 ? statusAccentColor : .secondary)
                        Spacer()
                        Text("100% (Full)")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    }
                }

                // Quick Presets
                HStack(spacing: 6) {
                    ForEach(batteryVM.availablePresets, id: \.self) { preset in
                        let isSelected = batteryVM.chargeLimit == preset
                        Button(action: {
                            batteryVM.setChargeLimit(preset)
                        }) {
                            Text(preset == 100 ? "100%" : "\(preset)%")
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isSelected ? statusAccentColor : (hoveredPreset == preset ? Color.white.opacity(0.09) : Color.white.opacity(0.045)))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.08), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .onHover { isHovered in
                            hoveredPreset = isHovered ? preset : nil
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Diagnostics Grid

    private var diagnosticsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BATTERY HEALTH & POWER METRICS")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.leading, 2)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                metricCell(
                    icon: "heart.fill",
                    color: .pink,
                    label: "Health",
                    value: String(format: "%.1f%%", batteryVM.telemetry.healthPercentage),
                    subvalue: "\(batteryVM.telemetry.fullChargeCapacity) / \(batteryVM.telemetry.designCapacity) mAh"
                )

                metricCell(
                    icon: "arrow.triangle.2.circlepath",
                    color: .blue,
                    label: "Cycle Count",
                    value: "\(batteryVM.telemetry.cycleCount)",
                    subvalue: "Total recharge cycles"
                )

                metricCell(
                    icon: "bolt.fill",
                    color: .yellow,
                    label: "Power Draw",
                    value: String(format: "%.1f W", batteryVM.telemetry.wattage),
                    subvalue: batteryVM.isBypassActive ? "0W to battery (Bypass)" : "\(batteryVM.telemetry.amperage) mA"
                )

                metricCell(
                    icon: "thermometer.medium",
                    color: .orange,
                    label: "Temperature",
                    value: String(format: "%.1f °C", batteryVM.telemetry.temperature),
                    subvalue: String(format: "%.1f V", Double(batteryVM.telemetry.voltage) / 1000.0)
                )
            }
        }
    }

    private func metricCell(icon: String, color: Color, label: String, value: String, subvalue: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(subvalue)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary.opacity(0.8))
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - Hardware Helper Card

    private var hardwareHelperCard: some View {
        HStack(spacing: 10) {
            Image(systemName: batteryVM.isHelperInstalled ? "checkmark.shield.fill" : "lock.shield")
                .font(.system(size: 16))
                .foregroundColor(batteryVM.isHelperInstalled ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(batteryVM.isHelperInstalled ? "Hardware SMC Limiter: Active" : "Hardware Bypass Control")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.primary)

                Text(batteryVM.isHelperInstalled ? "Power adapter bypass enforced via hardware." : "One-time authorization enables native SMC charge cutoff.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !batteryVM.isHelperInstalled {
                Button(action: {
                    batteryVM.authorizeHelper()
                }) {
                    Text(batteryVM.isAuthorizingHelper ? "Authorizing..." : "Authorize")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(batteryVM.isAuthorizingHelper)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button(action: {
                clipVM.showingSettings = true
            }) {
                Label("NotchKit Settings", systemImage: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Text("Quit")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Computed Styles

    private var statusAccentColor: Color {
        if batteryVM.isBypassActive {
            return .teal
        } else if batteryVM.telemetry.isCharging {
            return .green
        } else if batteryVM.telemetry.percentage <= 20 {
            return .red
        } else {
            return .blue
        }
    }

    private var statusSubtitle: String {
        if batteryVM.isBypassActive {
            return "Adapter Power • Battery Preserved"
        } else if batteryVM.telemetry.isCharging {
            return batteryVM.telemetry.formattedRemainingTime
        } else if batteryVM.telemetry.isPluggedIn {
            return "Connected to AC Power"
        } else {
            return batteryVM.telemetry.formattedRemainingTime
        }
    }

    private var powerBehaviorDescription: String {
        if batteryVM.isBypassActive {
            return "Charging is paused at \(batteryVM.chargeLimit)%. Your MacBook draws 100% of its operating power directly from the wall adapter."
        } else if batteryVM.telemetry.isCharging {
            return "Replenishing battery cells up to \(batteryVM.chargeLimit)%. Direct adapter bypass will engage upon reaching the limit."
        } else if batteryVM.telemetry.isPluggedIn {
            return "Connected to adapter. Battery is at normal capacity."
        } else {
            return "Operating on battery power. Connect power adapter to engage limiter."
        }
    }
}
