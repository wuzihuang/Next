import SwiftUI

/// The panel is printed, not lit: every pixel of art is punched through a 4px dot screen,
/// and the space between dots is the panel's own ink. Reproduces the SVG `<pattern>` the
/// board uses on 04 · 07 · 13.
struct HalftoneScreen<Content: View>: View {
    var pitch: CGFloat = 4
    var radius: CGFloat = 1.6
    var ink: Color = NB.panelInk
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            ink
            content.mask(DotMask(pitch: pitch, radius: radius))
        }
        .drawingGroup()
    }
}

private struct DotMask: View {
    let pitch: CGFloat
    let radius: CGFloat

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
            var path = Path()
            var y = pitch / 2
            while y < size.height + pitch {
                var x = pitch / 2
                while x < size.width + pitch {
                    path.addEllipse(in: CGRect(x: x - radius, y: y - radius,
                                               width: radius * 2, height: radius * 2))
                    x += pitch
                }
                y += pitch
            }
            ctx.fill(path, with: .color(.white))
        }
    }
}
