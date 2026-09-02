import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// 01 · the first button on the gate. Sign in with Apple through the system sheet, with a
/// nonce so the identity token that comes back can only ever open this one request.
///
/// The sheet is the whole UI: nothing of ours is drawn until the server has answered.
/// Cancelling the sheet is `Failure.cancelled` and the gate stays silent (01 edge 5);
/// anything else is a token failure and the gate says so.
@MainActor
final class AppleSignIn: NSObject {
    struct Credential {
        let idToken: String
        /// The raw nonce; its SHA-256 is what the token carries.
        let nonce: String
    }

    enum Failure: Error { case cancelled, noToken, system(Error) }

    private var continuation: CheckedContinuation<Credential, Error>?
    private var rawNonce = ""
    private var controller: ASAuthorizationController?

    func request() async throws -> Credential {
        rawNonce = Self.randomNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email, .fullName]
        request.nonce = Self.sha256(rawNonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller

        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<Credential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }

    private static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension AppleSignIn: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = cred.identityToken, let token = String(data: data, encoding: .utf8) else {
            finish(.failure(Failure.noToken)); return
        }
        finish(.success(Credential(idToken: token, nonce: rawNonce)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let e = error as? ASAuthorizationError, e.code == .canceled {
            finish(.failure(Failure.cancelled))
        } else {
            finish(.failure(Failure.system(error)))
        }
    }
}

extension AppleSignIn: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
            ?? ASPresentationAnchor()
    }
}
