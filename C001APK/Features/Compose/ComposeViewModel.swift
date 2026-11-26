import CoolapkKit
import Foundation
import Observation
import UIKit

@MainActor
@Observable
public final class ComposeViewModel {
    public struct PickedImage: Identifiable {
        public let id = UUID()
        public let image: UIImage
        public let jpegData: Data
    }

    public var text = ""
    public var pickedImages: [PickedImage] = []
    public var isSubmitting = false

    public init() {}

    public func addImageData(_ data: Data) {
        guard let img = UIImage(data: data),
              let jpeg = img.jpegData(compressionQuality: 0.86) else { return }
        pickedImages.append(PickedImage(image: img, jpegData: jpeg))
    }

    public func removeImage(id: UUID) {
        pickedImages.removeAll { $0.id == id }
    }

    public func submit(mode: ComposeMode, appState: AppState) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .forward = mode {
            // Forwarding allows empty comment text.
        } else if trimmed.isEmpty && pickedImages.isEmpty {
            appState.showToast("请输入内容或选择图片")
            return false
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            var uploadedURLs: [String] = []
            for item in pickedImages {
                let link = try await API.uploadImage(
                    data: item.jpegData,
                    filename: "\(UUID().uuidString).jpg"
                )
                uploadedURLs.append(link)
            }

            switch mode {
            case .newFeed:
                try await API.createFeed(message: trimmed, pictures: uploadedURLs)
                appState.showToast("发布成功")
            case let .forward(feed):
                try await API.forwardFeed(id: feed.id, message: trimmed)
                appState.showToast("转发成功")
            case let .replyToFeed(feedID, _):
                _ = try await API.postReply(targetID: feedID, message: trimmed, isReply: false, pictures: uploadedURLs)
                appState.showToast("评论已发送")
            case let .replyToComment(targetID, _):
                _ = try await API.postReply(targetID: targetID, message: trimmed, isReply: true, pictures: uploadedURLs)
                appState.showToast("回复已发送")
            }
            return true
        } catch {
            let retried = await appState.handleAPIError(error)
            if retried {
                return await submit(mode: mode, appState: appState)
            }
            return false
        }
    }
}
