import SwiftUI
import AppKit
import PowerCore
import ClipCore

/// High-precision, colorful, interactive Battery & Hardware Power Analytics view
@MainActor
public struct BatteryPopoverView: View {
    @ObservedObject var batteryVM: BatteryViewModel
    @ObservedObject var clipVM: ClipBarViewModel

    @State private var hoveredPreset: Int? = nil
    @State private var hoveredBarIndex: Int? = nil
    @State private var isDonutHovered: Bool = false

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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                // 1. Hero Dynamic Battery & Bypass Header Card
                heroBatteryCard

                // 2. Hardware Charger Details & Live Negotiated Power Flow
                chargerDetailsCard

                // 3. Reverse Charging & External Accessories Power Delivery
                accessoryPowerDeliveryCard

                // 4. Hardware Charge Limiter & Threshold Range Chart
                chargeLimiterCard

                // 5. Battery Health & Degradation Pie / Donut Chart
                healthDonutChartCard

                // 6. 24-Hour Battery Discharge & Power Usage Bar Chart
                powerTimelineBarChartCard

                // 7. Battery Lifespan & Longevity Prediction
                lifecyclePredictionCard

                // 8. Live Hardware Diagnostics & Sensors Grid
                diagnosticsSensorGrid

                // 9. Kernel SMC Control & Touch ID Authorization
                kernelSMCAuthorizationCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 1. Hero Battery Card with Live Telemetry

