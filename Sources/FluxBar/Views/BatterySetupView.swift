import SwiftUI
import PowerCore

/// The same graphical setup and recovery controls in Battery and Settings.
@MainActor
struct BatterySetupView: View {
    @ObservedObject var batteryVM: BatteryViewModel

    private var needsSetup: Bool {
        batteryVM.method == .helper && (!batteryVM.isHelperInstalled || batteryVM.helperNeedsUpdate)
    }

    private var title: String {
        if batteryVM.method == .unavailable { return "Charge limits unavailable on this Mac" }
        if batteryVM.method == .macOS { return "Battery controls ready" }
        if batteryVM.helperNeedsUpdate { return "Update battery controls" }
        return batteryVM.isHelperInstalled ? "Battery controls installed" : "Enable battery limit"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: batteryVM.method == .unavailable ? "info.circle" : (needsSetup ? "bolt.shield" : "checkmark.shield.fill"))
                    .font(.system(size: 18))
                    .foregroundColor(batteryVM.method == .unavailable ? .secondary : (needsSetup ? .orange : .green))

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if batteryVM.method == .helper {
                HStack {
                    if batteryVM.isAuthorizingHelper {
                        ProgressView().controlSize(.small)
                        Text("Waiting for macOS…").font(.system(size: 12))
                    } else {
                        Button(batteryVM.helperNeedsUpdate ? "Update" : (batteryVM.isHelperInstalled ? "Repair" : "Enable")) {
                            batteryVM.authorizeHelper()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        if batteryVM.isHelperInstalled {
                            Button("Remove Battery Helper") { batteryVM.uninstallHelper() }
                                .controlSize(.small)
                        }
                    }
                }
            } else if batteryVM.isHelperInstalled {
                Button("Remove Old Battery Helper") { batteryVM.uninstallHelper() }
                    .controlSize(.small)
                    .disabled(batteryVM.isAuthorizingHelper)
            }

            if let message = batteryVM.statusMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var description: String {
        if batteryVM.method == .unavailable {
            return "Charging control is not supported by this Mac’s hardware and macOS combination. Clipboard, network speed and Caffeine remain available."
        }
        if batteryVM.method == .macOS {
            return "macOS manages your charge limit directly. Choose a limit in the Battery tab."
        }
        if batteryVM.helperNeedsUpdate {
            return "Finish updating the battery controls included with this version of FluxBar. macOS will ask for administrator approval."
        }
        if batteryVM.isHelperInstalled {
            return "Battery controls are installed for background charging control. Use Repair if charging does not follow your limit."
        }
        return "Set up battery controls included with FluxBar. macOS will ask for administrator approval, then your limit can work even when the app is closed."
    }
}
