import Foundation
import Security

/// API keys, one generic-password item per endpoint in the login keychain.
public struct KeychainStore: Sendable {
    public let service: String

    public init(service: String = "org.mlcommons.kurt.kurtkode.endpoint") {
        self.service = service
    }

    public enum KeychainError: Error, Sendable {
        case status(OSStatus)
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func apiKey(for endpointID: UUID) -> String? { secret(account: endpointID.uuidString) }
    public func setAPIKey(_ key: String, for endpointID: UUID) throws { try setSecret(key, account: endpointID.uuidString) }
    public func removeAPIKey(for endpointID: UUID) { removeSecret(account: endpointID.uuidString) }

    public func secret(account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        // A key pasted with a line break or spaces around it: a header value with a line break is dropped (the
        // server then says the key is missing), so keys are trimmed both ways.
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func setSecret(_ value: String, account: String) throws {
        let q = query(account)
        let data = Data(value.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            let s = SecItemAdd(add as CFDictionary, nil)
            guard s == errSecSuccess else { throw KeychainError.status(s) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    public func removeSecret(account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }

    /// Where MCP server tokens are kept: one item per server name and host, so a token set for a server is
    /// never sent to another host that a config later gives the same name.
    public static let mcp = KeychainStore(service: "org.mlcommons.kurt.kurtkode.mcp")

    public static func mcpAccount(server: String, url: String) -> String {
        "\(server)@\(URL(string: url)?.host() ?? url)"
    }
}
