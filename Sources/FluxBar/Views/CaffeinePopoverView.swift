import SwiftUI

@MainActor
public struct CaffeinePopoverView: View {
    @ObservedObject private var caffeine = CaffeineManager.shared

    private let accent = FluxBarTab.caffeine.accentColor

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header

            Divider().opacity(0.2)

            VStack(spacing: 0) {
                Spacer(minLength: 16)

                VStack(spacing: 12) {
                    Text("Keep your screen awake.")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("Read, present, or focus without your display going to sleep.")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                        .frame(maxWidth: 360)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 24)

                sessionTimer

                Spacer(minLength: 24)

                VStack(spacing: 16) {
                    awakeControl

                    Text("Closing this popover won’t end your session.\nTurn Caffeine off to restore normal display sleep.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "cup.and.saucer.fill")
                .foregroundColor(accent)
            Text("Caffeine")
                .fontWeight(.semibold)

            Spacer()

            Text(caffeine.isActive ? "Active" : "Off")
                .foregroundColor(caffeine.isActive ? accent : .secondary)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.14))
    }

    private var sessionTimer: some View {
        VStack(spacing: 8) {
            Group {
                if caffeine.isActive, let since = caffeine.activeSince {
                    Text(since, style: .timer)
                } else {
                    Text("0:00")
                }
            }
            .font(.system(size: 76, weight: .light, design: .rounded))
            .monospacedDigit()
            .foregroundColor(caffeine.isActive ? accent : .primary.opacity(0.6))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .frame(maxWidth: .infinity)

            Text(caffeine.isActive ? "Time kept awake" : "Ready to start your session")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var awakeControl: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Keep awake")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Text(caffeine.isActive ? "On · Your display stays awake" : "Off · Normal display sleep")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Toggle("Keep display awake", isOn: $caffeine.isActive)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(accent)
                .help(caffeine.isActive ? "Allow the display to sleep" : "Keep the display awake")
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
