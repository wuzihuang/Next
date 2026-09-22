import SwiftUI
import UIKit

/// The plate's photo, on the phone.
///
/// A meal row carries `photo_path` — an object in the private `meal-photos` bucket, whose
/// first path segment is the owner. That is the whole of the access control, so this store
/// asks for the bytes with the session's own token and keeps them in Caches: a photo the
/// person has already seen should not cost a request every time the fuel table scrolls.
///
/// A missing photo is not an error state. The row is the record; the photo is what lets a
/// person check it three hours later, and a plate with no photo simply has no thumbnail.
@MainActor
final class MealPhotoStore: ObservableObject {
    static let shared = MealPhotoStore()

    private var memory: [String: UIImage] = [:]
    private var inFlight: Set<String> = []
    /// Published so a view that asked for a path redraws when the bytes land.
    @Published private(set) var generation = 0

    private let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("meal-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    func image(for path: String?) -> UIImage? {
        guard let path, !path.isEmpty else { return nil }
        if let hit = memory[path] { return hit }
        let file = directory.appendingPathComponent(Self.filename(for: path))
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            memory[path] = image
            return image
        }
        load(path)
        return nil
    }

    /// The photo of a plate the phone wrote itself, kept before the row has ever been read
    /// back — so the receipt and the table show it during the seconds the upload is still
    /// in the air.
    func remember(_ image: UIImage, for path: String) {
        memory[path] = image
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: directory.appendingPathComponent(Self.filename(for: path)), options: .atomic)
        }
        generation &+= 1
    }

    private func load(_ path: String) {
        guard !inFlight.contains(path) else { return }
        inFlight.insert(path)
        Task { [weak self] in
            defer { Task { @MainActor in self?.inFlight.remove(path) } }
            guard let data = try? await SupabaseClient.shared.storageObject(bucket: "meal-photos", path: path),
                  let image = UIImage(data: data) else { return }
            await MainActor.run {
                guard let self else { return }
                self.memory[path] = image
                try? data.write(to: self.directory.appendingPathComponent(Self.filename(for: path)), options: .atomic)
                self.generation &+= 1
            }
        }
    }

    /// Signing out clears the bytes with everything else this account could see.
    func clear() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        generation &+= 1
    }

    private static func filename(for path: String) -> String {
        path.replacingOccurrences(of: "/", with: "_")
    }
}

/// A plate thumbnail that fills its frame, or nothing at all while there is nothing to show.
struct MealThumbnail: View {
    let path: String?
    var side: CGFloat = 44
    var radius: CGFloat = 10
    @ObservedObject private var store = MealPhotoStore.shared

    var body: some View {
        Group {
            if let image = store.image(for: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(NB.carbon3)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(NB.hairline, lineWidth: 1))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .id(store.generation)
    }
}
