import Foundation

/// Compares only server-supplied identity evidence. Callers must still require
/// exactly one matching record before changing that token's expiry.
public enum CanvasTokenIdentity {
    public static func matches(token: String, hint: String?, visibleToken: String?) -> Bool {
        guard let credential = TokenParts(token), credential.secret.count >= 5 else { return false }
        var checks: [Bool] = []
        if let hint, !hint.isEmpty {
            checks.append(matchesPrefix(hint, credential: credential))
        }
        if let visibleToken, !visibleToken.isEmpty {
            if visibleToken == token {
                checks.append(true)
            } else if visibleToken.hasSuffix("...") {
                checks.append(matchesPrefix(String(visibleToken.dropLast(3)), credential: credential))
            } else if visibleToken.hasSuffix("…") {
                checks.append(matchesPrefix(String(visibleToken.dropLast()), credential: credential))
            } else {
                checks.append(false)
            }
        }
        // Conflicting fields are not permission to choose whichever one matches.
        return !checks.isEmpty && checks.allSatisfy { $0 }
    }

    private static func matchesPrefix(_ text: String, credential: TokenParts) -> Bool {
        guard let candidate = TokenParts(text), candidate.secret.count >= 5 else { return false }
        if let shard = candidate.shard, shard != credential.shard { return false }
        // A raw display prefix can stop inside the public shard number. Even if
        // the secret coincidentally starts with those digits, it is not evidence.
        if candidate.shard == nil, let shard = credential.shard, shard.hasPrefix(candidate.secret) { return false }
        return credential.secret.hasPrefix(candidate.secret)
    }

    private struct TokenParts {
        let shard: String?
        let secret: String

        init?(_ text: String) {
            guard !text.isEmpty, text.utf8.count <= 4096,
                  text.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }),
                  !text.contains("."), !text.contains("*"), !text.contains("•") else { return nil }
            let parts = text.split(separator: "~", omittingEmptySubsequences: false)
            if parts.count == 1 {
                shard = nil
                secret = text
            } else if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
                      parts[0].utf8.allSatisfy({ (48...57).contains($0) }) {
                shard = String(parts[0])
                secret = String(parts[1])
            } else { return nil }
        }
    }
}
