import Foundation

enum BandPersonalInfoPolicy {
    /// VPPeripheralBaseManage: 0 failure, 1 success; unknown replies are not success.
    static func acknowledged(_ result: UInt) -> Bool { result == 1 }

    static func owns(expectedAccount: String?, expectedBinding: String?,
                     account: String?, binding: String?, consent: Bool) -> Bool {
        consent && expectedBinding != nil && expectedAccount == account && expectedBinding == binding
    }
}
