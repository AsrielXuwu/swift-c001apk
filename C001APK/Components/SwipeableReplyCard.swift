import SwiftUI

@MainActor
public final class ReplySwipeLock {
    public var isDraggingMedia = false
    private var lastMediaDragEndedAt: Date = .distantPast

    public init() {}

    public var isBlocked: Bool {
        isDraggingMedia || Date().timeIntervalSince(lastMediaDragEndedAt) < 0.22
    }

    public func setDraggingMedia(_ active: Bool) {
        isDraggingMedia = active
        if !active {
            lastMediaDragEndedAt = Date()
        }
    }
}

private struct ReplySwipeLockKey: EnvironmentKey {
    static let defaultValue: ReplySwipeLock? = nil
}

public extension EnvironmentValues {
    var replySwipeLock: ReplySwipeLock? {
        get { self[ReplySwipeLockKey.self] }
        set { self[ReplySwipeLockKey.self] = newValue }
    }
}

public struct SwipeableReplyCard<Content: View>: View {
    public let onReply: () -> Void
    public var onLike: (() -> Void)?
    public var isLiked: Bool = false
    public let onCopy: () -> Void
    @ViewBuilder public let content: () -> Content

    @State private var offsetX: CGFloat = 0
    @State private var isOpen = false
    @State private var isDraggingHorizontally = false
    @State private var lastSwipeEndedAt: Date = .distantPast
    @State private var swipeLock = ReplySwipeLock()

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

    private var shouldSuppressChildMediaTap: Bool {
        isDraggingHorizontally || abs(offsetX) > 2 || Date().timeIntervalSince(lastSwipeEndedAt) < 0.35
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
                .environment(\.suppressMediaTap, shouldSuppressChildMediaTap)
                .environment(\.replySwipeLock, swipeLock)
                .offset(x: offsetX)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { value in
                            if swipeLock.isBlocked {
                                isDraggingHorizontally = false
                                if offsetX != (isOpen ? -revealWidth : 0) {
                                    withAnimation(.snappy(duration: 0.2)) {
                                        offsetX = isOpen ? -revealWidth : 0
                                    }
                                }
                                return
                            }
                            let dx = value.translation.width
                            let dy = value.translation.height
                            guard isDraggingHorizontally || abs(dx) > max(18, abs(dy) * 1.3) else { return }
                            isDraggingHorizontally = true
                            if isOpen {
                                let next = -revealWidth + dx
                                offsetX = min(0, max(-revealWidth - 18, next))
                            } else if dx < 0 {
                                offsetX = max(-revealWidth - 18, dx)
                            }
                        }
                        .onEnded { value in
                            if swipeLock.isBlocked {
                                isDraggingHorizontally = false
                                withAnimation(.snappy(duration: 0.2)) {
                                    offsetX = isOpen ? -revealWidth : 0
                                }
                                return
                            }
                            let dx = value.translation.width
                            let dy = value.translation.height
                            let wasSwiping = isDraggingHorizontally || abs(dx) > max(18, abs(dy) * 1.3)
                            isDraggingHorizontally = false
                            guard wasSwiping else {
                                withAnimation(.snappy(duration: 0.22)) {
                                    offsetX = isOpen ? -revealWidth : 0
                                }
                                return
                            }
                            lastSwipeEndedAt = Date()
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
