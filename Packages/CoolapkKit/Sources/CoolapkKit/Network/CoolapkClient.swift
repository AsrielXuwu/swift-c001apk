import CryptoKit
import Foundation

public struct ProtocolParameters: Codable, Equatable, Hashable, Sendable {
    public var appVersion: String
    public var appCode: String
    public var apiVersion: String
    public var sdkInt: String
    public var deviceBrand: String
    public var deviceModel: String
    public var userAgent: String
    public var deviceCode: String
    public var szlmID: String

    public init(
        appVersion: String = CoolapkToken.defaultAppVersion,
        appCode: String = CoolapkToken.defaultAppCode,
        apiVersion: String = CoolapkToken.defaultAPIVersion,
        sdkInt: String = CoolapkToken.defaultSDKInt,
        deviceBrand: String = CoolapkToken.defaultDeviceBrand,
        deviceModel: String = CoolapkToken.defaultDeviceModel,
        userAgent: String? = nil,
        deviceCode: String = "",
        szlmID: String = ""
    ) {
        self.appVersion = appVersion
        self.appCode = appCode
        self.apiVersion = apiVersion
        self.sdkInt = sdkInt
        self.deviceBrand = deviceBrand
        self.deviceModel = deviceModel
        self.userAgent = userAgent ?? CoolapkToken.defaultUserAgent(
            deviceBrand: deviceBrand,
            deviceModel: deviceModel,
            appVersion: appVersion,
            appCode: appCode,
            sdkInt: sdkInt
        )
        let build = CoolapkToken.buildID(forSDKInt: Int(sdkInt) ?? 35)
        let trimmedSzlm = szlmID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.szlmID = trimmedSzlm
        if deviceCode.isEmpty {
            self.deviceCode = CoolapkToken.makeDeviceCode(
                brand: deviceBrand,
                model: deviceModel,
                build: build,
                identifier: trimmedSzlm.isEmpty ? nil : trimmedSzlm
            )
        } else if !trimmedSzlm.isEmpty {
            self.deviceCode = CoolapkToken.replacingDeviceIdentifier(
                in: deviceCode,
                with: trimmedSzlm,
                brand: deviceBrand,
                model: deviceModel,
                build: build
            )
        } else {
            self.deviceCode = deviceCode
        }
    }

    /// Returns a copy whose `X-App-Device` slot 0 is synchronized with `szlmID` when present.
    public func normalized() -> ProtocolParameters {
        var copy = self
        let trimmed = copy.szlmID.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.szlmID = trimmed
        let build = CoolapkToken.buildID(forSDKInt: Int(copy.sdkInt) ?? 35)
        if !trimmed.isEmpty {
            copy.deviceCode = CoolapkToken.replacingDeviceIdentifier(
                in: copy.deviceCode,
                with: trimmed,
                brand: copy.deviceBrand,
                model: copy.deviceModel,
                build: build
            )
        } else if copy.deviceCode.isEmpty {
            copy.deviceCode = CoolapkToken.makeDeviceCode(
                brand: copy.deviceBrand,
                model: copy.deviceModel,
                build: build
            )
        }
        return copy
    }
}

public struct LoginSubmissionResult: Sendable {
    public let uid: String
    public let username: String
    public let token: String
    public let sessid: String
    public let status: Int
    public let message: String
    public let messageStatus: String
}

private struct PersistedAPISession: Codable, Sendable {
    var identity: String
    var value: String
    var domain: String
    var path: String
    var expiresAt: TimeInterval
}

private struct PersistedCaptchaValidation: Codable, Sendable {
    var identity: String
    var sessionHash: String
    var value: String
    var expiresAt: TimeInterval
}

