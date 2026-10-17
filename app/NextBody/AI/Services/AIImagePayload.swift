import UIKit

struct AIImagePayload {
    static let targetBytes = 96 * 1024

    let preview: UIImage
    let dataURL: String
    let byteCount: Int

    /// Keeps enough detail for food/general vision while bounding JSON + Base64 overhead.
    /// The last attempt is the quality floor; going lower makes labels and small objects
    /// unreliable, so an unusually complex image may exceed the soft target slightly.
    static func prepare(_ raw: UIImage) -> AIImagePayload? {
        let attempts: [(side: CGFloat, qualities: [CGFloat])] = [
            (640, [0.55, 0.45, 0.35]),
            (512, [0.40, 0.32]),
        ]
        var smallest: (image: UIImage, data: Data)?

        for attempt in attempts {
            let image = raw.nb_resized(maxSide: attempt.side)
            for quality in attempt.qualities {
                guard let data = image.jpegData(compressionQuality: quality) else { continue }
                if let current = smallest {
                    if data.count < current.data.count {
                        smallest = (image, data)
                    }
                } else {
                    smallest = (image, data)
                }
                if data.count <= targetBytes {
                    return payload(image: image, data: data)
                }
            }
        }

        guard let smallest else { return nil }
        return payload(image: smallest.image, data: smallest.data)
    }

    private static func payload(image: UIImage, data: Data) -> AIImagePayload {
        AIImagePayload(
            preview: image,
            dataURL: "data:image/jpeg;base64," + data.base64EncodedString(),
            byteCount: data.count
        )
    }
}
