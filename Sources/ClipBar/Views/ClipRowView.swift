import SwiftUI
import ClipCore

public struct ClipRowView: View {
    public let item: ClipItem
    public let isSelected: Bool
    public let quickIndex: Int?
    public let isCopied: Bool
    public let onSelect: () -> Void
    public let onCopy: () -> Void
    public let onTogglePin: () -> Void
    public let onDelete: () -> Void

    @State private var isHovered: Bool = false

    public init(
        item: ClipItem,
        isSelected: Bool,
        quickIndex: Int?,
        isCopied: Bool,
        onSelect: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onTogglePin: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.isSelected = isSelected
        self.quickIndex = quickIndex
        self.isCopied = isCopied
        self.onSelect = onSelect
        self.onCopy = onCopy
        self.onTogglePin = onTogglePin
        self.onDelete = onDelete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                // Pin icon indicator if pinned
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                }

                // Text preview
                Text(item.previewText)
                    .font(item.isCodeSnippet ? .system(size: 11.5, weight: .regular, design: .monospaced) : .system(size: 12.5, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                // Quick copy keyboard shortcut pill or Copied indicator
                if isCopied {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Copied!")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .cornerRadius(4)
                    .transition(.opacity.combined(with: .scale))
                } else if let quickIndex = quickIndex {
                    Text("⌘\(quickIndex)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                }
            }

            // Metadata & Hover Action Bar
            HStack(spacing: 8) {
                // Source App & Time
                HStack(spacing: 4) {
                    if let appName = item.sourceAppName, !appName.isEmpty {
                        Image(systemName: "app.badge")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(appName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.5))
                    }

                    Text(item.relativeTimeText)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("\(item.charCount)c")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)

                    if item.copyCount > 1 {
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("\(item.copyCount)x")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.accentColor)
                    }
                }

                Spacer()

                // Action buttons on hover or selection
                if isHovered || isSelected {
                    HStack(spacing: 4) {
                        Button(action: onCopy) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .help("Copy (Return)")

                        Button(action: onTogglePin) {
                            Image(systemName: item.isPinned ? "pin.slash" : "pin")
                                .font(.system(size: 10))
                                .foregroundColor(item.isPinned ? .orange : .primary)
                        }
                        .buttonStyle(.plain)
                        .help(item.isPinned ? "Unpin (⌘P)" : "Pin (⌘P)")

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Delete (⌫)")
                    }
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onSelect()
        }
    }
}
