import CoolapkKit
import Foundation
import Observation
import Security

@MainActor
@Observable
public final class AccountStore {
    private static let accountsDefaultsKey = "c001apk.accounts.v1"
    private static let activeUIDDefaultsKey = "c001apk.activeUid.v1"
    private static let keychainService = "app.awavenue.c001apk.tokens"

    public private(set) var accounts: [SavedAccount] = []
    public private(set) var activeUID: String?

    public var activeAccount: SavedAccount? {
        guard let activeUID else { return nil }
        return accounts.first { $0.uid == activeUID && !$0.needsRelogin }
    }

    public var isLoggedIn: Bool { activeAccount != nil }

    public init() {
        loadFromDisk()
    }

    public func restoreActiveSessionIntoClient() async {
        guard let account = activeAccount,
              let creds = readCredentials(for: account.uid),
              !creds.token.isEmpty else {
            await CoolapkClient.shared.clearLogin()
            return
        }
        await CoolapkClient.shared.updateLogin(
            uid: account.uid,
            username: account.username,
            token: creds.token,
            sessid: creds.sessid
        )
    }

    public func saveLogin(uid: String, username: String, token: String, sessid: String = "") async throws {
        guard !uid.isEmpty, uid.allSatisfy(\.isNumber), !token.isEmpty else {
            throw APIError.message("登录响应缺少有效账号信息")
        }
        let normalizedName = (username.removingPercentEncoding ?? username)
        let resolvedName = normalizedName.isEmpty ? uid : normalizedName
        saveCredentials(uid: uid, token: token, sessid: sessid)
        let existing = accounts.first { $0.uid == uid }
        let updated = SavedAccount(
            uid: uid,
            username: resolvedName,
            avatar: existing?.avatar ?? "",
            level: existing?.level ?? 0,
            exp: existing?.exp ?? 0,
            nextExp: existing?.nextExp ?? 1,
            needsRelogin: false
        )
        accounts.removeAll { $0.uid == uid }
        accounts.insert(updated, at: 0)
        activeUID = uid
        persistMetadata()
        await CoolapkClient.shared.updateLogin(uid: uid, username: resolvedName, token: token, sessid: sessid)
    }

    public func refreshActiveCredentials(uid: String, username: String, token: String) async {
        guard activeUID == uid, !token.isEmpty else { return }
        let existingCreds = readCredentials(for: uid)
        let sessid = existingCreds?.sessid ?? ""
        saveCredentials(uid: uid, token: token, sessid: sessid)
        let cleanName = username.removingPercentEncoding ?? username
        if let index = accounts.firstIndex(where: { $0.uid == uid }), !cleanName.isEmpty {
            accounts[index].username = cleanName
            persistMetadata()
        }
        let effectiveName = !cleanName.isEmpty ? cleanName : (accounts.first(where: { $0.uid == uid })?.username ?? uid)
        await CoolapkClient.shared.updateLogin(uid: uid, username: effectiveName, token: token, sessid: sessid)
    }

    public func switchTo(uid: String) async throws {
        guard let account = accounts.first(where: { $0.uid == uid }),
              !account.needsRelogin,
              let creds = readCredentials(for: uid),
              !creds.token.isEmpty else {
            throw APIError.message("此账号凭证已失效，请重新登录")
        }
        activeUID = uid
        persistMetadata()
        await CoolapkClient.shared.updateLogin(uid: uid, username: account.username, token: creds.token, sessid: creds.sessid)
    }

    public func useGuest() async {
        activeUID = nil
        persistMetadata()
        await CoolapkClient.shared.clearLogin()
    }

    public func remove(uid: String) async {
        deleteCredentials(for: uid)
        accounts.removeAll { $0.uid == uid }
        let wasActive = (activeUID == uid)
        if wasActive {
            activeUID = nil
        }
        persistMetadata()
        if wasActive {
            await CoolapkClient.shared.clearLogin()
        }
    }

    public func expireCurrent() async {
        guard let uid = activeUID,
              let index = accounts.firstIndex(where: { $0.uid == uid }) else { return }
        deleteCredentials(for: uid)
        accounts[index].needsRelogin = true
        activeUID = nil
        persistMetadata()
        await CoolapkClient.shared.clearLogin()
    }

    public func updateProfile(_ profile: UserProfile) {
        guard let index = accounts.firstIndex(where: { $0.uid == profile.id }) else { return }
        accounts[index].username = profile.username.isEmpty ? accounts[index].username : profile.username
        accounts[index].avatar = profile.avatar.isEmpty ? accounts[index].avatar : profile.avatar
        accounts[index].level = profile.level
        accounts[index].exp = profile.experience
        accounts[index].nextExp = profile.nextLevelExperience
        persistMetadata()
    }

    // MARK: - Persistence & Keychain

    private func loadFromDisk() {
        if let data = UserDefaults.standard.data(forKey: Self.accountsDefaultsKey),
           let decoded = try? JSONDecoder().decode([SavedAccount].self, from: data) {
            accounts = decoded
        }
        activeUID = UserDefaults.standard.string(forKey: Self.activeUIDDefaultsKey)
    }

    private func persistMetadata() {
        if let encoded = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(encoded, forKey: Self.accountsDefaultsKey)
        }
        UserDefaults.standard.set(activeUID, forKey: Self.activeUIDDefaultsKey)
    }

    private struct TokenRecord: Codable {
        let token: String
        let sessid: String
    }

    private func saveCredentials(uid: String, token: String, sessid: String) {
        guard let data = try? JSONEncoder().encode(TokenRecord(token: token, sessid: sessid)) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: uid
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private func readCredentials(for uid: String) -> TokenRecord? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: uid,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(TokenRecord.self, from: data)
    }

    private func deleteCredentials(for uid: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: uid
        ]
        SecItemDelete(query as CFDictionary)
    }
}
