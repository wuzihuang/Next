import SwiftUI
import UIKit

/// The panel is printed, not lit: every pixel of art is punched through a 4px dot screen,
/// and the space between dots is the panel's own ink. Reproduces the SVG `<pattern>` the
/// board uses on 04 · 07 · 13.
///
/// ⚠️ Performance. This used to be `content.mask(Canvas)` inside `.drawingGroup()`. The
/// canvas laid down ~15,000 ellipses (26,000 while the panel was the whole screen), and the
/// drawing group re-rasterised the *entire* subtree — art, animating pip, and that canvas —
/// into an offscreen texture on every frame the art moved. The standby pip pulses forever,
/// so the home screen paid that price 120 times a second on a ProMotion phone and never
/// stopped. The screen is now rasterised once, as an ink sheet with holes punched in it,
/// and laid over the art as a plain image: a single texture composite per frame, and the
/// pip's pulse is left to Core Animation, where it costs nothing.
struct HalftoneScreen<Content: View>: View {
    var pitch: CGFloat = 4
    var radius: CGFloat = 1.6
    var ink: Color = NB.panelInk
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            ink
            content
        }
        // The sheet is cut at the screen's own size and pinned top-leading, so a panel of any
        // size — including one whose frame is mid-fold — sees exactly the grid a mask of its
        // own size would have given it. Nothing is re-rendered when the frame animates.
        .overlay(alignment: .topLeading) {
            Image(uiImage: DotScreen.sheet(pitch: pitch, radius: radius, ink: ink))
                .fixedSize()
                .allowsHitTesting(false)
        }
        .clipped()
    }
}

/// One rasterised ink sheet per (pitch, radius, ink) for the life of the process.
private enum DotScreen {
    private struct Key: Hashable {
        let pitch: CGFloat, radius: CGFloat, ink: String, w: CGFloat, h: CGFloat, scale: CGFloat
    }
    private static var cache: [Key: UIImage] = [:]

    @MainActor
    static func sheet(pitch: CGFloat, radius: CGFloat, ink: Color) -> UIImage {
        let bounds = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        let inkColor = UIColor(ink)
        let key = Key(pitch: pitch, radius: radius, ink: inkColor.description,
                      w: bounds.width, h: bounds.height, scale: scale)
        if let hit = cache[key] { return hit }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: bounds, format: format).image { r in
            let cg = r.cgContext
            cg.setFillColor(inkColor.cgColor)
            cg.fill(CGRect(origin: .zero, size: bounds))
            // Holes, not white dots: clearing through the ink is what lets the art show.
            cg.setBlendMode(.clear)
            var y = pitch / 2
            while y < bounds.height + pitch {
                var x = pitch / 2
                while x < bounds.width + pitch {
                    cg.fillEllipse(in: CGRect(x: x - radius, y: y - radius,
                                              width: radius * 2, height: radius * 2))
                    x += pitch
                }
                y += pitch
            }
        }
        cache[key] = image
        return image
    }
}
