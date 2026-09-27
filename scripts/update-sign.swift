// Release signing for OTA updates.
//   swift scripts/update-sign.swift keygen          prints a new key pair (keep PRIVATE secret)
//   SIDEBIT_UPDATE_KEY=<private> swift scripts/update-sign.swift sign dist/Sidebit-x-arm64.zip
import CryptoKit
import Foundation

let arguments = CommandLine.arguments
switch arguments.dropFirst().first {
case "keygen":
    let key = Curve25519.Signing.PrivateKey()
    print("PRIVATE=\(key.rawRepresentation.base64EncodedString())")
    print("PUBLIC=\(key.publicKey.rawRepresentation.base64EncodedString())")
case "sign" where arguments.count == 3:
    guard let secret = ProcessInfo.processInfo.environment["SIDEBIT_UPDATE_KEY"], let raw = Data(base64Encoded: secret),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        FileHandle.standardError.write(Data("Set SIDEBIT_UPDATE_KEY to the base64 private key.\n".utf8)); exit(1)
    }
    let archive = URL(fileURLWithPath: arguments[2])
    let signature = try key.signature(for: Data(contentsOf: archive)).base64EncodedString()
    try Data((signature + "\n").utf8).write(to: archive.appendingPathExtension("sig"))
    print("Signed: \(archive.lastPathComponent).sig")
default:
    FileHandle.standardError.write(Data("usage: update-sign.swift keygen | sign <zip>\n".utf8)); exit(2)
}
