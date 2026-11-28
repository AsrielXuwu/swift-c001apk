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

    public enum ProductSubTabOption: String, CaseIterable, Identifiable {
        case none = "0"
        case daoshoujia = "6"
        case battery = "1"
        case benchmark = "2"
        case feedback = "5"

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .none: return "普通讨论"
            case .daoshoujia: return "到手价"
            case .battery: return "续航时长"
            case .benchmark: return "跑分成绩"
            case .feedback: return "问题反馈"
            }
        }
    }

    public var text = ""
    public var pickedImages: [PickedImage] = []
    public var isSubmitting = false
    public var isSelfOnly = false
    public var subTabOption: ProductSubTabOption = .none
    public var finalPriceInput = ""
    public var configNameInput = ""
    public var batteryHoursInput = ""
    public var antutuScoreInput = ""
    public var feedbackLevel = "2"

    public init() {}

    public func addImageData(_ data: Data) {
        guard let img = UIImage(data: data),
              let jpeg = img.jpegData(compressionQuality: 0.86) else { return }
        pickedImages.append(PickedImage(image: img, jpegData: jpeg))
    }

    public func removeImage(id: UUID) {
        pickedImages.removeAll { $0.id == id }
    }

    private func buildSubTabPayload() -> (id: String, data: String) {
        switch subTabOption {
        case .none:
            return ("", "")
        case .daoshoujia:
            let priceNum = FeedItem.parseNumericPriceString(finalPriceInput)
            guard priceNum > 0 else { return ("", "") }
            let cfgName = configNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let payload: [String: Any] = [
                "final_price": priceNum.truncatingRemainder(dividingBy: 1) == 0 ? Int(priceNum) : priceNum,
                "config_id": 1,
                "config_name": cfgName.isEmpty ? "默认配置" : cfgName
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload),
               let jsonStr = String(data: data, encoding: .utf8) {
                return ("6", jsonStr)
            }
            return ("", "")
        case .battery:
            let trimmed = batteryHoursInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let hrs = Double(trimmed), hrs > 0 else { return ("", "") }
            return ("1", trimmed)
        case .benchmark:
            let trimmed = antutuScoreInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let score = Int(trimmed), score > 0 else { return ("", "") }
            return ("2", "{\"antutu_score\":\(score)}")
        case .feedback:
            return ("5", feedbackLevel)
        }
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
                let subTab = buildSubTabPayload()
                try await API.createFeed(
                    message: trimmed,
                    pictures: uploadedURLs,
                    publishStatus: isSelfOnly ? "1" : "0",
                    subTabID: subTab.id,
                    subTabData: subTab.data
                )
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
            appState.feedRefreshTrigger += 1
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
