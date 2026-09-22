import SwiftUI

/// The idle collection shares one lighting model and one continuous, slow camera.
/// Coordinates are authored on the existing 358 × 470 panel; bodies stay circular
/// on every device and the lower third remains quiet behind the live readout.
struct DeepSpacePlate: View {
    let plate: Int
    let clock: Double

    var body: some View {
        let look = SpaceLook.collection[min(28, max(1, plate)) - 1]
        GeometryReader { geometry in
            Rectangle()
                .fill(.black)
                .colorEffect(ShaderLibrary.nbDeepSpace(
                    .float2(geometry.size), .float(clock), .float(Float(plate)),
                    .float4(look.x, look.y, look.radius, look.surface),
                    .float4(look.tilt, look.inclination, look.ringInner, look.ringOuter),
                    .color(Color(hex: look.shadow)), .color(Color(hex: look.light)),
                    .color(Color(hex: look.air)),
                    .float4(look.sunX, look.sunY, look.sunZ, look.nebula)
                ))
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SpaceLook {
    var x: Float = 179
    var y: Float = 174
    var radius: Float = 78
    /// 0 gas bands, 1 rock, 2 ocean/ice.
    var surface: Float = 0
    var tilt: Float = -18
    var inclination: Float = 0.32
    var ringInner: Float = 1.34
    var ringOuter: Float = 2.12
    var shadow: UInt32 = 0x655646
    var light: UInt32 = 0xE3D3AF
    var air: UInt32 = 0xAABAD1
    var sunX: Float = -0.78
    var sunY: Float = -0.48
    var sunZ: Float = 0.48
    var nebula: Float = 0.5

    /// Stable plate IDs preserve the daily/event selection policy. Each composition
    /// is authored separately; event colours remain restrained amber or blue.
    static let collection: [SpaceLook] = [
        .init(), // 01 · ivory rings
        .init(y: 169, radius: 106, surface: 1, ringOuter: 0,
              shadow: 0x575A60, light: 0xD5D7D6, air: 0x818997, sunZ: 0.68, nebula: 0.22),
        .init(y: 132, radius: 58, tilt: -6, inclination: 0.22,
              light: 0xE4E7E9, air: 0xB2C7DC, nebula: 0.4),
        .init(y: 171, radius: 48, tilt: -32, inclination: 0.55, ringInner: 1.8, ringOuter: 3.35,
              shadow: 0x3D4957, light: 0xACBDCB, air: 0x9AB8D0, sunZ: 0.18),
        .init(y: 168, radius: 75, tilt: -31, inclination: 0.26,
              shadow: 0x493A2A, light: 0xC5B395, air: 0xAD9680, sunZ: 0.08, nebula: 0.25),
        .init(x: 212, y: 152, radius: 46, surface: 1, tilt: -38, inclination: 0.4,
              ringInner: 2.25, ringOuter: 3.1, shadow: 0x414C58, light: 0xC4D1D8, nebula: 0.6),
        .init(y: 166, radius: 82, tilt: -24, inclination: 0.3, ringOuter: 1.83,
              shadow: 0x314956, light: 0xA0BBCB, air: 0x6CADD2, nebula: 0.38),
        .init(x: 147, y: 167, radius: 51, tilt: -25, inclination: 0.42,
              ringInner: 1.5, ringOuter: 3.0, shadow: 0x6C6252, light: 0xD1C7B3, nebula: 0.3),
        .init(y: 173, radius: 84, surface: 1, tilt: 22, inclination: 0.17,
              ringInner: 1.45, ringOuter: 1.87, shadow: 0x58524C, light: 0xC9C3B3, nebula: 0.45),
        .init(x: 221, y: 143, radius: 33, surface: 1, ringOuter: 0,
              shadow: 0x4D5863, light: 0xCAD6DA, sunZ: -0.05, nebula: 0.75),
        .init(x: 330, y: 144, radius: 173, tilt: -12, inclination: 0.27,
              shadow: 0x4A5155, light: 0xC6C9BD, air: 0x81949E, sunZ: 0.12, nebula: 0.25),
        .init(y: 168, radius: 78, tilt: -8, inclination: 0.24,
              shadow: 0x3D414B, light: 0x9BA3AF, air: 0x7489A5, sunZ: -0.36, nebula: 0.25),
        .init(x: 198, y: 145, radius: 45, surface: 2, tilt: -38, inclination: 0.5,
              ringInner: 1.9, ringOuter: 3.4, shadow: 0x294E67, light: 0xA9C9D7, air: 0x639DCA, nebula: 0.7),
        .init(y: 170, radius: 77, surface: 1, ringOuter: 0,
              shadow: 0x55504A, light: 0xD6D0C5, sunZ: -0.62, nebula: 0.4),
        .init(x: 171, y: 268, radius: 155, surface: 1, ringOuter: 0,
              shadow: 0x5B3024, light: 0xB98E64, air: 0xD58C54,
              sunX: -0.2, sunY: -0.9, sunZ: -0.22, nebula: 0.3),
        .init(x: 86, y: 126, radius: 108, surface: 2, ringOuter: 0,
              shadow: 0x1C395C, light: 0x6D9CBF, air: 0x528FD4, sunX: 0.7, sunZ: -0.12, nebula: 0.4),
        .init(y: 161, radius: 66, tilt: -20, inclination: 0.52, ringOuter: 2.35,
              shadow: 0x4A3E60, light: 0xB8AAC6, air: 0x9994D3, nebula: 0.85),
        .init(x: 214, y: 143, radius: 61, surface: 2, ringOuter: 0,
              shadow: 0x553C59, light: 0xB79EBB, air: 0xBC95BF, sunZ: 0.15, nebula: 1.25),
        .init(y: 168, radius: 73, tilt: -19, inclination: 0.34,
              shadow: 0x62585E, light: 0xD3C4B9, air: 0xB4A4CA, nebula: 0.65),
        .init(x: 335, y: 162, radius: 145, surface: 2, ringOuter: 0,
              shadow: 0x1C344B, light: 0x83AABD, air: 0x689FCA, sunZ: -0.04, nebula: 0.35),
        .init(x: 5, y: 177, radius: 153, surface: 2, ringOuter: 0,
              shadow: 0x1D3652, light: 0x6E9CBA, air: 0x528BBD, sunX: 0.85, sunZ: 0.12, nebula: 0.4),
        .init(y: 193, radius: 70, tilt: -6, inclination: 0.2,
              shadow: 0x5E594D, light: 0xD7CFB7, air: 0xB3BBC6, nebula: 0.4),
        .init(x: 160, y: 158, radius: 139, surface: 1, ringOuter: 0,
              shadow: 0x565A61, light: 0xC7C9CA, air: 0x8493A5, sunZ: 0.32, nebula: 0.2),
        .init(x: 273, y: 111, radius: 42, surface: 2, ringOuter: 0,
              shadow: 0x28434E, light: 0x8EB4C2, air: 0x7FB9D4, sunZ: 0.28, nebula: 1.0),
        .init(x: 183, y: 222, radius: 94, surface: 1, ringOuter: 0,
              shadow: 0x532D22, light: 0xBD9772, air: 0xD09261,
              sunX: 0.3, sunY: -0.85, sunZ: -0.5, nebula: 0.22),
        .init(x: 200, y: 169, radius: 91, surface: 2, ringOuter: 0,
              shadow: 0x303758, light: 0x969FCA, air: 0x849BE0, sunX: 0.9, sunZ: 0.1, nebula: 0.5),
        .init(x: 277, y: 86, radius: 113, surface: 1, ringOuter: 0,
              shadow: 0x444C53, light: 0xBAC6CD, air: 0x889FB4, sunZ: -0.28, nebula: 0.4),
        .init(y: 169, radius: 80, tilt: -2, inclination: 0.09,
              ringInner: 1.25, ringOuter: 2.4, shadow: 0x3C4B56, light: 0xBDC9CA,
              air: 0x90B1C9, sunZ: 0.18, nebula: 0.4),
    ]
}
