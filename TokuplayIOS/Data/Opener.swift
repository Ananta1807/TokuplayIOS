import Foundation
import CommonCrypto
import CryptoKit

/// Port of com.androidku.tokuplay.domain.util.Opener.a (see decrypt_plugin.js).
/// Input = 3 decoy characters + base64 tail; "U2FsdGVkX1" is prepended to rebuild the OpenSSL "Salted__" header.
/// KDF: EVP_BytesToKey(MD5, 1 iteration, password = package name, salt). Cipher: AES-256-CBC/PKCS7.
enum Opener {
    static let packageName = "com.androidku.tokuplay"
    private static let prefix = "U2FsdGVkX1"

    static func decrypt(_ text: String, password: String = packageName) -> String? {
        guard text.count > 3,
              let raw = Data(base64Encoded: prefix + String(text.dropFirst(3))),
              raw.count > 16 else { return nil }
        let salt = raw.subdata(in: 8..<16)
        let cipher = raw.subdata(in: 16..<raw.count)
        let (key, iv) = deriveKeyIV(password: Data(password.utf8), salt: salt)

        var out = [UInt8](repeating: 0, count: cipher.count + kCCBlockSizeAES128)
        var written = 0
        let status = cipher.withUnsafeBytes { c in
            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                    key, key.count, iv, c.baseAddress, cipher.count, &out, out.count, &written)
        }
        guard status == kCCSuccess else { return nil }
        return String(data: Data(out.prefix(written)), encoding: .utf8)
    }

    private static func deriveKeyIV(password: Data, salt: Data) -> ([UInt8], [UInt8]) {
        var material = Data()
        var previous = Data()
        while material.count < 48 {
            var md5 = Insecure.MD5()
            md5.update(data: previous)
            md5.update(data: password)
            md5.update(data: salt)
            previous = Data(md5.finalize())
            material.append(previous)
        }
        let bytes = [UInt8](material)
        return (Array(bytes[0..<32]), Array(bytes[32..<48]))
    }
}
