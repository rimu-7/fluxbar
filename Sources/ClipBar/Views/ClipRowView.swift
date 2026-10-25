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
        HStack(alignment: .top, spacing: 9) {
            // Pin Button with Glass Squircle
            Button(action: onTogglePin) {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: item.isPinned ? .bold : .medium))
                    .foregroundColor(item.isPinned ? .orange : (isHovered || isSelected ? .primary.opacity(0.75) : .secondary.opacity(0.35)))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6.5)
                            .fill(item.isPinned ? Color.orange.opacity(0.18) : (isHovered ? Color.white.opacity(0.08) : Color.clear))
                            .overlay {
                                if item.isPinned {
                                    RoundedRectangle(cornerRadius: 6.5)
                                        .strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.5)
                                } else if isHovered {
                                    RoundedRectangle(cornerRadius: 6.5)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                                }
                            }
                    )
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

                // Metadata Footer with Glowing Badges
                HStack(spacing: 4.5) {
                    if item.isCodeSnippet {
                        Text("CODE")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule()
                                    .fill(Color.cyan.opacity(0.16))
                                    .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.4), lineWidth: 0.5))
                            )
                        Text("•")
                            .font(.system(size: 8.5))
                            .foregroundColor(.secondary.opacity(0.4))
                    } else if item.isDocument {
                        Text("DOC")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule()
                                    .fill(Color.purple.opacity(0.16))
                                    .overlay(Capsule().strokeBorder(Color.purple.opacity(0.4), lineWidth: 0.5))
                            )
                        Text("•")
                            .font(.system(size: 8.5))
                            .foregroundColor(.secondary.opacity(0.4))
                    } else if item.isFile {
                        Text("FILE")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.teal)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule()
                                    .fill(Color.teal.opacity(0.16))
                                    .overlay(Capsule().strokeBorder(Color.teal.opacity(0.4), lineWidth: 0.5))
                            )
                        Text("•")
                            .font(.system(size: 8.5))
                            .foregroundColor(.secondary.opacity(0.4))
                    }

                    if let appName = item.sourceAppName, !appName.isEmpty {
                        Image(systemName: "app.badge")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.8))
                        Text(appName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Text("•")
                            .font(.system(size: 8.5))
                            .foregroundColor(.secondary.opacity(0.4))
                    }

                    Text(item.relativeTimeText)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))

                    Text("•")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("\(item.charCount)c")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))

                    if item.copyCount > 1 {
                        Text("•")
                            .font(.system(size: 8.5))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("\(item.copyCount)x")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
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
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
                            .shadow(color: Color.accentColor.opacity(0.35), radius: 3, x: 0, y: 1)
                    )
                } else if let quickIndex = quickIndex {
                    Text("⌘\(quickIndex)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.9))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4.5)
                                .fill(Color.white.opacity(0.08))
                                .overlay(RoundedRectangle(cornerRadius: 4.5).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                        )
                }

                Spacer()

                // Direct Action Buttons (Copy & Delete)
                HStack(spacing: 3) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(isHovered || isSelected ? .primary.opacity(0.85) : .secondary.opacity(0.4))
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 5.5)
                                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
                                    .overlay {
                                        if isHovered {
                                            RoundedRectangle(cornerRadius: 5.5)
                                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                                        }
                                    }
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard (Return)")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.red.opacity(isHovered || isSelected ? 0.9 : 0.45))
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 5.5)
                                    .fill(isHovered ? Color.red.opacity(0.14) : Color.clear)
                                    .overlay {
                                        if isHovered {
                                            RoundedRectangle(cornerRadius: 5.5)
                                                .strokeBorder(Color.red.opacity(0.3), lineWidth: 0.5)
                                        }
                                    }
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Delete clip (⌘⌫)")
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isSelected
                        ? LinearGradient(
                            colors: [Color.accentColor.opacity(0.26), Color.accentColor.opacity(0.14)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : (isHovered
                            ? LinearGradient(
                                colors: [Color.white.opacity(0.09), Color.white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.white.opacity(0.035), Color.white.opacity(0.01)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isSelected
                                ? LinearGradient(
                                    colors: [Color.accentColor.opacity(0.85), Color.accentColor.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : (isHovered
                                    ? LinearGradient(
                                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [Color.white.opacity(0.07), Color.clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )),
                            lineWidth: isSelected ? 1.2 : 0.6
                        )
                }
                .shadow(
                    color: isSelected ? Color.accentColor.opacity(0.18) : (isHovered ? Color.black.opacity(0.08) : Color.clear),
                    radius: isSelected ? 4 : 2,
                    x: 0,
                    y: 1
                )
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
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
