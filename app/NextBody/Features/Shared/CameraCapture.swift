import SwiftUI
import UIKit

/// Presents the system camera on the key window. A SwiftUI `fullScreenCover` wrapping
/// `UIImagePickerController` is easy to lose under the plus-menu dismiss, so the shutter
/// is presented from UIKit after the overlay is gone.
@MainActor
enum CameraGate {
    static func present(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        Coordinator.shared.present(onCapture: onCapture, onCancel: onCancel)
    }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        static let shared = Coordinator()
        private var onCapture: ((UIImage) -> Void)?
        private var onCancel: (() -> Void)?

        func present(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                onCancel()
                return
            }
            guard let host = topPresenter() else {
                onCancel()
                return
            }
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            picker.allowsEditing = false
            picker.modalPresentationStyle = .fullScreen
            picker.delegate = self
            if UIImagePickerController.isCameraDeviceAvailable(.rear) {
                picker.cameraDevice = .rear
            }
            host.present(picker, animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) { [weak self] in
                self?.onCancel?()
                self?.clear()
            }
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            picker.dismiss(animated: true) { [weak self] in
                if let image {
                    self?.onCapture?(image)
                } else {
                    self?.onCancel?()
                }
                self?.clear()
            }
        }

        private func clear() {
            onCapture = nil
            onCancel = nil
        }

        private func topPresenter() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            let window = active?.windows.first { $0.isKeyWindow } ?? active?.windows.first
            guard var top = window?.rootViewController else { return nil }
            while let presented = top.presentedViewController, !presented.isBeingDismissed {
                top = presented
            }
            return top
        }
    }
}
