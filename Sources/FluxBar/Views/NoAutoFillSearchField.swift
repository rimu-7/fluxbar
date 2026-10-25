import AppKit
import SwiftUI

/// Custom AppKit-backed Search Field with macOS AutoFill, Text Completion,
/// Autocorrection, Smart Substitutions, and Suggestions completely disabled.
public struct NoAutoFillSearchField: NSViewRepresentable {
    @Binding public var text: String
    public var placeholder: String
    public var onSubmit: (() -> Void)?
    public var onArrowDown: (() -> Void)?
    public var onArrowUp: (() -> Void)?
    public var onEscape: (() -> Void)?

    public init(
        placeholder: String = "Search clips (FTS5)...",
        text: Binding<String>,
        onSubmit: (() -> Void)? = nil,
        onArrowDown: (() -> Void)? = nil,
        onArrowUp: (() -> Void)? = nil,
        onEscape: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.onSubmit = onSubmit
        self.onArrowDown = onArrowDown
        self.onArrowUp = onArrowUp
        self.onEscape = onEscape
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NoAutoFillNSTextField {
        let textField = NoAutoFillNSTextField()
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 12.5)
        textField.textColor = .labelColor
        textField.placeholderString = placeholder
        textField.isEditable = true
        textField.isSelectable = true
        textField.delegate = context.coordinator
        textField.allowsCharacterPickerTouchBarItem = false

        // Disable completion and AutoFill
        textField.isAutomaticTextCompletionEnabled = false

        if #available(macOS 11.0, *) {
            textField.contentType = nil
        }

        context.coordinator.textField = textField
        return textField
    }

    public func updateNSView(_ nsView: NoAutoFillNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    public final class Coordinator: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
        var parent: NoAutoFillSearchField
        weak var textField: NoAutoFillNSTextField?

        init(_ parent: NoAutoFillSearchField) {
            self.parent = parent
        }

        public func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit?()
                return true
            } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onArrowDown?()
                return true
            } else if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onArrowUp?()
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape?()
                return true
            }
            return false
        }

        // Return empty completions to prevent system auto-completion / dropdown popups
        public func control(
            _ control: NSControl,
            textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>
        ) -> [String] {
            return []
        }

        // Return empty candidates to prevent system candidate bar
        public func textView(_ textView: NSTextView, candidatesForSelectedRange selectedRange: NSRange) -> [Any]? {
            return []
        }

        public func textView(_ textView: NSTextView, shouldSelectCandidateAt index: Int) -> Bool {
            return false
        }

        public func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            // Strip any macOS AutoFill menu items from right-click context menu
            menu.items.removeAll { item in
                let title = item.title.lowercased()
                return title.contains("autofill") || title.contains("auto-fill") || title.contains("passwords")
            }
            return menu
        }
    }
}

public final class NoAutoFillNSTextField: NSTextField {
    @available(macOS 11.0, *)
    public override var contentType: NSTextContentType? {
        get { nil }
        set { }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }
    }

    public override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        // Hard-disable AutoFill & spellcheck on the field editor (NSTextView)
        if let editor = currentEditor() as? NSTextView {
            editor.isAutomaticTextCompletionEnabled = false
            editor.isAutomaticSpellingCorrectionEnabled = false
            editor.isContinuousSpellCheckingEnabled = false
            editor.isGrammarCheckingEnabled = false
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticTextReplacementEnabled = false
            editor.isAutomaticDataDetectionEnabled = false
            editor.isAutomaticLinkDetectionEnabled = false
            editor.smartInsertDeleteEnabled = false
            if #available(macOS 11.0, *) {
                editor.contentType = nil
            }
        }
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        menu.items.removeAll { item in
            let title = item.title.lowercased()
            return title.contains("autofill") || title.contains("auto-fill") || title.contains("passwords")
        }
        return menu
    }
}
