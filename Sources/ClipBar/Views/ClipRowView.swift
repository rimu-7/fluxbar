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
        HStack(alignment: .top, spacing: 8) {
            // Direct Pin Button (Always accessible)
            Button(action: onTogglePin) {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: item.isPinned ? .bold : .regular))
                    .foregroundColor(item.isPinned ? .orange : (isHovered || isSelected ? .secondary : .secondary.opacity(0.4)))
                    .frame(width: 22, height: 22)
                    .background(item.isPinned ? Color.orange.opacity(0.12) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
                    .cornerRadius(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.isPinned ? "Unpin clip (⌘P)" : "Pin clip (⌘P)")
            .padding(.top, 1)

            // Middle Content: Preview and Metadata (Click to select & copy)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.previewText)
                    .font(item.isCodeSnippet ? .system(size: 11.5, weight: .regular, design: .monospaced) : .system(size: 12.5, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                // Metadata Footer
                HStack(spacing: 4) {
                    if item.isCodeSnippet {
                        Text("CODE")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(3)
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.5))
                    } else if item.isDocument {
                        Text("DOC")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.12))
                            .cornerRadius(3)
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.5))
                    } else if item.isFile {
                        Text("FILE")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.teal)
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1)
                            .background(Color.teal.opacity(0.12))
                            .cornerRadius(3)
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.5))
                    }

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
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect()
            }

            // Right Action Controls: Quick Badge, Copy & Delete Buttons
            VStack(alignment: .trailing, spacing: 6) {
                if isCopied {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                        Text("Copied!")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .cornerRadius(4)
                } else if let quickIndex = quickIndex {
                    Text("⌘\(quickIndex)")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                }

                Spacer()

                // Direct Action Buttons (Copy & Delete)
                HStack(spacing: 3) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(isHovered || isSelected ? 0.9 : 0.45))
                            .frame(width: 20, height: 20)
                            .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
                            .cornerRadius(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard (Return)")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(.red.opacity(isHovered || isSelected ? 0.85 : 0.45))
                            .frame(width: 20, height: 20)
                            .background(isHovered ? Color.red.opacity(0.08) : Color.clear)
                            .cornerRadius(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete clip (⌘⌫)")
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
                .stroke(isSelected ? Color.accentColor.opacity(0.4) : (item.isPinned ? Color.orange.opacity(0.3) : Color.clear), lineWidth: 1)
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
