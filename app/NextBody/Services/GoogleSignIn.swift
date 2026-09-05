import Foundation
import GoogleSignIn
import UIKit

/// 01 · the third button on the gate. The account picker hands back a Google identity token;
/// the token buys a Supabase session at the same `/auth/v1/token?grant_type=id_token` the
/// Apple path uses, under the same nonce convention (hash out, raw to the server).
///
/// The sheet is the whole UI, like Apple's: nothing of ours is drawn until the server has
/// answered. Cancelling is `Failure.cancelled` and the gate stays silent (01 edge 5).
@MainActor
enum GoogleAuth {
    struct Credential {
        let idToken: String
        /// The raw nonce; its SHA-256 is what the token carries.
        let nonce: String
        /// Unlike Apple, Google returns the profile name on *every* sign-in, so this is not
        /// a one-shot. It is still only adopted when the server has no name yet.
        let fullName: String?
    }

    enum Failure: Error { case cancelled, noToken, noPresenter }

    static func request() async throws -> Credential {
        guard let presenter = topViewController() else { throw Failure.noPresenter }
        let raw = Nonce.random()
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter, hint: nil, additionalScopes: nil, nonce: Nonce.sha256(raw))
            guard let idToken = result.user.idToken?.tokenString else { throw Failure.noToken }
            return Credential(idToken: idToken, nonce: raw, fullName: result.user.profile?.name)
        } catch let error as NSError where error.code == GIDSignInError.canceled.rawValue {
            throw Failure.cancelled
        }
    }

    /// Signing out of Supabase without this leaves the SDK's cached account in place, and the
    /// next tap on the gate would sign the same person back in without ever showing a picker.
    static func signOut() { GIDSignIn.sharedInstance.signOut() }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
            ?? scenes.first?.windows.first?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}
