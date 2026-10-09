import AppKit
import SwiftUI

struct EditorTextView: NSViewRepresentable {
    let document: TextDocument
    let displayFont: NSFont
    let wordWrap: Bool
    let backgroundColor: NSColor
    let textColor: NSColor
    let isSelected: Bool
    /// `false`, solange ein Aufklappfeld über dem Text liegt: Der Text nimmt dann
    /// keine Eingaben an und zeigt auch keinen Text-Cursor.
    let isInteractive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let textView = NSTextView(frame: .zero)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = document.text
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        document.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator

        if coordinator.appliedFont != displayFont {
            coordinator.appliedFont = displayFont
            textView.font = displayFont
        }
        if coordinator.appliedBackground != backgroundColor {
            coordinator.appliedBackground = backgroundColor
            textView.backgroundColor = backgroundColor
            scrollView.backgroundColor = backgroundColor
        }
        if coordinator.appliedTextColor != textColor {
            coordinator.appliedTextColor = textColor
            textView.textColor = textColor
            textView.insertionPointColor = textColor
        }
        if coordinator.appliedInteractive != isInteractive {
            coordinator.appliedInteractive = isInteractive
            textView.isSelectable = isInteractive
            textView.isEditable = isInteractive
            textView.window?.invalidateCursorRects(for: textView)
            if isInteractive && isSelected {
                DispatchQueue.main.async {
                    textView.window?.makeFirstResponder(textView)
                }
            }
        }
        if coordinator.appliedWrap != wordWrap {
            coordinator.appliedWrap = wordWrap
            applyWordWrap(to: textView, in: scrollView)
        }
        if coordinator.wasSelected != isSelected {
            coordinator.wasSelected = isSelected
            if isSelected {
                DispatchQueue.main.async {
                    textView.window?.makeFirstResponder(textView)
                }
            }
        }
    }

    private func applyWordWrap(to textView: NSTextView, in scrollView: NSScrollView) {
        let unlimited = CGFloat.greatestFiniteMagnitude
        if wordWrap {
            let width = scrollView.contentSize.width
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.containerSize = NSSize(width: width, height: unlimited)
            textView.textContainer?.widthTracksTextView = true
            textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
            scrollView.hasHorizontalScroller = false
        } else {
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: unlimited, height: unlimited)
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = [.width, .height]
            scrollView.hasHorizontalScroller = true
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let document: TextDocument
        var appliedFont: NSFont?
        var appliedWrap: Bool?
        var appliedInteractive: Bool?
        var appliedBackground: NSColor?
        var appliedTextColor: NSColor?
        var wasSelected: Bool?

        init(document: TextDocument) {
            self.document = document
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            document.text = textView.string
            if !document.isDirty {
                document.isDirty = true
            }
        }
    }
}
