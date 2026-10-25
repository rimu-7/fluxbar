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
            // Top Preview & Badges
            HStack(alignment: .top, spacing: 6) {
                // Pin icon indicator if pinned
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                        .help("Pinned clip (will not be pruned)")
                }

                // Text preview
                Text(item.previewText)
                    .font(item.isCodeSnippet ? .system(size: 11.5, weight: .regular, design: .monospaced) : .system(size: 12.5, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelect()
                    }

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
                    .padding(.vertical, 2.5)
                    .background(Color.accentColor)
                    .cornerRadius(4)
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

            // Metadata & Action Buttons
            HStack(spacing: 8) {
                // Metadata (App, Time, Char count, Copy count)
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
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect()
                }

                Spacer()

                // Stable action buttons (opacity-based to eliminate row jitter)
                HStack(spacing: 4) {
                    // Copy button
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10.5))
                            .frame(width: 22, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Copy to clipboard (Return)")

                    // Pin / Unpin button
                    Button(action: onTogglePin) {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 10.5))
                            .foregroundColor(item.isPinned ? .orange : .primary)
                            .frame(width: 22, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(item.isPinned ? "Unpin clip (⌘P)" : "Pin clip (⌘P)")

                    // Delete button
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10.5))
                            .foregroundColor(.red.opacity(0.9))
                            .frame(width: 22, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Delete clip (⌫)")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(5)
                .opacity((isHovered || isSelected) ? 1.0 : 0.0)
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
            isHovered = hovering
        }
        .contextMenu {
            Button(action: onCopy) {
                Label("Copy to Clipboard", systemImage: "doc.on.doc")
            }
            Button(action: onTogglePin) {
                Label(item.isPinned ? "Unpin Clip" : "Pin Clip", systemImage: item.isPinned ? "pin.slash" : "pin")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete Clip", systemImage: "trash")
            }
        }
    }
}
