import SwiftUI
import UIKit

/// Persistent bitmap for Originkit Glitter Wrap: destination-out trail fade
/// plus additive square stamps. A blurred elliptical mask feathers all four
/// edges so the field blooms instead of clipping to the panel rect.
struct GlitterWrapStage: View {
    var paused: Bool

    var body: some View {
        GlitterWrapUIView(paused: paused)
            .mask { GlitterWrapHaloMask() }
    }
}

struct GlitterWrapHaloMask: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let m = max(1, min(w, h))
            RadialGradient(
                stops: [
                    .init(color: .white, location: 0.0),
                    .init(color: .white, location: 0.42),
                    .init(color: .white.opacity(0.7), location: 0.68),
                    .init(color: .white.opacity(0.18), location: 0.88),
                    .init(color: .clear, location: 1.0),
                ],
                center: .center,
                startRadius: 0,
                endRadius: m * 0.5
            )
            .scaleEffect(x: (w / m) * 0.98, y: (h / m) * 0.84, anchor: .center)
            .blur(radius: min(32, m * 0.09))
        }
    }
}

private struct GlitterWrapUIView: UIViewRepresentable {
    var paused: Bool

    func makeUIView(context: Context) -> GlitterWrapView {
        let view = GlitterWrapView()
        view.paused = paused
        return view
    }

    func updateUIView(_ view: GlitterWrapView, context: Context) {
        view.paused = paused
    }
}

final class GlitterWrapView: UIView {
    var paused = false {
        didSet {
            guard paused != oldValue else { return }
            applyPaused()
        }
    }

    private let field = GlitterWrapField(seed: UInt64.random(in: 1...UInt64.max))
    private var canvas: CGContext?
    private var canvasW = 0
    private var canvasH = 0
    private var canvasDpr: CGFloat = 1
    private var link: CADisplayLink?
    private let tickProxy = TickProxy()
    private var lastT: CFTimeInterval = 0
    private var baked = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        tickProxy.owner = self
    }

    required init?(coder: NSCoder) { nil }

    deinit { link?.invalidate() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            link?.invalidate()
            link = nil
            lastT = 0
        } else {
            startLinkIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ensureCanvas()
        if paused, !baked {
            for _ in 0..<80 { render(deltaSec: 1.0 / 60.0) }
            present()
            baked = true
        }
    }

    private func applyPaused() {
        if paused {
            link?.isPaused = true
            lastT = 0
        } else {
            baked = false
            startLinkIfNeeded()
            link?.isPaused = false
        }
    }

    private func startLinkIfNeeded() {
        guard window != nil, link == nil else {
            link?.isPaused = paused
            return
        }
        let link = CADisplayLink(target: tickProxy, selector: #selector(TickProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        link.isPaused = paused
        self.link = link
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let delta = lastT == 0 ? link.duration : now - lastT
        lastT = now
        render(deltaSec: delta)
        present()
    }

    private func ensureCanvas() {
        let dpr = min(window?.screen.scale ?? UIScreen.main.scale, 2)
        let w = max(1, Int(bounds.width.rounded(.down)))
        let h = max(1, Int(bounds.height.rounded(.down)))
        if canvasW == w, canvasH == h, canvasDpr == dpr, canvas != nil {
            field.width = Double(w)
            field.height = Double(h)
            return
        }
        canvasW = w
        canvasH = h
        canvasDpr = dpr
        field.width = Double(w)
        field.height = Double(h)
        let pw = max(1, Int((CGFloat(w) * dpr).rounded(.down)))
        let ph = max(1, Int((CGFloat(h) * dpr).rounded(.down)))
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: pw,
            height: ph,
            bitsPerComponent: 8,
            bytesPerRow: pw * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
        ctx?.translateBy(x: 0, y: CGFloat(ph))
        ctx?.scaleBy(x: dpr, y: -dpr)
        ctx?.clear(CGRect(x: 0, y: 0, width: w, height: h))
        canvas = ctx
        layer.contentsScale = dpr
        baked = false
    }

    private func render(deltaSec: Double) {
        ensureCanvas()
        guard let ctx = canvas else { return }
        let frame = field.step(deltaSec: deltaSec, moving: true)
        let w = CGFloat(max(1, canvasW))
        let h = CGFloat(max(1, canvasH))
        ctx.setAlpha(1)
        ctx.setBlendMode(.destinationOut)
        ctx.setFillColor(gray: 0, alpha: frame.trailAlpha)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setBlendMode(.plusLighter)
        let palette = field.config.palette
        for stamp in frame.stamps {
            let col = palette[min(max(stamp.colorIdx, 0), palette.count - 1)]
            let cr = CGFloat(col.r / 255), cg = CGFloat(col.g / 255), cb = CGFloat(col.b / 255)
            if let px = stamp.px, let py = stamp.py {
                ctx.setAlpha(stamp.alpha * 0.5)
                ctx.setStrokeColor(red: cr, green: cg, blue: cb, alpha: 1)
                ctx.setLineWidth(max(0.4, stamp.r * 0.4))
                ctx.beginPath()
                ctx.move(to: CGPoint(x: px, y: py))
                ctx.addLine(to: CGPoint(x: stamp.sx, y: stamp.sy))
                ctx.strokePath()
            }
            ctx.setAlpha(stamp.alpha)
            ctx.setFillColor(red: cr, green: cg, blue: cb, alpha: 1)
            let r = stamp.r
            ctx.fill(CGRect(x: stamp.sx - r, y: stamp.sy - r, width: r * 2, height: r * 2))
            if let rf = stamp.haloR {
                ctx.setAlpha(stamp.alpha * 0.5)
                ctx.fill(CGRect(x: stamp.sx - rf, y: stamp.sy - rf, width: rf * 2, height: rf * 2))
            }
        }
        ctx.setAlpha(1)
        ctx.setBlendMode(.normal)
    }

    private func present() {
        guard let image = canvas?.makeImage() else { return }
        layer.contents = image
        layer.contentsGravity = .resize
    }
}

private final class TickProxy: NSObject {
    weak var owner: GlitterWrapView?
    @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
}
