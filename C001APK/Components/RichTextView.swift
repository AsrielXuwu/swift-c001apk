import SwiftUI
import UIKit

public struct RichTextView: UIViewRepresentable {
    public let html: String
    public var fontSize: CGFloat = 16
    public var textColor: UIColor = .label
    public var maxLines: Int = 0
    public var showEmoji: Bool = true
    public var onLinkTap: ((String) -> Void)?

    public init(
        html: String,
        fontSize: CGFloat = 16,
        textColor: UIColor = .label,
        maxLines: Int = 0,
        showEmoji: Bool = true,
        onLinkTap: ((String) -> Void)? = nil
    ) {
        self.html = html
        self.fontSize = fontSize
        self.textColor = textColor
        self.maxLines = maxLines
        self.showEmoji = showEmoji
        self.onLinkTap = onLinkTap
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTap: onLinkTap)
    }

    public func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.lineBreakMode = .byTruncatingTail
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.delegate = context.coordinator
        return view
    }

    public func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.onLinkTap = onLinkTap
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

    public final class Coordinator: NSObject, UITextViewDelegate {
        var onLinkTap: ((String) -> Void)?

        init(onLinkTap: ((String) -> Void)?) {
            self.onLinkTap = onLinkTap
        }

        public func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            if case let .link(url) = textItem.content {
                return UIAction { [weak self] _ in
                    self?.onLinkTap?(url.absoluteString)
                }
            }
            return defaultAction
        }
    }
}
