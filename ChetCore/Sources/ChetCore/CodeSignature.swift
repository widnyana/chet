import Foundation
import Security

/// The signing identity of code on disk. Ad-hoc and unsigned code has no Team ID, which
/// matters for the helper: `SMAppService` records a daemon from such a build but refuses to
/// start it, and `register()` answers with "Operation not permitted".
public enum CodeSignature {
    /// The Team ID of the bundle or executable at `url`, or nil when it has none.
    public static func teamID(of url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code
        else { return nil }
        var information: CFDictionary?
        guard
            SecCodeCopySigningInformation(
                code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
            let dictionary = information as? [String: Any],
            let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        else { return nil }
        return team
    }
}
