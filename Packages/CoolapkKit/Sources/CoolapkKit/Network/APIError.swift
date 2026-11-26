import Foundation

public enum APIError: LocalizedError, Sendable {
    case blocked
    case expired
    case unauthorized
    case decoding
    case sessionChanged
    case captchaRequired(CaptchaChallenge, message: String)
    case message(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .blocked:
            return "请求被酷安安全策略拦截，请稍后再试"
        case .expired:
            return "登录状态已过期，请重新登录"
        case .unauthorized:
            return "该操作需要登录酷安账号"
        case .decoding:
            return "数据解析失败"
        case .sessionChanged:
            return "账号状态已切换，请重试"
        case let .captchaRequired(_, message):
            return message.isEmpty ? "当前操作需要完成人机验证" : message
        case let .message(text):
            return text
        case let .network(text):
            return text
        }
    }
}

public enum CoolapkLog: Sendable {
    public nonisolated(unsafe) static var sink: (@Sendable (String) -> Void)?

    public static func log(_ message: @autoclosure () -> String) {
        sink?(message())
    }
}