/// Actor-isolated Coolapk HTTP client handling signed headers, session generation, captcha proof, and OSS uploads.
public actor CoolapkClient {
    public static let shared = CoolapkClient()

    public static let apiBase = "https://api.coolapk.com"
    public static let api2Base = "https://api2.coolapk.com"
    public static let accountBase = "https://account.coolapk.com"

    private let session: URLSession
    private var params: ProtocolParameters
    private var inFlightGETs: [String: Task<JSON, Error>] = [:]
    private var hasBootstrappedSession = false

    private(set) var sessionGeneration: Int = 0
    private(set) var uid: String = ""
    private(set) var username: String = ""
    private var token: String = ""
    private var sessid: String = ""
    private var loginSessionCookies: [String: String] = [:]
    private var apiSessionCookies: [String: String] = [:]
    private var persistedAPISession: PersistedAPISession?

    /// In-memory proof for `validate=` cookie during verification retry; promoted to persistent storage once accepted.
    private var memoryCaptchaProof: String?
    private var memoryCaptchaExpiresAt: Date?
    private var memoryCaptchaIdentity: String = ""
    private var memoryCaptchaSessionHash: String = ""

    private var persistedCaptchaValidation: PersistedCaptchaValidation?

    /// One-shot field proof when server asks for `captchaField` (e.g. `_v2_post_token`).
    private var pendingFieldProof: (field: String, proof: String, identity: String, expiresAt: Date)?

    private static let apiSessionDefaultsKey = "c001apk.apiSession.v1"
    private static let captchaValidationDefaultsKey = "c001apk.apiValidation.v1"
    private static let apiSessionMaxAge: TimeInterval = 7 * 86400

    public var isLoggedIn: Bool { !token.isEmpty && !uid.isEmpty }

    public init(parameters: ProtocolParameters = ProtocolParameters()) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = ["Accept-Encoding": "gzip, deflate"]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        self.params = parameters.normalized()

        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        if let sessionData = defaults.data(forKey: Self.apiSessionDefaultsKey),
           let decoded = try? JSONDecoder().decode(PersistedAPISession.self, from: sessionData),
           decoded.expiresAt > now,
           !decoded.value.isEmpty {
            self.persistedAPISession = decoded
        }
        if let valData = defaults.data(forKey: Self.captchaValidationDefaultsKey),
           let decoded = try? JSONDecoder().decode(PersistedCaptchaValidation.self, from: valData),
           decoded.expiresAt > now,
           !decoded.value.isEmpty {
            self.persistedCaptchaValidation = decoded
        }
    }

    // MARK: - Protocol & Session

    public func currentParameters() -> ProtocolParameters { params }

    public func updateParameters(_ updated: ProtocolParameters) {
        let normalized = updated.normalized()
        let deviceChanged = normalized.deviceCode != params.deviceCode
        params = normalized
        if deviceChanged {
            clearAPISessionAndValidation()
        }
    }

    public func applySzlmID(_ id: String) {
        var updated = params
        updated.szlmID = id
        updateParameters(updated)
    }

    public func bootstrapSession(
        parameters: ProtocolParameters,
        uid: String,
        username: String,
        token: String,
        sessid: String
    ) {
        let normalized = parameters.normalized()
        let deviceChanged = normalized.deviceCode != params.deviceCode
        params = normalized
        self.uid = uid
        self.username = username
        self.token = token
        self.sessid = sessid
        hasBootstrappedSession = true
        if deviceChanged {
            apiSessionCookies.removeAll()
        }
        pruneMismatchedSessionAndValidation()
    }

    public func updateLogin(uid: String, username: String, token: String, sessid: String = "") {
        let uidChanged = self.uid != uid || self.token != token
        if hasBootstrappedSession {
            sessionGeneration += 1
        }
        hasBootstrappedSession = true
        self.uid = uid
        self.username = username
        self.token = token
        if !sessid.isEmpty {
            self.sessid = sessid
        }
        if uidChanged {
            clearAPISessionAndValidation()
        }
    }

    public func clearLogin() {
        if hasBootstrappedSession {
            sessionGeneration += 1
        }
        hasBootstrappedSession = true
        uid = ""
        username = ""
        token = ""
        sessid = ""
        clearAPISessionAndValidation()
    }

    public func sessionSnapshot() -> (generation: Int, uid: String, username: String, token: String, sessid: String) {
        (sessionGeneration, uid, username, token, sessid)
    }

    private func currentIdentityHash() -> String {
        let raw = "\(params.deviceCode)|\(isLoggedIn)|\(isLoggedIn ? uid : "")|\(isLoggedIn ? token : "")"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func activeAPISessionValue(for url: URL?) -> String {
        let identity = currentIdentityHash()
        let now = Date().timeIntervalSince1970
        if let saved = persistedAPISession,
           saved.identity == identity,
           saved.expiresAt > now {
            if let url, let host = url.host?.lowercased() {
                let domainMatch = saved.domain == "coolapk.com" || saved.domain == host
                let pathMatch = url.path == saved.path || url.path.hasPrefix(saved.path.hasSuffix("/") ? saved.path : "\(saved.path)/")
                if domainMatch && pathMatch {
                    return saved.value
                }
            } else {
                return saved.value
            }
        }
        if let mem = apiSessionCookies["SESSID"], !mem.isEmpty {
            return mem
        }
        return sessid
    }

    private func currentSessionHash() -> String {
        let val = activeAPISessionValue(for: nil)
        let digest = SHA256.hash(data: Data(val.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func pruneMismatchedSessionAndValidation() {
        let identity = currentIdentityHash()
        let now = Date().timeIntervalSince1970
        if let saved = persistedAPISession, (saved.identity != identity || saved.expiresAt <= now) {
            persistedAPISession = nil
            UserDefaults.standard.removeObject(forKey: Self.apiSessionDefaultsKey)
        }
        let sHash = currentSessionHash()
        if let val = persistedCaptchaValidation,
           (val.identity != identity || val.sessionHash != sHash || val.expiresAt <= now) {
            persistedCaptchaValidation = nil
            UserDefaults.standard.removeObject(forKey: Self.captchaValidationDefaultsKey)
        }
    }

    private func clearAPISessionAndValidation() {
        apiSessionCookies.removeAll()
        persistedAPISession = nil
        UserDefaults.standard.removeObject(forKey: Self.apiSessionDefaultsKey)
        clearCaptchaState()
    }

    public func setCaptchaProof(_ proof: String, field: String = "") {
        let encoded = proof.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? proof
        let identity = currentIdentityHash()
        if !field.isEmpty {
            pendingFieldProof = (
                field: field,
                proof: proof,
                identity: identity,
                expiresAt: Date().addingTimeInterval(300)
            )
            return
        }
        memoryCaptchaProof = encoded
        memoryCaptchaExpiresAt = Date().addingTimeInterval(24 * 3600)
        memoryCaptchaIdentity = identity
        memoryCaptchaSessionHash = currentSessionHash()
    }

    public func clearCaptchaState() {
        memoryCaptchaProof = nil
        memoryCaptchaExpiresAt = nil
        memoryCaptchaIdentity = ""
        memoryCaptchaSessionHash = ""
        pendingFieldProof = nil
        persistedCaptchaValidation = nil
        UserDefaults.standard.removeObject(forKey: Self.captchaValidationDefaultsKey)
    }

    private func activeCaptchaProof(for url: URL) -> String? {
        let identity = currentIdentityHash()
        let sHash = currentSessionHash()
        let now = Date()
        if let proof = memoryCaptchaProof,
           memoryCaptchaIdentity == identity,
           memoryCaptchaSessionHash == sHash,
           let expires = memoryCaptchaExpiresAt,
           expires > now {
            return proof
        }
        if let saved = persistedCaptchaValidation,
           saved.identity == identity,
           saved.sessionHash == sHash,
           saved.expiresAt > now.timeIntervalSince1970 {
            return saved.value
        }
        return nil
    }

    private func promoteAcceptedCaptchaProofIfNeeded(usedProof: String?, identityAtStart: String) {
        guard let usedProof,
              let memProof = memoryCaptchaProof,
              usedProof == memProof,
              identityAtStart == currentIdentityHash() else {
            return
        }
        let persisted = PersistedCaptchaValidation(
            identity: identityAtStart,
            sessionHash: currentSessionHash(),
            value: memProof,
            expiresAt: Date().addingTimeInterval(24 * 3600).timeIntervalSince1970
        )
        persistedCaptchaValidation = persisted
        if let encoded = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(encoded, forKey: Self.captchaValidationDefaultsKey)
        }
        memoryCaptchaProof = nil
        memoryCaptchaExpiresAt = nil
        memoryCaptchaIdentity = ""
        memoryCaptchaSessionHash = ""
    }

    private func buildCookieHeader(for url: URL) -> String {
        var parts: [String] = []
        if isLoggedIn {
            parts.append("uid=\(uid)")
            let rawUsername = username.removingPercentEncoding ?? username
            let encodedName = rawUsername.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? rawUsername
            parts.append("username=\(encodedName)")
            parts.append("token=\(token)")
        }
        let effectiveSessid = activeAPISessionValue(for: url)
        if !effectiveSessid.isEmpty {
            parts.append("SESSID=\(effectiveSessid)")
        }
        for (key, value) in apiSessionCookies.sorted(by: { $0.key < $1.key })
        where key != "SESSID" && key != "validate" && key != "uid" && key != "username" && key != "token" {
            parts.append("\(key)=\(value)")
        }
        if url.scheme == "https", let proof = activeCaptchaProof(for: url) {
            parts.append("validate=\(proof)")
        }
        return parts.joined(separator: "; ")
    }

    private func captureCookies(
        from response: HTTPURLResponse,
        target: inout [String: String],
        persistAPISession: Bool = false,
        requestGeneration: Int? = nil,
        requestIdentity: String? = nil
    ) {
        guard let url = response.url,
              let allHeaders = response.allHeaderFields as? [String: String] else { return }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: allHeaders, for: url)
        for cookie in cookies where !cookie.name.isEmpty {
            target[cookie.name] = cookie.value
            guard persistAPISession,
                  cookie.name == "SESSID",
                  let requestGeneration,
                  let requestIdentity,
                  requestGeneration == sessionGeneration,
                  requestIdentity == currentIdentityHash(),
                  let host = url.host?.lowercased(),
                  host == "api.coolapk.com" || host == "api2.coolapk.com" else {
                continue
            }
            let domain = (cookie.domain.isEmpty ? host : cookie.domain).trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            let path = cookie.path.isEmpty ? "/" : cookie.path
            guard domain == "coolapk.com" || domain == host else { continue }

            let now = Date()
            var expires = now.addingTimeInterval(Self.apiSessionMaxAge)
            if let cookieExpiry = cookie.expiresDate, cookieExpiry < expires {
                expires = cookieExpiry
            }
            if cookie.value.isEmpty || expires <= now {
                persistedAPISession = nil
                persistedCaptchaValidation = nil
                UserDefaults.standard.removeObject(forKey: Self.apiSessionDefaultsKey)
                UserDefaults.standard.removeObject(forKey: Self.captchaValidationDefaultsKey)
            } else {
                let record = PersistedAPISession(
                    identity: requestIdentity,
                    value: cookie.value,
                    domain: domain,
                    path: path,
                    expiresAt: expires.timeIntervalSince1970
                )
                persistedAPISession = record
                if let encoded = try? JSONEncoder().encode(record) {
                    UserDefaults.standard.set(encoded, forKey: Self.apiSessionDefaultsKey)
                }
            }
        }
    }

    // MARK: - Token

    private func currentAppToken() async -> String {
        let code = params.deviceCode
        let appCode = Int(params.appCode) ?? 2604201
        return await CoolapkToken.currentToken(deviceCode: code, appCode: appCode) ?? ""
    }

    public func prepareForForeground(flushConnections: Bool = false) async {
        // Keep persistent HTTP/2 connections and session state intact across foreground transitions
        // to match Android/Flutter clients and avoid unnecessary risk-control re-challenges.
        if flushConnections {
            await session.flush()
        }
    }

    private func applySignedClientHeaders(to request: inout URLRequest, appToken: String, includeAccept: Bool = true) {
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(CoolapkToken.packageName, forHTTPHeaderField: "X-App-Id")
        request.setValue(params.appVersion, forHTTPHeaderField: "X-App-Version")
        request.setValue(params.appCode, forHTTPHeaderField: "X-App-Code")
        request.setValue(params.appCode, forHTTPHeaderField: "X-App-Supported")
        request.setValue(params.apiVersion, forHTTPHeaderField: "X-Api-Version")
        request.setValue(appToken, forHTTPHeaderField: "X-App-Token")
        request.setValue(params.deviceCode, forHTTPHeaderField: "X-App-Device")
        request.setValue(params.sdkInt, forHTTPHeaderField: "X-Sdk-Int")
        request.setValue("zh-CN", forHTTPHeaderField: "X-Sdk-Locale")
        request.setValue("universal", forHTTPHeaderField: "X-App-Mode")
        request.setValue("coolapk", forHTTPHeaderField: "X-App-Channel")
        request.setValue("0", forHTTPHeaderField: "X-Dark-Mode")
        request.setValue(params.userAgent, forHTTPHeaderField: "User-Agent")
        if includeAccept {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        }
    }

    // MARK: - Core Requests

    private func makeSignedRequest(
        base: String,
        path: String,
        parameters: [String: String],
        method: String,
        body: Data?,
        contentType: String?,
        requestGeneration: Int,
        requestIdentity: String
    ) async throws -> (Data, HTTPURLResponse?, String?) {
        let appToken = await currentAppToken()
        let fullString = path.hasPrefix("http") ? path : base + path
        var components = URLComponents(string: fullString)
        if !parameters.isEmpty {
            var items = components?.queryItems ?? []
            for (key, value) in parameters where !value.isEmpty {
                items.append(URLQueryItem(name: key, value: value))
            }
            components?.queryItems = items
        }
        guard let url = components?.url else { throw APIError.network("无效的请求地址") }

        let usedProof = url.scheme == "https" ? activeCaptchaProof(for: url) : nil
        var request = URLRequest(url: url)
        request.httpMethod = method
        applySignedClientHeaders(to: &request, appToken: appToken)

        let cookieHeader = buildCookieHeader(for: url)
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        if let body {
            request.httpBody = body
            if let contentType {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }

        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            if let http {
                captureCookies(
                    from: http,
                    target: &apiSessionCookies,
                    persistAPISession: true,
                    requestGeneration: requestGeneration,
                    requestIdentity: requestIdentity
                )
                if http.statusCode == 567 { throw APIError.blocked }
                if http.statusCode != 200, (try? JSON(data: data)) == nil {
                    throw APIError.network("服务端返回异常（HTTP \(http.statusCode)）")
                }
            }
            return (data, http, usedProof)
        } catch let error as APIError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    private func consumePendingFieldProofIfValid() -> (field: String, proof: String)? {
        guard let pending = pendingFieldProof else { return nil }
        pendingFieldProof = nil
        guard pending.identity == currentIdentityHash(), pending.expiresAt > Date() else {
            return nil
        }
        return (pending.field, pending.proof)
    }

    private func injectFieldProof(
        _ fieldProof: (field: String, proof: String),
        intoParameters parameters: [String: String],
        method: String,
        body: Data?,
        contentType: String?
    ) -> ([String: String], Data?) {
        if method == "GET" || body == nil {
            var updated = parameters
            updated[fieldProof.field] = fieldProof.proof
            return (updated, body)
        }
        if let body,
           let contentType,
           contentType.contains("application/x-www-form-urlencoded"),
           var bodyStr = String(data: body, encoding: .utf8) {
            let pair = "\(urlFormEncode(fieldProof.field))=\(urlFormEncode(fieldProof.proof))"
            bodyStr = bodyStr.isEmpty ? pair : "\(bodyStr)&\(pair)"
            return (parameters, Data(bodyStr.utf8))
        }
        var updated = parameters
        updated[fieldProof.field] = fieldProof.proof
        return (updated, body)
    }

    private func perform(
        base: String = CoolapkClient.apiBase,
        path: String,
        parameters: [String: String],
        method: String,
        body: Data?,
        contentType: String?,
        clearProofOnCaptcha: Bool = true
    ) async throws -> JSON {
        let initialGeneration = sessionGeneration
        let initialIdentity = currentIdentityHash()
        var effectiveParameters = parameters
        var effectiveBody = body
        if let fieldProof = consumePendingFieldProofIfValid() {
            (effectiveParameters, effectiveBody) = injectFieldProof(
                fieldProof,
                intoParameters: effectiveParameters,
                method: method,
                body: effectiveBody,
                contentType: contentType
            )
        }

        var attempt = 0
        while true {
            guard initialGeneration == sessionGeneration, initialIdentity == currentIdentityHash() else {
                throw APIError.sessionChanged
            }
            let (data, _, usedProof) = try await makeSignedRequest(
                base: base,
                path: path,
                parameters: effectiveParameters,
                method: method,
                body: effectiveBody,
                contentType: contentType,
                requestGeneration: initialGeneration,
                requestIdentity: initialIdentity
            )
            guard initialGeneration == sessionGeneration, initialIdentity == currentIdentityHash() else {
                throw APIError.sessionChanged
            }

            let json: JSON
            do {
                json = try JSON(data: data)
            } catch {
                if attempt == 0 { attempt += 1; continue }
                throw APIError.decoding
            }

            if let challenge = CaptchaChallenge.from(json: json) {
                if clearProofOnCaptcha, usedProof != nil {
                    clearCaptchaState()
                }
                throw APIError.captchaRequired(challenge, message: json.message.string)
            }

            let status = json.status.int
            if !json.message.isNull, status != 0, status != 1, status != 1000, !json.data.exists {
                let text = json.message.string
                if status == 1005 || text.contains("过期") {
                    if attempt == 0 { attempt += 1; continue }
                    throw APIError.expired
                }
                if text.contains("登录") {
                    throw APIError.unauthorized
                }
                throw APIError.message(text)
            }

            let code = json.code.int
            if code != 0, !json.data.exists {
                let text = json.message.string
                if text.contains("登录") { throw APIError.unauthorized }
                throw APIError.message(text.isEmpty ? "请求被服务端拒绝（code \(code)）" : text)
            }

            if status == 1005, attempt == 0 {
                attempt += 1
                continue
            }

            promoteAcceptedCaptchaProofIfNeeded(usedProof: usedProof, identityAtStart: initialIdentity)
            CoolapkLog.log("\(method) \(path) -> status \(status) count \(json.data.array.count)")
            return json
        }
    }

    @discardableResult
    public func get(
        _ path: String,
        _ parameters: [String: String] = [:],
        base: String = CoolapkClient.apiBase,
        clearProofOnCaptcha: Bool = true
    ) async throws -> JSON {
        let sortedParams = parameters.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        let key = "\(sessionGeneration)|\(base)|\(path)|\(sortedParams)"
        if let existing = inFlightGETs[key] {
            return try await existing.value
        }
        let task = Task<JSON, Error> {
            try await perform(
                base: base,
                path: path,
                parameters: parameters,
                method: "GET",
                body: nil,
                contentType: nil,
                clearProofOnCaptcha: clearProofOnCaptcha
            )
        }
        inFlightGETs[key] = task
        defer { inFlightGETs.removeValue(forKey: key) }
        return try await task.value
    }

    @discardableResult
    public func post(_ path: String, _ form: [String: String] = [:], query: [String: String] = [:], base: String = CoolapkClient.apiBase) async throws -> JSON {
        let encodedBody = form
            .map { key, value in
                "\(urlFormEncode(key))=\(urlFormEncode(value))"
            }
            .joined(separator: "&")
        return try await perform(
            base: base,
            path: path,
            parameters: query,
            method: "POST",
            body: Data(encodedBody.utf8),
            contentType: "application/x-www-form-urlencoded; charset=utf-8"
        )
    }

    public func postMultipart(_ path: String, fields: [String: String], query: [String: String] = [:]) async throws -> JSON {
        let boundary = "----C001APKiOS\(UUID().uuidString)"
        var body = Data()
        for (key, value) in fields {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return try await perform(
            base: Self.apiBase,
            path: path,
            parameters: query,
            method: "POST",
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
    }

    public func upload(
        path: String,
        fieldName: String,
        filename: String,
        data: Data,
        mimeType: String = "image/jpeg"
    ) async throws -> JSON {
        let boundary = "----C001APKiOS\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return try await perform(
            base: Self.apiBase,
            path: path,
            parameters: [:],
            method: "POST",
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
    }

    public func dataList(url: String, page: Int, extra: [String: String] = [:]) async throws -> [JSON] {
        var params = extra
        params["url"] = url
        params["page"] = String(page)
        let json = try await get("/v6/page/dataList", params)
        return json.data.array
    }

    /// Official public feed representation fallback (`https://www.coolapk.com/feed/<id>`) without cookies.
    public func publicFeedJSON(id: String) async throws -> JSON {
        let appToken = await currentAppToken()
        guard let url = URL(string: "https://www.coolapk.com/feed/\(id)") else {
            throw APIError.network("无效的公开动态地址")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applySignedClientHeaders(to: &request, appToken: appToken, includeAccept: false)

        let (data, _) = try await session.data(for: request)
        let json = try JSON(data: data)
        guard json.data.exists else {
            throw APIError.decoding
        }
        return json
    }

    // MARK: - Message Image Redirect

    public func resolveMessageImageURL(id: String) async throws -> URL? {
        let appToken = await currentAppToken()
        var components = URLComponents(string: Self.apiBase + "/v6/message/showImage")
        components?.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "type", value: "s")
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(CoolapkToken.packageName, forHTTPHeaderField: "X-App-Id")
        request.setValue(params.appVersion, forHTTPHeaderField: "X-App-Version")
        request.setValue(params.appCode, forHTTPHeaderField: "X-App-Code")
        request.setValue(params.apiVersion, forHTTPHeaderField: "X-Api-Version")
        request.setValue(appToken, forHTTPHeaderField: "X-App-Token")
        request.setValue(params.deviceCode, forHTTPHeaderField: "X-App-Device")
        request.setValue(params.userAgent, forHTTPHeaderField: "User-Agent")
        let cookie = buildCookieHeader(for: url)
        if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }

        let delegate = NoRedirectDelegate()
        let noRedirectSession = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { noRedirectSession.invalidateAndCancel() }
        let (_, response) = try await noRedirectSession.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 302,
              let location = http.value(forHTTPHeaderField: "Location"),
              let resolved = URL(string: location),
              let scheme = resolved.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return resolved
    }

    // MARK: - Aliyun OSS Direct Upload (Chat Images)

    public func uploadChatImageToOSS(
        data: Data,
        filename: String,
        mimeType: String,
        resolution: String,
        toUID: String
    ) async throws -> String {
        let md5Hex = CoolapkToken.md5(data)
        let uploadListPayload: [[String: String]] = [[
            "name": filename,
            "resolution": resolution,
            "md5": md5Hex
        ]]
        let uploadListJSONData = try JSONSerialization.data(withJSONObject: uploadListPayload)
        let uploadListString = String(data: uploadListJSONData, encoding: .utf8) ?? "[]"

        let prepared = try await postMultipart("/v6/upload/ossUploadPrepare", fields: [
            "uploadBucket": "message",
            "uploadDir": "message",
            "is_anonymous": "0",
            "uploadFileList": uploadListString,
            "toUid": toUID
        ])

        let info = prepared.data.uploadPrepareInfo
        let object = prepared.data.fileInfo[0].uploadFileName.string
        let accessKeyID = info.accessKeyId.string
        let accessKeySecret = info.accessKeySecret.string
        let securityToken = info.securityToken.string
        let endpoint = info.endPoint.string
        let bucket = info.bucket.string

        guard object.hasPrefix("message/"),
              !accessKeyID.isEmpty, !accessKeySecret.isEmpty, !securityToken.isEmpty,
              !endpoint.isEmpty, !bucket.isEmpty else {
            throw APIError.message("图片上传配置不完整，请重试")
        }

        let cleanEndpoint = endpoint.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        guard let uploadURL = URL(string: "https://\(bucket).\(cleanEndpoint)/\(object)") else {
            throw APIError.message("无效的 OSS 上传地址")
        }

        let contentMD5 = Data(Insecure.MD5.hash(data: data)).base64EncodedString()
        let dateString = rfc1123Date(Date())
        let callbackVar = "eyJ4OnZhcjEiOiJmYWxzZSJ9"
        let callback = "eyJjYWxsYmFja0JvZHlUeXBlIjoiYXBwbGljYXRpb25cL2pzb24iLCJjYWxsYmFja0hvc3QiOiJhcGkuY29vbGFway5jb20iLCJjYWxsYmFja1VybCI6Imh0dHBzOlwvXC9hcGkuY29vbGFway5jb21cL3Y2XC9jYWxsYmFja1wvbW9iaWxlT3NzVXBsb2FkU3VjY2Vzc0NhbGxiYWNrP2NoZWNrQXJ0aWNsZUNvdmVyUmVzb2x1dGlvbj0wJnZlcnNpb25Db2RlPTIxMDIwMzEiLCJjYWxsYmFja0JvZHkiOiJ7XCJidWNrZXRcIjoke2J1Y2tldH0sXCJvYmplY3RcIjoke29iamVjdH0sXCJoYXNQcm9jZXNzXCI6JHt4OnZhcjF9fSJ9"

        let canonicalHeaders = "x-oss-callback:\(callback)\nx-oss-callback-var:\(callbackVar)\nx-oss-security-token:\(securityToken)"
        let stringToSign = "PUT\n\(contentMD5)\n\(mimeType)\n\(dateString)\n\(canonicalHeaders)\n/\(bucket)/\(object)"
        let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(stringToSign.utf8), using: SymmetricKey(data: Data(accessKeySecret.utf8)))
        let signature = Data(hmac).base64EncodedString()

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        request.setValue(contentMD5, forHTTPHeaderField: "Content-MD5")
        request.setValue(dateString, forHTTPHeaderField: "Date")
        request.setValue("\(bucket).\(cleanEndpoint)", forHTTPHeaderField: "Host")
        request.setValue(securityToken, forHTTPHeaderField: "x-oss-security-token")
        request.setValue(callbackVar, forHTTPHeaderField: "x-oss-callback-var")
        request.setValue(callback, forHTTPHeaderField: "x-oss-callback")
        request.setValue("OSS \(accessKeyID):\(signature)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.network("OSS 图片上传失败")
        }
        return "/\(object)"
    }

    // MARK: - Account Login Service (account.coolapk.com)

    public func fetchLoginRequestHash() async throws -> String {
        loginSessionCookies.removeAll()
        var foundHash: String?

        if let mobileURL = URL(string: "\(Self.accountBase)/auth/login?type=mobile") {
            var request = URLRequest(url: mobileURL)
            request.httpMethod = "GET"
            applyAccountHeaders(to: &request, isPost: false)
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                captureCookies(from: http, target: &loginSessionCookies)
            }
            let html = String(data: data, encoding: .utf8) ?? ""
            foundHash = extractRequestHash(from: html)
        }

        if let loginPageURL = URL(string: "\(Self.accountBase)/auth/loginByCoolApk") {
            var request = URLRequest(url: loginPageURL)
            request.httpMethod = "GET"
            applyAccountHeaders(to: &request, isPost: false)
            if let (data, response) = try? await session.data(for: request) {
                if let http = response as? HTTPURLResponse {
                    captureCookies(from: http, target: &loginSessionCookies)
                }
                let html = String(data: data, encoding: .utf8) ?? ""
                if let hash = extractRequestHash(from: html) {
                    foundHash = hash
                }
            }
        }

        if let foundHash, !foundHash.isEmpty {
            return foundHash
        }
        throw APIError.message("未能获取登录参数（requestHash）")
    }

    public func fetchLoginCaptchaImage() async throws -> Data {
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        guard let url = URL(string: "\(Self.accountBase)/auth/showCaptchaImage?\(stamp)") else {
            throw APIError.network("无效的验证码地址")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAccountHeaders(to: &request, isPost: false)
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("\(Self.accountBase)/auth/loginByCoolApk", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            captureCookies(from: http, target: &loginSessionCookies)
        }
        return data
    }

    public func loginByCoolapk(requestHash: String, account: String, password: String, captcha: String) async throws -> LoginSubmissionResult {
        guard let url = URL(string: "\(Self.accountBase)/auth/loginByCoolApk") else {
            throw APIError.network("无效的登录地址")
        }
        let form: [String: String] = [
            "submit": "1",
            "randomNumber": CoolapkToken.createRandomNumber(),
            "requestHash": requestHash,
            "login": account,
            "password": password,
            "captcha": captcha,
            "code": ""
        ]
        let body = form.map { "\(urlFormEncode($0.key))=\(urlFormEncode($0.value))" }.joined(separator: "&")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        applyAccountHeaders(to: &request, isPost: true)
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        var setCookies: [String: String] = [:]
        if let http = response as? HTTPURLResponse {
            captureCookies(from: http, target: &setCookies)
        }
        let json = try JSON(data: data)
        let rawName = setCookies["username"] ?? loginSessionCookies["username"] ?? ""
        let decodedName = rawName.removingPercentEncoding ?? rawName
        let resolvedSessid = (setCookies["SESSID"]?.isEmpty == false ? setCookies["SESSID"] : loginSessionCookies["SESSID"]) ?? ""
        return LoginSubmissionResult(
            uid: setCookies["uid"] ?? loginSessionCookies["uid"] ?? "",
            username: decodedName,
            token: setCookies["token"] ?? loginSessionCookies["token"] ?? "",
            sessid: resolvedSessid,
            status: json.status.int,
            message: json.message.string,
            messageStatus: json.messageStatus.string
        )
    }

    private func applyAccountHeaders(to request: inout URLRequest, isPost: Bool) {
        request.setValue("\"Android WebView\";v=\"117\", \"Not;A=Brand\";v=\"8\", \"Chromium\";v=\"117\"", forHTTPHeaderField: "sec-ch-ua")
        request.setValue("?1", forHTTPHeaderField: "sec-ch-ua-mobile")
        request.setValue("Android", forHTTPHeaderField: "sec-ch-ua-platform")
        request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        request.setValue(params.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(isPost ? "XMLHttpRequest" : CoolapkToken.packageName, forHTTPHeaderField: "X-Requested-With")
        if !loginSessionCookies.isEmpty {
            let cookiePairs = loginSessionCookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            request.setValue("\(cookiePairs); forward=https://www.coolapk.com", forHTTPHeaderField: "Cookie")
        }
    }

    private func extractRequestHash(from html: String) -> String? {
        let patterns = [
            #"name=["']requestHash["'][^>]*value=["']([^"']+)["']"#,
            #"value=["']([^"']+)["'][^>]*name=["']requestHash["']"#,
            #"data-request-hash=["']([^"']+)["']"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let value = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private func urlFormEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    private func rfc1123Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }

    public func resolveRedirectLocation(
        path: String,
        query: [String: String],
        base: String = CoolapkClient.apiBase
    ) async -> String? {
        let fullString = path.hasPrefix("http") ? path : base + path
        var components = URLComponents(string: fullString)
        if !query.isEmpty {
            var items = components?.queryItems ?? []
            for (key, value) in query where !value.isEmpty {
                items.append(URLQueryItem(name: key, value: value))
            }
            components?.queryItems = items
        }
        guard let url = components?.url else { return nil }

        let appToken = await currentAppToken()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applySignedClientHeaders(to: &request, appToken: appToken, includeAccept: false)
        let cookieHeader = buildCookieHeader(for: url)
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let noRedirectConfig = URLSessionConfiguration.ephemeral
        noRedirectConfig.timeoutIntervalForRequest = 12
        let noRedirectSession = URLSession(configuration: noRedirectConfig, delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { noRedirectSession.invalidateAndCancel() }

        guard let (data, response) = try? await noRedirectSession.data(for: request),
              let http = response as? HTTPURLResponse else {
            return nil
        }
        if (300...399).contains(http.statusCode),
           let location = http.value(forHTTPHeaderField: "Location"),
           location.hasPrefix("http://") || location.hasPrefix("https://") {
            return coolapkNormalizedURL(location)
        }
        if let json = try? JSON(data: data) {
            let direct = json.data.string
            if direct.hasPrefix("http://") || direct.hasPrefix("https://") {
                return coolapkNormalizedURL(direct)
            }
        }
        return nil
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
