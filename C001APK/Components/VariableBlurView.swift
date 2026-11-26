import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

public enum VariableBlurDirection: Sendable {
    case blurredTopClearBottom
    case blurredBottomClearTop
}

/// Progressive variable Gaussian blur matching `nikstar/VariableBlur` (`CABackdropLayer` + `variableBlur`).
public struct VariableBlurView: UIViewRepresentable {
    public var maxBlurRadius: CGFloat
    public var direction: VariableBlurDirection
    public var startOffset: CGFloat

    public init(
        maxBlurRadius: CGFloat = 20,
        direction: VariableBlurDirection = .blurredTopClearBottom,
        startOffset: CGFloat = 0
    ) {
        self.maxBlurRadius = maxBlurRadius
        self.direction = direction
        self.startOffset = startOffset
    }

    public func makeUIView(context: Context) -> VariableBlurUIView {
        VariableBlurUIView(
            maxBlurRadius: maxBlurRadius,
            direction: direction,
            startOffset: startOffset
        )
    }

    public func updateUIView(_ uiView: VariableBlurUIView, context: Context) {
        uiView.configure(
            maxBlurRadius: maxBlurRadius,
            direction: direction,
            startOffset: startOffset
        )
    }
}

public final class VariableBlurUIView: UIVisualEffectView {
    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

    private var maxBlurRadius: CGFloat
    private var direction: VariableBlurDirection
    private var startOffset: CGFloat
    private var cachedMaskImage: CGImage?
    private var cachedMaskKey: String = ""

    public init(
        maxBlurRadius: CGFloat = 20,
        direction: VariableBlurDirection = .blurredTopClearBottom,
        startOffset: CGFloat = 0
    ) {
        self.maxBlurRadius = maxBlurRadius
        self.direction = direction
        self.startOffset = startOffset
        super.init(effect: UIBlurEffect(style: .regular))
        isUserInteractionEnabled = false
        backgroundColor = .clear
        applyVariableBlurFilter()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(
        maxBlurRadius: CGFloat,
        direction: VariableBlurDirection,
        startOffset: CGFloat
    ) {
        let clampedOffset = max(0, min(0.95, startOffset))
        guard self.maxBlurRadius != maxBlurRadius
                || self.direction != direction
                || self.startOffset != clampedOffset else {
            return
        }
        self.maxBlurRadius = maxBlurRadius
        self.direction = direction
        self.startOffset = clampedOffset
        applyVariableBlurFilter()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        if let screen = window?.windowScene?.screen {
            subviews.first?.layer.setValue(screen.scale, forKey: "scale")
        }
        applyVariableBlurFilter()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        applyVariableBlurFilter()
    }

    private func applyVariableBlurFilter() {
        let clampedOffset = max(0, min(0.95, startOffset))
        let maskKey = "\(direction)|\(Int((clampedOffset * 1000).rounded()))"
        if cachedMaskImage == nil || cachedMaskKey != maskKey {
            cachedMaskImage = Self.makeGradientMaskImage(
                startOffset: clampedOffset,
                direction: direction
            )
            cachedMaskKey = maskKey
        }

        guard let maskImage = cachedMaskImage,
              let caFilterClass = NSClassFromString("CAFilter") as? NSObject.Type else {
            return
        }
        let selector = NSSelectorFromString("filterWithType:")
        guard caFilterClass.responds(to: selector),
              let filter = caFilterClass.perform(selector, with: "variableBlur" as NSString)?.takeUnretainedValue() as? NSObject else {
            return
        }

        filter.setValue(maskImage, forKey: "inputMaskImage")
        filter.setValue(NSNumber(value: Double(maxBlurRadius)), forKey: "inputRadius")
        filter.setValue(NSNumber(value: true), forKey: "inputNormalizeEdges")

        if let backdropLayer = subviews.first?.layer {
            backdropLayer.filters = [filter]
        }

        // Remove UIVisualEffectView dimming/tint layers so only the pure progressive Gaussian blur remains.
        for tintSubview in subviews.dropFirst() {
            tintSubview.alpha = 0
            tintSubview.isHidden = true
        }
    }

    private static func makeGradientMaskImage(
        startOffset: CGFloat,
        direction: VariableBlurDirection
    ) -> CGImage? {
        let height: CGFloat = 100
        let filter = CIFilter.linearGradient()
        filter.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        filter.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)

        switch direction {
        case .blurredTopClearBottom:
            filter.point0 = CGPoint(x: 0, y: height * (1 - startOffset))
            filter.point1 = CGPoint(x: 0, y: 0)
        case .blurredBottomClearTop:
            filter.point0 = CGPoint(x: 0, y: height * startOffset)
            filter.point1 = CGPoint(x: 0, y: height)
        }

        guard let output = filter.outputImage else { return nil }
        return sharedCIContext.createCGImage(output, from: CGRect(x: 0, y: 0, width: 1, height: height))
    }
}
