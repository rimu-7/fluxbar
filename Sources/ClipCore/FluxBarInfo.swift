import Foundation

/// Single source of truth for the release version.
/// `scripts/build-app.sh` reads this line to stamp Info.plist, so keep the format `version = "x.y.z"`.
public enum FluxBarInfo {
    public static let version = "1.2.1"
    public static let bundleIdentifier = "com.fluxbar.FluxBar"
}
