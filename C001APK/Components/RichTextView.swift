import SwiftUI
import UIKit

public struct RichTextView: UIViewRepresentable {
    public let html: String
    public var fontSize: CGFloat = 16
    public var textColor: UIColor = .label
    public var maxLines: Int = 0
    public var showEmoji: Bool = true
    public var isSelectableText: Bool = true
    public var onLinkTap: ((String) -> Void)?
    public var onCardTap: (() -> Void)?

    public init(
        html: String,
        fontSize: CGFloat = 16,
        textColor: UIColor = .label,
        maxLines: Int = 0,
        showEmoji: Bool = true,
        isSelectableText: Bool = true,
        onLinkTap: ((String) -> Void)? = nil,
        onCardTap: (() -> Void)? = nil
    ) {
        self.html = html
        self.fontSize = fontSize
        self.textColor = textColor
        self.maxLines = maxLines
        self.showEmoji = showEmoji
        self.isSelectableText = isSelectableText
        self.onLinkTap = onLinkTap
        self.onCardTap = onCardTap
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTap: onLinkTap, onCardTap: onCardTap)
    }

    public func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = isSelectableText
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.lineBreakMode = .byTruncatingTail
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.delegate = context.coordinator
        if !isSelectableText {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            view.addGestureRecognizer(tap)
            context.coordinator.tapRecognizer = tap
        }
        return view
    }

    public func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.isSelectable = isSelectableText
        context.coordinator.onLinkTap = onLinkTap
        context.coordinator.onCardTap = onCardTap
        uiView.textContainer.maximumNumberOfLines = maxLines
        uiView.attributedText = RichTextRenderer.attributedString(
            html: html,
            fontSize: fontSize,
            textColor: textColor,
            showEmoji: showEmoji
        )
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 340
        guard width > 0 else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }

    @MainActor
    public final class Coordinator: NSObject, UITextViewDelegate {
        var onLinkTap: ((String) -> Void)?
        var onCardTap: (() -> Void)?
        weak var tapRecognizer: UITapGestureRecognizer?

        init(onLinkTap: ((String) -> Void)?, onCardTap: (() -> Void)?) {
            self.onLinkTap = onLinkTap
            self.onCardTap = onCardTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = gesture.view as? UITextView else {
                onCardTap?()
                return
            }
            let location = gesture.location(in: textView)
            if let url = linkAt(point: location, in: textView) {
                onLinkTap?(url.absoluteString)
            } else {
                onCardTap?()
            }
        }

        private func linkAt(point: CGPoint, in textView: UITextView) -> URL? {
            guard textView.attributedText.length > 0 else { return nil }
            let adjusted = CGPoint(
                x: point.x - textView.textContainerInset.left,
                y: point.y - textView.textContainerInset.top
            )
            if let position = textView.closestPosition(to: adjusted) {
                let offset = textView.offset(from: textView.beginningOfDocument, to: position)
                let candidates = [offset, max(0, offset - 1)]
                for idx in candidates where idx >= 0 && idx < textView.attributedText.length {
                    if let link = textView.attributedText.attribute(.link, at: idx, effectiveRange: nil) {
                        if let url = link as? URL { return url }
                        if let str = link as? String, let url = URL(string: str) { return url }
                    }
                }
            }
            return nil
        }

        public func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            if case let .link(url) = textItem.content {
                return UIAction { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.onLinkTap?(url.absoluteString)
                    }
                }
            }
            return defaultAction
        }
    }
}
