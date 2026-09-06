import Foundation
import LocalAuthentication

/// Only an explicit missing-passcode error permits the handoff's unauthenticated fallback.
enum DeviceAuthentication {
    static func hasNoPasscode(_ error: NSError?) -> Bool {
        error?.domain == LAError.errorDomain && error?.code == LAError.passcodeNotSet.rawValue
    }
}
