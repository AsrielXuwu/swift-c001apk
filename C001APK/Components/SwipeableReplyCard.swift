import SwiftUI

public struct SwipeableReplyCard<Content: View>: View {
    public let onReply: () -> Void
    public var onLike: (() -> Void)?
    public var isLiked: Bool = false
    public let onCopy: () -> Void
    @ViewBuilder public let content: () -> Content

    @State private var offsetX: CGFloat = 0
    @State private var isOpen = false

    public init(
        onReply: @escaping () -> Void,
        onLike: (() -> Void)? = nil,
        isLiked: Bool = false,
        onCopy: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.onReply = onReply
        self.onLike = onLike
        self.isLiked = isLiked
        self.onCopy = onCopy
        self.content = content
    }

    private var revealWidth: CGFloat {
        onLike == nil ? 100 : 148
    }

    public var body: some View {
        ZStack(alignment: .trailing) {
            if offsetX < -4 {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            closeMenu()
                            onReply()
                        } label: {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .font(.body.weight(.semibold))
                                .frame(width: 40, height: 40)
                                .glassEffect(.regular.interactive(), in: .circle)
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)

                        if let onLike {
                            Button {
                                closeMenu()
                                onLike()
                            } label: {
                                Image(systemName: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 40, height: 40)
                                    .glassEffect(.regular.interactive(), in: .circle)
                                    .foregroundStyle(isLiked ? Color.pink : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            closeMenu()
                            onCopy()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.body.weight(.semibold))
                                .frame(width: 40, height: 40)
                                .glassEffect(.regular.interactive(), in: .circle)
                                .foregroundStyle(Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 4)
            }

            content()
                .offset(x: offsetX)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            guard abs(dx) > abs(dy) * 1.35 else { return }
                            if isOpen {
                                let next = -revealWidth + dx
                                offsetX = min(0, max(-revealWidth - 18, next))
                            } else if dx < 0 {
                                offsetX = max(-revealWidth - 18, dx)
                            }
                        }
                        .onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            guard abs(dx) > abs(dy) * 1.35 else {
                                withAnimation(.snappy(duration: 0.22)) {
                                    offsetX = isOpen ? -revealWidth : 0
                                }
                                return
                            }
                            withAnimation(.snappy(duration: 0.24)) {
                                if (!isOpen && dx < -46) || (isOpen && dx < 28) {
                                    offsetX = -revealWidth
                                    isOpen = true
                                } else {
                                    offsetX = 0
                                    isOpen = false
                                }
                            }
                        }
                )
        }
    }

    private func closeMenu() {
        withAnimation(.snappy(duration: 0.22)) {
            offsetX = 0
            isOpen = false
        }
    }
}