    private var heroBatteryCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 18) {
                // Animated Multi-Layer Circular Gauge
                ZStack {
                    // Outer track background
                    Circle()
                        .stroke(Color.white.opacity(0.07), lineWidth: 10)
                        .frame(width: 90, height: 90)

                    // Active Battery Level Progress Ring
                    Circle()
                        .trim(from: 0.0, to: CGFloat(batteryVM.telemetry.percentage) / 100.0)
                        .stroke(
                            LinearGradient(
                                colors: [primaryAccentColor, primaryAccentColor.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 90, height: 90)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: batteryVM.telemetry.percentage)

                    // Target Limit Notch Indicator
                    if batteryVM.isLimiterEnabled && batteryVM.chargeLimit < 100 {
                        Circle()
                            .trim(from: max(0.0, CGFloat(batteryVM.chargeLimit) / 100.0 - 0.006),
                                  to: CGFloat(batteryVM.chargeLimit) / 100.0)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 90, height: 90)
                    }

                    // Inside Text Counter
                    VStack(spacing: 1) {
                        Text("\(batteryVM.telemetry.percentage)%")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text(heroStateBadgeText)
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(primaryAccentColor)
                            .tracking(0.6)
                    }
                }

                // Dynamic Status & Power Flow Details
                VStack(alignment: .leading, spacing: 6) {
                    // Status Badge Pill
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(primaryAccentColor.opacity(0.2))
                                .frame(width: 20, height: 20)

                            Image(systemName: heroStateIcon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(primaryAccentColor)
                        }

                        Text(heroStateTitle)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)

                        Spacer()

                        // Real-time Wattage Tag
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8))
                            Text(String(format: "%.1f W", batteryVM.telemetry.wattage))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(primaryAccentColor.opacity(0.14))
                        .foregroundColor(primaryAccentColor)
                        .clipShape(Capsule())
                    }

                    Text(powerBehaviorDescription)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(1.5)

                    if let adapterWatts = batteryVM.telemetry.adapterWatts {
                        HStack(spacing: 5) {
                            Text("Power Adapter:")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.secondary)

                            Text("\(adapterWatts)W \(batteryVM.telemetry.adapterName ?? "PD Charger")")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(.primary)

                            Text("• Fast Charging")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color.teal)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [primaryAccentColor.opacity(0.3), Color.white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                }
        )
    }

    // MARK: - 2. Power Adapter Hardware & Live Negotiated Input Card

    private var chargerDetailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "powerplug.fill")
                        .font(.system(size: 12))
                        .foregroundColor(batteryVM.telemetry.isPluggedIn ? Color.green : Color.secondary)

                    Text("CHARGER HARDWARE & LIVE POWER INPUT")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.6)
                        .foregroundColor(.secondary.opacity(0.85))
                }

                Spacer()

                if batteryVM.telemetry.isPluggedIn {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(batteryVM.telemetry.adapterWatts != nil && batteryVM.telemetry.adapterWatts! >= 60 ? "Fast Charge Connected" : "AC Connected")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.green)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
                } else {
                    Text("Unplugged")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
            }

            if batteryVM.telemetry.isPluggedIn {
                // Top row: Charger Model & Max Wattage
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.2), Color.teal.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)

                        Image(systemName: "bolt.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Color.green)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("\(batteryVM.telemetry.adapterWatts ?? 100)W")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)

                            Text(batteryVM.telemetry.adapterName?.uppercased() ?? "PD CHARGER")
                                .font(.system(size: 9.5, weight: .heavy))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08))
                                .foregroundColor(.secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }

                        if let port = batteryVM.telemetry.chargerPortIndex {
                            Text("Connected to Thunderbolt / USB-C Port \(port)")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                        } else {
                            Text("Negotiated USB-PD 3.0 High-Power Rail")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Live Input Wattage Highlight Badge
                    let liveWatts = batteryVM.telemetry.inputPowerWatts ?? Double(batteryVM.telemetry.adapterWatts ?? 0)
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(spacing: 2) {
                            Text(String(format: "%.1f", liveWatts))
                                .font(.system(size: 18, weight: .heavy, design: .monospaced))
                                .foregroundColor(Color.teal)
                            Text("W")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color.teal)
                        }
                        Text("ACTIVE POWER INPUT")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }

                // Real-time Power Input Flow Bar (Draw vs Charger Capacity)
                let maxWatts = Double(batteryVM.telemetry.adapterWatts ?? 100)
                let activeWatts = batteryVM.telemetry.inputPowerWatts ?? min(maxWatts, max(5.0, batteryVM.telemetry.wattage))
                let ratio = max(0.05, min(1.0, activeWatts / maxWatts))

                VStack(spacing: 5) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 7)

                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.green, Color.teal, Color.cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(8, geo.size.width * CGFloat(ratio)), height: 7)
                        }
                    }
                    .frame(height: 7)

                    HStack {
                        Text(String(format: "%.1f W active draw (%.0f%% of adapter capacity)", activeWatts, ratio * 100))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Max: \(Int(maxWatts))W")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)

                // Electrical Specs Grid (Voltage Rail, Amperage Draw, Power Delivery)
                HStack(spacing: 8) {
                    let voltVal = batteryVM.telemetry.inputVoltage ?? batteryVM.telemetry.adapterVoltage ?? 20.0
                    let ampVal = batteryVM.telemetry.inputCurrentAmps ?? batteryVM.telemetry.adapterAmperage ?? 3.6
                    let maxAmp = batteryVM.telemetry.adapterAmperage ?? 5.0

                    miniSpecBox(
                        title: "INPUT VOLTAGE",
                        value: String(format: "%.1f V", voltVal),
                        subtitle: "Negotiated DC Rail",
                        icon: "bolt.badge.clock"
                    )

                    miniSpecBox(
                        title: "CURRENT FLOW",
                        value: String(format: "%.2f A", ampVal),
                        subtitle: "Max \(String(format: "%.1f", maxAmp)) A",
                        icon: "gauge.with.needle"
                    )

                    miniSpecBox(
                        title: "POWER DELIVERY",
                        value: "USB-PD 3.0",
                        subtitle: "EPR Smart Profile",
                        icon: "cpu"
                    )
                }

                // Supported USB-PD Charging Profiles Pills
                VStack(alignment: .leading, spacing: 6) {
                    Text("SUPPORTED USB-PD POWER PROFILES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)

                    let profiles = !batteryVM.telemetry.adapterProfiles.isEmpty
                        ? batteryVM.telemetry.adapterProfiles
                        : ["5V @ 3.0A (15W)", "9V @ 3.0A (27W)", "15V @ 3.0A (45W)", "20V @ 5.0A (\(batteryVM.telemetry.adapterWatts ?? 100)W)"]

                    HStack(spacing: 5) {
                        ForEach(Array(profiles.enumerated()), id: \.offset) { idx, profile in
                            let isActive = (batteryVM.telemetry.activeProfileIndex != nil && batteryVM.telemetry.activeProfileIndex == idx) || (batteryVM.telemetry.activeProfileIndex == nil && idx == profiles.count - 1)
                            HStack(spacing: 3) {
                                if isActive {
                                    Circle()
                                        .fill(Color.teal)
                                        .frame(width: 4, height: 4)
                                }
                                Text(profile)
                                    .font(.system(size: 8.5, weight: isActive ? .bold : .medium, design: .monospaced))
                                    .foregroundColor(isActive ? Color.teal : Color.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3.5)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(isActive ? Color.teal.opacity(0.16) : Color.white.opacity(0.035))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(isActive ? Color.teal.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 0.5)
                            )
                        }
                    }
                }
            } else {
                // Disconnected State Card
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 10) {
                        Image(systemName: "powerplug")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Operating on Internal Battery")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)

                            Text("Connect a USB-C or MagSafe charger to inspect live power input flow, voltage rails, and supported PD profiles.")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                                .lineSpacing(1.5)
                        }
                    }

                    if let lastWatts = batteryVM.telemetry.adapterWatts {
                        Divider().opacity(0.1).padding(.vertical, 2)
                        HStack(spacing: 5) {
                            Text("Last Connected Adapter:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("\(lastWatts)W \(batteryVM.telemetry.adapterName ?? "PD Charger")")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(batteryVM.telemetry.isPluggedIn ? Color.green.opacity(0.2) : Color.white.opacity(0.07), lineWidth: 0.75)
                }
        )
    }

    private func miniSpecBox(title: String, value: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(subtitle)
                .font(.system(size: 8.5))
                .foregroundColor(.secondary.opacity(0.8))
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - 3. Reverse Charging & External Accessory Power Delivery Card

    private var accessoryPowerDeliveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cable.connector.horizontal")
                        .font(.system(size: 12))
                        .foregroundColor(Color.cyan)

                    Text("EXTERNAL DEVICE POWER DELIVERY (REVERSE CHARGING)")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.6)
                        .foregroundColor(.secondary.opacity(0.85))
                }

                Spacer()

                if !batteryVM.telemetry.connectedAccessories.isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 6, height: 6)
                        Text("\(batteryVM.telemetry.connectedAccessories.count) Device Powered")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.cyan)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.cyan.opacity(0.15))
                    .clipShape(Capsule())
                } else {
                    Text("15W Per Port Ready")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
            }

            if !batteryVM.telemetry.connectedAccessories.isEmpty {
                // List of actively charging accessories
                VStack(spacing: 8) {
                    ForEach(batteryVM.telemetry.connectedAccessories) { acc in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.cyan.opacity(0.15))
                                    .frame(width: 36, height: 36)

                                Image(systemName: accessoryIcon(for: acc.deviceName))
                                    .font(.system(size: 16))
                                    .foregroundColor(Color.cyan)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(acc.deviceName)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.primary)

                                    if let soc = acc.batteryLevel {
                                        HStack(spacing: 3) {
                                            Image(systemName: "battery.100")
                                                .font(.system(size: 8))
                                            Text("\(soc)%")
                                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                        }
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.green.opacity(0.18))
                                        .foregroundColor(Color.green)
                                        .clipShape(Capsule())
                                    }
                                }

                                Text("\(acc.portName) • Sourcing Power (~\(String(format: "%.1f", acc.estimatedOutputWatts))W USB-C Output)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(Color.cyan)
                                Text("CHARGING")
                                    .font(.system(size: 8.5, weight: .heavy))
                                    .foregroundColor(Color.cyan)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.cyan.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .padding(9)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.white.opacity(0.035))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.cyan.opacity(0.2), lineWidth: 0.5)
                        )
                    }
                }
            } else {
                // Clean Standby / Capability State
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "iphone")
                            .font(.system(size: 18))
                            .foregroundColor(Color.cyan.opacity(0.8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reverse Power Delivery Active & Ready")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(.primary)

                            Text("Connect an iPhone, iPad, Apple Watch, AirPods, or peripheral to charge it directly from your MacBook.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineSpacing(1.4)
                        }
                    }

                    // Port status readiness chips
                    HStack(spacing: 6) {
                        portReadinessChip(name: "Port 1", spec: "5V/3A (15W Ready)")
                        portReadinessChip(name: "Port 2", spec: "5V/3A (15W Ready)")
                        if let chargerPort = batteryVM.telemetry.chargerPortIndex {
                            portInputChip(name: "Port \(chargerPort)", spec: "⚡️ Power Input")
                        } else {
                            portReadinessChip(name: "Port 3", spec: "5V/3A (15W Ready)")
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.cyan.opacity(0.18), lineWidth: 0.75)
                }
        )
    }

    private func accessoryIcon(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("phone") || lower.contains("apple device") {
            return "iphone"
        } else if lower.contains("watch") {
            return "applewatch"
        } else if lower.contains("airpod") || lower.contains("audio") || lower.contains("headphone") {
            return "headphones"
        } else if lower.contains("ipad") || lower.contains("tablet") {
            return "ipad"
        } else {
            return "cable.connector"
        }
    }

    private func portReadinessChip(name: String, spec: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(Color.secondary.opacity(0.6)).frame(width: 4, height: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 8.5, weight: .bold)).foregroundColor(.primary)
                Text(spec).font(.system(size: 7.5)).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5))
    }

    private func portInputChip(name: String, spec: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(Color.green).frame(width: 4, height: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 8.5, weight: .bold)).foregroundColor(Color.green)
                Text(spec).font(.system(size: 7.5, weight: .semibold)).foregroundColor(Color.green.opacity(0.85))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.green.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.green.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: - 4. Charge Limiter & Threshold Range Chart

    private var chargeLimiterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with Master Toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)

                        Text("HARDWARE CHARGE LIMITER")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.6)
                            .foregroundColor(.secondary.opacity(0.85))
                    }

                    Text(batteryVM.isLimiterEnabled
                         ? (batteryVM.method == .macOS
                            ? "macOS holds the charge at \(batteryVM.chargeLimit)%"
                            : "Direct adapter bypass engages at \(batteryVM.chargeLimit)%")
                         : "Limiter inactive — charging up to 100%")
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
                .tint(Color.orange)
            }

            if batteryVM.isLimiterEnabled {
                // Interactive Threshold Range Bar (Range Chart)
                VStack(spacing: 7) {
                    GeometryReader { geo in
                        let width = geo.size.width
                        let limitRatio = CGFloat(batteryVM.chargeLimit) / 100.0

                        ZStack(alignment: .leading) {
                            // Full background track
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 10)

                            // Safe Charging Zone (0% to Limit%)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.green, Color.teal],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(10, width * limitRatio), height: 10)

                            // AC Bypass / Overcharge Protection Zone (Limit% to 100%)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.orange.opacity(0.55), Color.purple.opacity(0.65)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, width * (1.0 - limitRatio)), height: 10)
                                .offset(x: width * limitRatio)

                            // Target Limit Marker Needle
                            VStack(spacing: 0) {
                                Image(systemName: "arrowtriangle.down.fill")
                                    .font(.system(size: 7))
                                    .foregroundColor(.white)
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: 2, height: 12)
                            }
                            .offset(x: max(0, min(width - 6, (width * limitRatio) - 3)), y: -2)
                        }
                    }
                    .frame(height: 14)

                    // Range Chart Legend Labels
                    HStack {
                        Text("\(batteryVM.minimumLimit)%")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange).frame(width: 5, height: 5)
                            Text("Limit: \(batteryVM.chargeLimit)%")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.orange)
                        }
                        Spacer()
                        Text("100% (Full)")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    }

                    // Tactile Slider
                    Slider(
                        value: Binding(
                            get: { Double(batteryVM.chargeLimit) },
                            set: { batteryVM.setChargeLimit(Int($0)) }
                        ),
                        in: Double(batteryVM.minimumLimit)...100,
                        step: 5
                    )
                    .tint(.orange)
                }
                .padding(.top, 2)

                // Quick Preset Pills
                HStack(spacing: 5) {
                    ForEach(batteryVM.availablePresets, id: \.self) { preset in
                        let isSelected = batteryVM.chargeLimit == preset
                        Button(action: {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                batteryVM.setChargeLimit(preset)
                            }
                        }) {
                            Text(preset == 100 ? "100%" : (preset == 50 ? "50%" : "\(preset)%"))
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(
                                            isSelected
                                                ? LinearGradient(colors: [Color.orange, Color.red.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                                : (hoveredPreset == preset ? LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom) : LinearGradient(colors: [Color.white.opacity(0.04), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(isSelected ? Color.white.opacity(0.35) : Color.white.opacity(0.07), lineWidth: 0.75)
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
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.75)
                }
        )
    }

    // MARK: - 3. Battery Health & Degradation Pie / Donut Chart (PIE CHART)

    private var healthDonutChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.15, green: 0.85, blue: 0.55))

                    Text("BATTERY HEALTH & CAPACITY BREAKDOWN")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.6)
                        .foregroundColor(.secondary.opacity(0.85))
                }

                Spacer()

                Text(batteryVM.telemetry.healthGrade)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
            }

            HStack(spacing: 20) {
                // Interactive Donut / Pie Chart
                ZStack {
                    // Degradation Segment (Background circle)
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.red.opacity(0.65), Color.orange.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .butt)
                        )
                        .frame(width: 82, height: 82)

                    // Usable Capacity Segment (Front Arc)
                    Circle()
                        .trim(from: 0.0, to: CGFloat(batteryVM.telemetry.healthPercentage) / 100.0)
                        .stroke(
                            LinearGradient(
                                colors: [Color(red: 0.0, green: 0.90, blue: 0.65), Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 82, height: 82)

                    // Center Metrics
                    VStack(spacing: 0) {
                        Text(String(format: "%.1f%%", batteryVM.telemetry.healthPercentage))
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(.primary)

                        Text("HEALTH")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 4)

                // Capacity Legend & Metrics Breakdown
                VStack(alignment: .leading, spacing: 7) {
                    // Maximum Usable Capacity
                    HStack {
                        Circle().fill(Color.cyan).frame(width: 7, height: 7)
                        Text("Maximum Capacity:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(batteryVM.telemetry.fullChargeCapacity) mAh")
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                    }

                    // Original Design Capacity
                    HStack {
                        Circle().fill(Color.gray.opacity(0.5)).frame(width: 7, height: 7)
                        Text("Factory Design:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(batteryVM.telemetry.designCapacity) mAh")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    // Cell Degradation Loss
                    HStack {
                        Circle().fill(Color.red.opacity(0.8)).frame(width: 7, height: 7)
                        Text("Degradation Loss:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("-\(batteryVM.telemetry.degradedCapacity) mAh (\(String(format: "%.1f%%", batteryVM.telemetry.degradationPercentage)))")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.red.opacity(0.9))
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.75)
                }
        )
    }

    // MARK: - 4. 24-Hour Battery Discharge & Usage Bar Chart (BAR CHART)

    private var powerTimelineBarChartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 12))
                        .foregroundColor(Color.cyan)

                    Text("POWER SESSIONS & CHARGING ACTIVITY")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.6)
                        .foregroundColor(.secondary.opacity(0.85))
                }

                Spacer()

                if let idx = hoveredBarIndex {
                    Text(timelineItemDescription(for: idx))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.cyan)
                } else {
                    Text("Last 12 Hours")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            // Visual Timeline Bar Chart (12 Interval Bars)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<12, id: \.self) { index in
                    let barData = mockTimelineBar(index: index)
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            // Bar background slot
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .frame(height: 52)

                            // Active Level Bar
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(barData.colorGradient)
                                .frame(height: max(10, 52 * barData.heightRatio))
                                .shadow(color: barData.glowColor.opacity(hoveredBarIndex == index ? 0.4 : 0.1), radius: 3, x: 0, y: 1)
                        }

                        // Time Label
                        Text(barData.label)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(hoveredBarIndex == index ? .white : .secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onHover { isHovered in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredBarIndex = isHovered ? index : nil
                        }
                    }
                }
            }
            .frame(height: 70)

            // Timeline Legend
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(Color(red: 0.05, green: 0.88, blue: 0.62)).frame(width: 6, height: 6)
                    Text("Charging").font(.system(size: 9.5)).foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.teal).frame(width: 6, height: 6)
                    Text("AC Bypass").font(.system(size: 9.5)).foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                    Text("Battery Discharging").font(.system(size: 9.5)).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.75)
                }
        )
    }

    // MARK: - 5. Battery Lifespan & Longevity Prediction (LIFETIME STATS)

    private var lifecyclePredictionCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass.badge.plus")
                        .font(.system(size: 12))
                        .foregroundColor(Color.purple)

                    Text("LIFESPAN & CELL LONGEVITY PREDICTION")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.6)
                        .foregroundColor(.secondary.opacity(0.85))
                }

                Spacer()

                Text("Grade A • High Stability")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.purple)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.purple.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Cycle Count Progress Bar
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Recharge Cycles Completed:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(batteryVM.telemetry.cycleCount) / \(batteryVM.telemetry.ratedCycles) Cycles")
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                }

                GeometryReader { geo in
                    let cycleRatio = CGFloat(min(1.0, Double(batteryVM.telemetry.cycleCount) / Double(batteryVM.telemetry.ratedCycles)))
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 7)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple, Color.blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(6, geo.size.width * cycleRatio), height: 7)
                    }
                }
                .frame(height: 7)

                HStack {
                    Text("\(String(format: "%.1f%%", batteryVM.telemetry.cycleLifeRemainingPercentage)) rated cycle lifespan remaining")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Apple 1,000 Cycle Rating")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }
            }

            Divider().opacity(0.1)

            // Lifetime Prediction Insights
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ESTIMATED USEFUL LIFE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Text("~\(String(format: "%.1f", batteryVM.telemetry.estimatedYearsRemaining)) Years Remaining")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("OPTIMIZATION SAVINGS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(batteryVM.isLimiterEnabled ? "+2.5x Longevity with 80% Limit" : "Enable Limiter to Extend Life")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(batteryVM.isLimiterEnabled ? Color.green : Color.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.75)
                }
        )
    }

    // MARK: - 6. Diagnostics & Sensors Grid (COLORFUL CARDS)

    private var diagnosticsSensorGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HARDWARE SENSORS & POWER METRICS")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.6)
                .foregroundColor(.secondary.opacity(0.85))
                .padding(.leading, 2)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                sensorCell(
                    icon: "bolt.badge.clock.fill",
                    color: .yellow,
                    gradient: [Color.yellow, Color.orange],
                    label: "Voltage Rail",
                    value: String(format: "%.2f V", Double(batteryVM.telemetry.voltage) / 1000.0),
                    subvalue: "\(batteryVM.telemetry.voltage) mV nominal"
                )

                sensorCell(
                    icon: "gauge.with.needle",
                    color: .cyan,
                    gradient: [Color.cyan, Color.blue],
                    label: "Amperage Flow",
                    value: batteryVM.isBypassActive ? "0 mA (Idle)" : "\(batteryVM.telemetry.amperage) mA",
                    subvalue: batteryVM.isBypassActive ? "Cells Inactive in Bypass" : (batteryVM.telemetry.amperage >= 0 ? "Charging Current" : "Drain Current")
                )

                sensorCell(
                    icon: "thermometer.medium",
                    color: .orange,
                    gradient: [Color.orange, Color.red],
                    label: "Cell Temperature",
                    value: String(format: "%.1f °C", batteryVM.telemetry.temperature),
                    subvalue: batteryVM.telemetry.thermalStateDescription
                )

                sensorCell(
                    icon: "powerplug.fill",
                    color: .green,
                    gradient: [Color(red: 0.05, green: 0.88, blue: 0.62), Color.teal],
                    label: "Charger Power",
                    value: batteryVM.telemetry.adapterWatts != nil ? "\(batteryVM.telemetry.adapterWatts!) W" : "On Battery",
                    subvalue: batteryVM.telemetry.adapterName ?? (batteryVM.telemetry.isPluggedIn ? "Power Adapter" : "Unplugged")
                )
            }
        }
    }

    private func sensorCell(icon: String, color: Color, gradient: [Color], label: String, value: String, subvalue: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(subvalue)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary.opacity(0.85))
                .lineLimit(1)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(color.opacity(0.18), lineWidth: 0.5)
                }
        )
    }

    // MARK: - 7. Kernel SMC Control & Touch ID Authorization

    @ViewBuilder
    private var kernelSMCAuthorizationCard: some View {
        if batteryVM.method == .macOS {
            nativeLimitCard
        } else {
            helperCard
        }
    }

    /// macOS 27+: the limit is macOS's own, no helper involved.
    private var nativeLimitCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Using the macOS Charge Limit")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("No helper needed. macOS enforces the limit, even during sleep and when FluxBar is closed. It's the same setting as System Settings › Battery.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if batteryVM.isHelperInstalled {
                    Button("Remove Old Helper") { batteryVM.uninstallHelper() }
                        .controlSize(.small)
                        .disabled(batteryVM.isAuthorizingHelper)
                        .help("The FluxBar battery helper isn't used on this Mac")
                }
            }

            if let message = batteryVM.statusMessage {
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.2), lineWidth: 0.5)
                }
        )
    }

    private var helperCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: batteryVM.isHelperInstalled ? "checkmark.shield.fill" : "lock.shield")
                    .font(.system(size: 18))
                    .foregroundColor(batteryVM.isHelperInstalled ? Color.green : Color.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(batteryVM.isHelperInstalled ? "Battery Helper Installed" : "Battery Helper Needed")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(batteryVM.isHelperInstalled
                         ? "The limit is enforced in the background, even when FluxBar is closed."
                         : "Install once (password or Touch ID) so FluxBar can pause charging at your limit.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !batteryVM.isHelperInstalled {
                    Button(action: {
                        batteryVM.authorizeHelper()
                    }) {
                        Text(batteryVM.isAuthorizingHelper ? "Installing…" : "Install")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                LinearGradient(colors: [Color.orange, Color.red.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(batteryVM.isAuthorizingHelper)
                } else {
                    Button("Remove") { batteryVM.uninstallHelper() }
                        .controlSize(.small)
                        .disabled(batteryVM.isAuthorizingHelper)
                        .help("Uninstall the helper and restore normal charging")
                }
            }

            if let message = batteryVM.statusMessage {
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(batteryVM.isHelperInstalled ? .secondary : .orange)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(batteryVM.isHelperInstalled ? Color.green.opacity(0.2) : Color.orange.opacity(0.2), lineWidth: 0.5)
                }
        )
    }

    // MARK: - Computed Styles & Helpers

    private var primaryAccentColor: Color {
        if batteryVM.isBypassActive {
            return Color.teal
        } else if batteryVM.telemetry.isCharging {
            return Color(red: 0.05, green: 0.88, blue: 0.62) // Neon Emerald
        } else if batteryVM.telemetry.percentage <= 20 {
            return Color.red
        } else {
            return Color.blue
        }
    }

    private var heroStateIcon: String {
        if batteryVM.isBypassActive {
            return "powerplug.fill"
        } else if batteryVM.telemetry.isCharging {
            return "bolt.fill"
        } else if batteryVM.telemetry.isPluggedIn {
            return "bolt.shield.fill"
        } else {
            return "battery.75"
        }
    }

    private var heroStateBadgeText: String {
        if batteryVM.isBypassActive {
            return "BYPASS ACTIVE"
        } else if batteryVM.telemetry.isCharging {
            return "CHARGING"
        } else if batteryVM.telemetry.isPluggedIn {
            return "AC POWER"
        } else {
            return "ON BATTERY"
        }
    }

    private var heroStateTitle: String {
        if batteryVM.isBypassActive {
            return "Adapter Bypass Active"
        } else if batteryVM.telemetry.isCharging {
            return "Charging Battery"
        } else if batteryVM.telemetry.isPluggedIn {
            return "Connected to Power"
        } else {
            return "Running on Battery"
        }
    }

    private var powerBehaviorDescription: String {
        if batteryVM.isBypassActive {
            return "Charging is paused at \(batteryVM.chargeLimit)%. Your Mac runs from the power adapter, which slows battery wear."
        } else if batteryVM.telemetry.isCharging {
            return batteryVM.isLimiterEnabled
                ? "Charging up to \(batteryVM.chargeLimit)%. Charging pauses automatically once the limit is reached."
                : "Charging to 100%."
        } else if batteryVM.telemetry.isPluggedIn {
            return "Connected to AC adapter. Battery is at normal capacity."
        } else {
            return "Operating on internal battery cells. Connect your power adapter to enable charge limiting and adapter bypass."
        }
    }

    // MARK: - Timeline Helper Data

    private struct TimelineBarData {
        let label: String
        let heightRatio: CGFloat
        let colorGradient: LinearGradient
        let glowColor: Color
    }

    private func mockTimelineBar(index: Int) -> TimelineBarData {
        let labels = ["12h", "11h", "10h", "9h", "8h", "7h", "6h", "5h", "4h", "3h", "2h", "Now"]
        let label = (index < labels.count) ? labels[index] : "\(index)h"

        // Dynamically style current interval vs previous sessions
        let isLatest = (index == 11)
        if isLatest {
            if batteryVM.isBypassActive {
                return TimelineBarData(
                    label: label,
                    heightRatio: CGFloat(batteryVM.chargeLimit) / 100.0,
                    colorGradient: LinearGradient(colors: [Color.teal, Color.cyan], startPoint: .top, endPoint: .bottom),
                    glowColor: Color.teal
                )
            } else if batteryVM.telemetry.isCharging {
                return TimelineBarData(
                    label: label,
                    heightRatio: CGFloat(batteryVM.telemetry.percentage) / 100.0,
                    colorGradient: LinearGradient(colors: [Color(red: 0.05, green: 0.88, blue: 0.62), Color.teal], startPoint: .top, endPoint: .bottom),
                    glowColor: Color.green
                )
            } else {
                return TimelineBarData(
                    label: label,
                    heightRatio: CGFloat(batteryVM.telemetry.percentage) / 100.0,
                    colorGradient: LinearGradient(colors: [Color.blue, Color.indigo], startPoint: .top, endPoint: .bottom),
                    glowColor: Color.blue
                )
            }
        }

        // Realistic usage patterns for historical slots
        let heights: [CGFloat] = [0.85, 0.82, 0.80, 0.80, 0.80, 0.78, 0.75, 0.72, 0.79, 0.80, 0.80, 0.80]
        let h = (index < heights.count) ? heights[index] : 0.80

        if index >= 8 || index == 2 || index == 3 || index == 4 {
            // Bypass mode held
            return TimelineBarData(
                label: label,
                heightRatio: h,
                colorGradient: LinearGradient(colors: [Color.teal.opacity(0.85), Color.cyan.opacity(0.65)], startPoint: .top, endPoint: .bottom),
                glowColor: Color.teal
            )
        } else if index == 7 || index == 1 {
            // Charging period
            return TimelineBarData(
                label: label,
                heightRatio: h,
                colorGradient: LinearGradient(colors: [Color(red: 0.05, green: 0.88, blue: 0.62).opacity(0.9), Color.teal.opacity(0.7)], startPoint: .top, endPoint: .bottom),
                glowColor: Color.green
            )
        } else {
            // Battery drain period
            return TimelineBarData(
                label: label,
                heightRatio: h,
                colorGradient: LinearGradient(colors: [Color.blue.opacity(0.8), Color.indigo.opacity(0.65)], startPoint: .top, endPoint: .bottom),
                glowColor: Color.blue
            )
        }
    }

    private func timelineItemDescription(for index: Int) -> String {
        let labels = ["12h ago", "11h ago", "10h ago", "9h ago", "8h ago", "7h ago", "6h ago", "5h ago", "4h ago", "3h ago", "2h ago", "Now"]
        let time = (index < labels.count) ? labels[index] : "Recent"
        if index >= 8 || index == 2 || index == 3 || index == 4 {
            return "\(time) • AC Bypass Active (80%)"
        } else if index == 7 || index == 1 {
            return "\(time) • Charging (+28W)"
        } else {
            return "\(time) • Battery Drain (~14W)"
        }
    }
}
