import CryptoKit
import Foundation

// Prints only the public key; the private seed stays in the specified local file.
guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift update_signing_key.swift /path/to/private-key")
}
let path = URL(fileURLWithPath: CommandLine.arguments[1])
let key: Curve25519.Signing.PrivateKey
if FileManager.default.fileExists(atPath: path.path) {
    let encoded = try String(contentsOf: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let seed = Data(base64Encoded: encoded) else { fatalError("Invalid signing key file") }
    key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
} else {
    try FileManager.default.createDirectory(
        at: path.deletingLastPathComponent(), withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    key = Curve25519.Signing.PrivateKey()
    let seed = Data(key.rawRepresentation.base64EncodedString().utf8)
    guard FileManager.default.createFile(atPath: path.path, contents: seed, attributes: [.posixPermissions: 0o600]) else {
        fatalError("Cannot create signing key file")
    }
}
print(key.publicKey.rawRepresentation.base64EncodedString())
