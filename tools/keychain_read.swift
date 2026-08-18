import Foundation
import Security

guard CommandLine.arguments.count == 2 else {
    fputs("missing account\n", stderr)
    exit(2)
}

let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.pacificpride.workflow-assistant.jdy",
    kSecAttrAccount as String: CommandLine.arguments[1],
    kSecReturnData as String: true,
    kSecMatchLimit as String: kSecMatchLimitOne,
]
var result: CFTypeRef?
let status = SecItemCopyMatching(query as CFDictionary, &result)
guard status == errSecSuccess,
      let data = result as? Data,
      let password = String(data: data, encoding: .utf8),
      !password.isEmpty else {
    fputs("keychain read failed: \(status)\n", stderr)
    exit(3)
}
FileHandle.standardOutput.write(Data(password.utf8))
