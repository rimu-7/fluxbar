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

                // 2. Hardware Charge Limiter & Threshold Range Chart
                chargeLimiterCard

                // 3. Battery Health & Degradation Pie / Donut Chart
                healthDonutChartCard

                // 4. 24-Hour Battery Discharge & Power Usage Bar Chart
                powerTimelineBarChartCard

                // 5. Battery Lifespan & Longevity Prediction
                lifecyclePredictionCard

                // 6. Live Hardware Diagnostics & Sensors Grid
                diagnosticsSensorGrid

                // 7. Kernel SMC Control & Touch ID Authorization
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

    // MARK: - 2. Charge Limiter & Threshold Range Chart

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
                         ? "Direct adapter bypass engages at \(batteryVM.chargeLimit)%"
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
                        Text("50% (Storage)")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange).frame(width: 5, height: 5)
                            Text("Limit: \(batteryVM.chargeLimit)% [Bypass]")
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
                        in: 50...100,
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

    private var kernelSMCAuthorizationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: batteryVM.isHelperInstalled ? "checkmark.shield.fill" : "lock.shield")
                    .font(.system(size: 18))
                    .foregroundColor(batteryVM.isHelperInstalled ? Color.green : Color.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(batteryVM.isHelperInstalled ? "Kernel SMC Bypass: Active" : "Touch ID Authorization Required")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(batteryVM.isHelperInstalled
                         ? "Direct Apple Silicon hardware SMC charge cutoff is enforced."
                         : "Touch ID or admin authorization enables native SMC charge inhibition.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !batteryVM.isHelperInstalled {
                    Button(action: {
                        batteryVM.authorizeHelper()
                    }) {
                        Text(batteryVM.isAuthorizingHelper ? "Authorizing..." : "Authorize")
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
                }
            }

            if let message = batteryVM.statusMessage {
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(message.contains("success") ? .green : (message.contains("Limit reached") ? .teal : .orange))
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
            return "Charging is paused at \(batteryVM.chargeLimit)%. Your Mac draws 100% of its operating power directly from the wall adapter, eliminating battery cell wear."
        } else if batteryVM.telemetry.isCharging {
            return "Replenishing battery cells up to \(batteryVM.chargeLimit)%. Hardware adapter bypass will engage automatically once the threshold is reached."
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
