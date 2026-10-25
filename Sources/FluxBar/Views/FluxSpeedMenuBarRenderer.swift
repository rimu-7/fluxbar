import AppKit
import Foundation

/// Pixel-perfect CoreGraphics / AppKit menu bar speed meter renderer for FluxBar
/// Conforms strictly to the 4 Dynamic States spec:
/// 1. IDLE (Both Dimmed 40%):           ↑ 0.0 KB/s (Dim)    ↓ 0.0 KB/s (Dim)
/// 2. DOWNLOADING (Bottom Bright 100%):  ↑ 0.0 KB/s (Dim)    ↓ 24.8 MB/s (Bright)
/// 3. UPLOADING (Top Bright 100%):      ↑ 4.2 MB/s (Bright) ↓ 0.0 KB/s (Dim)
/// 4. FULL TRAFFIC (Both Bright 100%):   ↑ 18.5 MB/s (Bright) ↓ 112.0 MB/s (Bright)
public enum FluxSpeedMenuBarRenderer {
    public struct FormattedSpeedState: Equatable, Sendable {
        public let uploadValue: String
        public let uploadUnit: String
        public let isUploadDimmed: Bool
        public let downloadValue: String
        public let downloadUnit: String
        public let isDownloadDimmed: Bool

        public init(
            uploadValue: String,
            uploadUnit: String,
            isUploadDimmed: Bool,
            downloadValue: String,
            downloadUnit: String,
            isDownloadDimmed: Bool
        ) {
            self.uploadValue = uploadValue
            self.uploadUnit = uploadUnit
            self.isUploadDimmed = isUploadDimmed
            self.downloadValue = downloadValue
            self.downloadUnit = downloadUnit
            self.isDownloadDimmed = isDownloadDimmed
        }
    }

    /// Formats live raw byte rates into the 3-column components
    public static func format(uploadBytes: Double, downloadBytes: Double) -> FormattedSpeedState {
        let (upVal, upUnit, upDim) = formatRate(uploadBytes)
        let (downVal, downUnit, downDim) = formatRate(downloadBytes)
        return FormattedSpeedState(
            uploadValue: upVal,
            uploadUnit: upUnit,
            isUploadDimmed: upDim,
            downloadValue: downVal,
            downloadUnit: downUnit,
            isDownloadDimmed: downDim
        )
    }

    public static func formatRate(_ bytesPerSec: Double) -> (value: String, unit: String, isDimmed: Bool) {
        if bytesPerSec <= 0.0 {
            return ("0.0", "KB/s", true)
        }
        let kb = bytesPerSec / 1024.0
        if kb < 0.05 {
            return ("0.0", "KB/s", true)
        } else if kb < 1000.0 {
            return (String(format: "%.1f", kb), "KB/s", false)
        }
        let mb = kb / 1024.0
        if mb < 1000.0 {
            return (String(format: "%.1f", mb), "MB/s", false)
        }
        let gb = mb / 1024.0
        return (String(format: "%.1f", gb), "GB/s", false)
    }

    /// Renders a template NSImage matching the pixel-perfect layout spec:
    /// - Canvas: 58 pt wide × 22 pt high (standard macOS menu bar height)
    /// - Column 1: Arrows (`↑`/`↓`) | Width: 10 pt | Center (x: 2pt) | 8.5pt Heavy
    /// - Column 2: Numbers (`0.0`-`999`) | Width: 26 pt | Right-Aligned | 9.0pt Monospaced Tabular
    /// - Column 3: Units (`KB/s`, `MB/s`) | Width: 20 pt | Left (x: 37pt) | 8.5pt Medium
    /// - Row 1 (Top — Upload): y: 1pt | Dims to 40% at 0.0 KB/s
    /// - Row 2 (Bottom — Download): y: 11pt | Dims to 40% at 0.0 KB/s
    public static func renderImage(for state: FormattedSpeedState) -> NSImage {
        let canvasSize = NSSize(width: 58.0, height: 22.0)

        let image = NSImage(size: canvasSize, flipped: true) { _ in
            // Row 1: Upload (y: 1.0)
            renderRow(
                arrow: "↑",
                value: state.uploadValue,
                unit: state.uploadUnit,
                isDimmed: state.isUploadDimmed,
                rowY: 1.0
            )

            // Row 2: Download (y: 11.0)
            renderRow(
                arrow: "↓",
                value: state.downloadValue,
                unit: state.downloadUnit,
                isDimmed: state.isDownloadDimmed,
                rowY: 11.0
            )

            return true
        }

        image.isTemplate = true
        return image
    }

    private static func renderRow(
        arrow: String,
        value: String,
        unit: String,
        isDimmed: Bool,
        rowY: CGFloat
    ) {
        let alpha: CGFloat = isDimmed ? 0.40 : 1.00
        let textColor = NSColor.black.withAlphaComponent(alpha)
        let rowHeight: CGFloat = 10.0

        // Column 1: Arrow (`↑`/`↓`) — 10 pt, Center at x: 2pt, 8.5pt Heavy
        let arrowStyle = NSMutableParagraphStyle()
        arrowStyle.alignment = .center
        let arrowFont = NSFont.systemFont(ofSize: 8.5, weight: .heavy)
        let arrowAttrs: [NSAttributedString.Key: Any] = [
            .font: arrowFont,
            .foregroundColor: textColor,
            .paragraphStyle: arrowStyle
        ]
        let arrowSize = (arrow as NSString).size(withAttributes: arrowAttrs)
        let arrowRect = CGRect(
            x: 2.0,
            y: rowY + (rowHeight - arrowSize.height) / 2.0,
            width: 10.0,
            height: arrowSize.height
        )
        (arrow as NSString).draw(in: arrowRect, withAttributes: arrowAttrs)

        // Column 2: Number — 26 pt, Right-Aligned ending at x: 36pt, 9.0pt Monospaced Tabular
        let numStyle = NSMutableParagraphStyle()
        numStyle.alignment = .right
        let numFont = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .medium)
        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: numFont,
            .foregroundColor: textColor,
            .paragraphStyle: numStyle
        ]
        let numSize = (value as NSString).size(withAttributes: numAttrs)
        let numRect = CGRect(
            x: 10.0,
            y: rowY + (rowHeight - numSize.height) / 2.0,
            width: 26.0,
            height: numSize.height
        )
        (value as NSString).draw(in: numRect, withAttributes: numAttrs)

        // Column 3: Unit — 20 pt, Left-Aligned starting at x: 37pt, 8.5pt Medium
        let unitStyle = NSMutableParagraphStyle()
        unitStyle.alignment = .left
        let unitFont = NSFont.systemFont(ofSize: 8.5, weight: .medium)
        let unitAttrs: [NSAttributedString.Key: Any] = [
            .font: unitFont,
            .foregroundColor: textColor,
            .paragraphStyle: unitStyle
        ]
        let unitSize = (unit as NSString).size(withAttributes: unitAttrs)
        let unitRect = CGRect(
            x: 37.0,
            y: rowY + (rowHeight - unitSize.height) / 2.0,
            width: 20.0,
            height: unitSize.height
        )
        (unit as NSString).draw(in: unitRect, withAttributes: unitAttrs)
    }
}
