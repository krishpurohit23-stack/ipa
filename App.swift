// World.swift  -  "enter my world": top-down open-world crime sandbox (SpriteKit, 100% offline)
import SwiftUI
import SpriteKit
import UIKit

// MARK: - Orientation (sirf is game me landscape)

enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .portrait
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return OrientationLock.mask
    }
}

func setLandscape(_ on: Bool) {
    OrientationLock.mask = on ? .landscape : .portrait
    guard let ws = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
    if #available(iOS 16.0, *) {
        ws.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: on ? .landscapeRight : .portrait)
        ws.requestGeometryUpdate(prefs) { _ in }
    } else {
        let o: UIInterfaceOrientation = on ? .landscapeRight : .portrait
        UIDevice.current.setValue(o.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }
}

// MARK: - SwiftUI wrapper

struct WorldView: View {
    var onExit: () -> Void
    @State private var scene: WorldScene = WorldScene.make()

    var body: some View {
        ZStack(alignment: .topLeading) {
            SpriteView(scene: scene)
                .ignoresSafeArea()
            Button(action: {
                scene.saveGame()
                onExit()
            }) {
                Text("✕")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }
            .padding(12)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { setLandscape(true) }
        .onDisappear { setLandscape(false) }
    }
}

// MARK: - Helpers

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor {
    return UIColor(red: r, green: g, blue: b, alpha: a)
}

func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    return hypot(a.x - b.x, a.y - b.y)
}

func clampf(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
    return min(max(v, lo), hi)
}

func angDiff(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
    var d = (a - b).truncatingRemainder(dividingBy: 2 * CGFloat.pi)
    if d > CGFloat.pi { d -= 2 * CGFloat.pi }
    if d < -CGFloat.pi { d += 2 * CGFloat.pi }
    return d
}

func dirVec(_ d: Int) -> CGVector {
    switch d {
    case 0: return CGVector(dx: 1, dy: 0)
    case 1: return CGVector(dx: 0, dy: 1)
    case 2: return CGVector(dx: -1, dy: 0)
    default: return CGVector(dx: 0, dy: -1)
    }
}

func laneOffset(_ d: Int) -> CGFloat {
    return (d == 0 || d == 3) ? -14 : 14
}

extension UIColor {
    func shade(_ f: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: min(1, r * f), green: min(1, g * f), blue: min(1, b * f), alpha: a)
    }
}

struct RNG {
    var s: UInt64
    init(_ seed: Int) {
        s = UInt64(truncatingIfNeeded: seed) &* 0x9E3779B97F4A7C15 &+ 0x1234567
    }
    mutating func next() -> UInt64 {
        s = s &+ 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func f() -> CGFloat {
        return CGFloat(next() % 100000) / 100000
    }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        return a + (b - a) * f()
    }
    mutating func i(_ n: Int) -> Int {
        return Int(next() % UInt64(n))
    }
}

// MARK: - World constants + map data

enum W {
    static let n = 8
    static let cell: CGFloat = 384
    static let road: CGFloat = 96
    static let chunk: CGFloat = 768
    static let texScale: CGFloat = 1.5
    static var size: CGFloat { return CGFloat(n) * cell }
    static func c(_ k: Int) -> CGFloat { return CGFloat(k) * cell + road / 2 }
}

enum BlockKind { case buildings, park, bank, jewelry, gang, safehouse }

struct Block {
    var kind: BlockKind
    var area: CGRect
    var rects: [CGRect]
    var colors: [UIColor]
}

let neonColors: [UIColor] = [
    rgb(1.0, 0.2, 0.6), rgb(0.2, 0.9, 1.0), rgb(1.0, 0.7, 0.2), rgb(0.35, 1.0, 0.55), rgb(0.7, 0.45, 1.0)
]

func buildBlocks() -> [Block] {
    var out: [Block] = []
    let roofs: [UIColor] = [
        rgb(0.30, 0.32, 0.40), rgb(0.38, 0.30, 0.30), rgb(0.28, 0.36, 0.36),
        rgb(0.40, 0.38, 0.32), rgb(0.33, 0.30, 0.42), rgb(0.26, 0.28, 0.32)
    ]
    for i in 0..<W.n {
        for j in 0..<W.n {
            var rng = RNG(i * 31 + j * 7 + 3)
            let side = W.cell - W.road
            let area = CGRect(x: CGFloat(i) * W.cell + W.road, y: CGFloat(j) * W.cell + W.road, width: side, height: side)
            let inner = area.insetBy(dx: 18, dy: 18)
            var kind = BlockKind.buildings
            if i == 3 && j == 3 {
                kind = .bank
            } else if i == 5 && j == 2 {
                kind = .jewelry
            } else if (i == 1 && j == 5) || (i == 6 && j == 6) || (i == 6 && j == 1) {
                kind = .gang
            } else if i == 2 && j == 6 {
                kind = .safehouse
            } else if rng.f() < 0.15 {
                kind = .park
            }
            var rects: [CGRect] = []
            switch kind {
            case .buildings:
                let mode = rng.i(3)
                if mode == 0 {
                    rects = [inner]
                } else if mode == 1 {
                    let split = rng.range(0.4, 0.6) * inner.width
                    rects = [
                        CGRect(x: inner.minX, y: inner.minY, width: split - 5, height: inner.height),
                        CGRect(x: inner.minX + split + 5, y: inner.minY, width: inner.width - split - 5, height: inner.height)
                    ]
                } else {
                    let hw = inner.width / 2 - 5
                    let hh = inner.height / 2 - 5
                    rects = [
                        CGRect(x: inner.minX, y: inner.minY, width: hw, height: hh),
                        CGRect(x: inner.maxX - hw, y: inner.minY, width: hw, height: hh),
                        CGRect(x: inner.minX, y: inner.maxY - hh, width: hw, height: hh),
                        CGRect(x: inner.maxX - hw, y: inner.maxY - hh, width: hw, height: hh)
                    ]
                }
            case .park:
                rects = []
            case .bank:
                rects = [CGRect(x: inner.minX + 20, y: inner.minY + 30, width: inner.width - 40, height: inner.height - 60)]
            case .jewelry:
                rects = [CGRect(x: inner.minX + 40, y: inner.minY + 40, width: inner.width - 80, height: 120)]
            case .gang:
                rects = [
                    CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: 70),
                    CGRect(x: inner.minX, y: inner.minY + 70, width: 60, height: inner.height - 70)
                ]
            case .safehouse:
                rects = [CGRect(x: inner.minX + 30, y: inner.maxY - 110, width: 110, height: 100)]
            }
            var cols: [UIColor] = []
            for _ in rects { cols.append(roofs[rng.i(roofs.count)]) }
            if kind == .bank { cols = [rgb(0.62, 0.60, 0.55)] }
            if kind == .jewelry { cols = [rgb(0.40, 0.30, 0.46)] }
            if kind == .gang { cols = [rgb(0.38, 0.16, 0.14), rgb(0.30, 0.14, 0.12)] }
            if kind == .safehouse { cols = [rgb(0.30, 0.42, 0.34)] }
            out.append(Block(kind: kind, area: area, rects: rects, colors: cols))
        }
    }
    return out
}

func buildManholes() -> [CGPoint] {
    var out: [CGPoint] = []
    for i in 0..<W.n {
        for j in 0..<W.n where (i + j) % 2 == 0 {
            out.append(CGPoint(x: W.c(i) + 30, y: W.c(j) - 30))
        }
    }
    return out
}

// MARK: - Texture rendering helpers

var texCache: [String: SKTexture] = [:]

func renderTex(_ size: CGSize, _ scale: CGFloat, _ draw: (CGContext) -> Void) -> SKTexture {
    let f = UIGraphicsImageRendererFormat.default()
    f.scale = scale
    f.opaque = false
    let r = UIGraphicsImageRenderer(size: size, format: f)
    let img = r.image { rc in draw(rc.cgContext) }
    return SKTexture(image: img)
}

func rrect(_ g: CGContext, _ r: CGRect, _ rad: CGFloat, _ col: UIColor) {
    g.setFillColor(col.cgColor)
    g.addPath(UIBezierPath(roundedRect: r, cornerRadius: rad).cgPath)
    g.fillPath()
}

func ell(_ g: CGContext, _ r: CGRect, _ col: UIColor) {
    g.setFillColor(col.cgColor)
    g.fillEllipse(in: r)
}

func box(_ g: CGContext, _ r: CGRect, _ col: UIColor) {
    g.setFillColor(col.cgColor)
    g.fill(r)
}

func vGradient(_ g: CGContext, _ r: CGRect, _ top: UIColor, _ bot: UIColor, _ rad: CGFloat) {
    g.saveGState()
    g.addPath(UIBezierPath(roundedRect: r, cornerRadius: rad).cgPath)
    g.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let cols = [top.cgColor, bot.cgColor] as CFArray
    if let gr = CGGradient(colorsSpace: cs, colors: cols, locations: [0, 1]) {
        g.drawLinearGradient(gr, start: CGPoint(x: r.midX, y: r.minY), end: CGPoint(x: r.midX, y: r.maxY), options: [])
    }
    g.restoreGState()
}

func glowFill(_ g: CGContext, _ c: CGPoint, _ r: CGFloat, _ col: UIColor, _ a: CGFloat) {
    let cs = CGColorSpaceCreateDeviceRGB()
    var cr: CGFloat = 0, cg: CGFloat = 0, cb: CGFloat = 0, ca: CGFloat = 0
    col.getRed(&cr, green: &cg, blue: &cb, alpha: &ca)
    let c0 = UIColor(red: cr, green: cg, blue: cb, alpha: a).cgColor
    let c1 = UIColor(red: cr, green: cg, blue: cb, alpha: 0).cgColor
    let cols = [c0, c1] as CFArray
    if let gr = CGGradient(colorsSpace: cs, colors: cols, locations: [0, 1]) {
        g.saveGState()
        g.setBlendMode(.plusLighter)
        g.drawRadialGradient(gr, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
        g.restoreGState()
    }
}

func streakFill(_ g: CGContext, _ rect: CGRect, _ from: CGPoint, _ to: CGPoint, _ col: UIColor, _ a: CGFloat) {
    let cs = CGColorSpaceCreateDeviceRGB()
    var cr: CGFloat = 0, cg: CGFloat = 0, cb: CGFloat = 0, ca: CGFloat = 0
    col.getRed(&cr, green: &cg, blue: &cb, alpha: &ca)
    let c0 = UIColor(red: cr, green: cg, blue: cb, alpha: a).cgColor
    let c1 = UIColor(red: cr, green: cg, blue: cb, alpha: 0).cgColor
    let cols = [c0, c1] as CFArray
    if let gr = CGGradient(colorsSpace: cs, colors: cols, locations: [0, 1]) {
        g.saveGState()
        g.clip(to: rect)
        g.setBlendMode(.plusLighter)
        g.drawLinearGradient(gr, start: from, end: to, options: [])
        g.restoreGState()
    }
}

func drawRoof(_ g: CGContext, _ r: CGRect, _ col: UIColor, _ rng: inout RNG) {
    box(g, r.offsetBy(dx: 15, dy: -15), rgb(0, 0, 0, 0.40))
    box(g, r, col.shade(0.55))
    let top = r.insetBy(dx: 3, dy: 3)
    box(g, top, col)
    box(g, CGRect(x: top.minX, y: top.midY, width: top.width, height: top.height / 2), rgb(1, 1, 1, 0.05))
    g.setStrokeColor(col.shade(0.78).cgColor)
    g.setLineWidth(1)
    var t: CGFloat = 40
    while t < top.width {
        g.move(to: CGPoint(x: top.minX + t, y: top.minY))
        g.addLine(to: CGPoint(x: top.minX + t, y: top.maxY))
        t += 40
    }
    g.strokePath()
    let count = Int(r.width * r.height / 5500) + 1
    for _ in 0..<count {
        let w = rng.range(10, 20)
        let h = rng.range(9, 16)
        if top.width < w + 20 || top.height < h + 20 { continue }
        let x = rng.range(top.minX + 6, top.maxX - w - 6)
        let y = rng.range(top.minY + 6, top.maxY - h - 6)
        box(g, CGRect(x: x + 3, y: y - 3, width: w, height: h), rgb(0, 0, 0, 0.3))
        box(g, CGRect(x: x, y: y, width: w, height: h), rgb(0.52, 0.54, 0.58))
        ell(g, CGRect(x: x + w / 2 - 4, y: y + h / 2 - 4, width: 8, height: 8), rgb(0.2, 0.22, 0.25))
    }
}

func renderChunk(_ ca: Int, _ cb: Int, _ blocks: [Block], _ manholes: [CGPoint]) -> UIImage {
    let cs = W.chunk
    let fmt = UIGraphicsImageRendererFormat.default()
    fmt.scale = W.texScale
    fmt.opaque = true
    let rend = UIGraphicsImageRenderer(size: CGSize(width: cs, height: cs), format: fmt)
    let ox = CGFloat(ca) * cs
    let oy = CGFloat(cb) * cs
    let per = Int(cs / W.cell)
    let i0 = ca * per
    let j0 = cb * per
    let cell = W.cell
    return rend.image { rc in
        let g = rc.cgContext
        g.translateBy(x: -ox, y: cs + oy)
        g.scaleBy(x: 1, y: -1)
        var rng = RNG(ca * 977 + cb * 131 + 5)

        // wet asphalt base
        box(g, CGRect(x: ox, y: oy, width: cs, height: cs), rgb(0.085, 0.095, 0.13))
        for _ in 0..<1400 {
            let x = ox + rng.f() * cs
            let y = oy + rng.f() * cs
            let a = rng.range(0.03, 0.10)
            let col: UIColor = rng.f() < 0.5 ? rgb(0, 0, 0, a) : rgb(0.6, 0.65, 0.8, a * 0.6)
            box(g, CGRect(x: x, y: y, width: rng.range(1, 3), height: rng.range(1, 2)), col)
        }
        // puddles
        for _ in 0..<16 {
            let jj = min(W.n - 1, j0 + rng.i(per))
            let ii = min(W.n - 1, i0 + rng.i(per))
            if rng.f() < 0.5 {
                let y = W.c(jj) + rng.range(-38, 38)
                let x = ox + rng.f() * cs
                ell(g, CGRect(x: x, y: y, width: rng.range(30, 70), height: rng.range(8, 16)), rgb(0.40, 0.50, 0.70, 0.08))
            } else {
                let x = W.c(ii) + rng.range(-38, 38)
                let y = oy + rng.f() * cs
                ell(g, CGRect(x: x, y: y, width: rng.range(8, 16), height: rng.range(30, 70)), rgb(0.40, 0.50, 0.70, 0.08))
            }
        }

        // road markings
        for k in 0..<W.n {
            let cc = W.c(k)
            for a in 0..<per {
                // horizontal road k, arms inside this chunk
                let i = i0 + a
                if i < W.n && cc + 60 >= oy && cc - 60 <= oy + cs {
                    let x0 = CGFloat(i) * cell + W.road
                    box(g, CGRect(x: x0, y: cc - 2.5, width: cell - W.road, height: 2), rgb(0.9, 0.72, 0.2, 0.8))
                    box(g, CGRect(x: x0, y: cc + 0.5, width: cell - W.road, height: 2), rgb(0.9, 0.72, 0.2, 0.8))
                    box(g, CGRect(x: x0, y: cc - 44, width: cell - W.road, height: 1.5), rgb(1, 1, 1, 0.22))
                    box(g, CGRect(x: x0, y: cc + 42, width: cell - W.road, height: 1.5), rgb(1, 1, 1, 0.22))
                }
                let j = j0 + a
                if j < W.n && cc + 60 >= ox && cc - 60 <= ox + cs {
                    let y0 = CGFloat(j) * cell + W.road
                    box(g, CGRect(x: cc - 2.5, y: y0, width: 2, height: cell - W.road), rgb(0.9, 0.72, 0.2, 0.8))
                    box(g, CGRect(x: cc + 0.5, y: y0, width: 2, height: cell - W.road), rgb(0.9, 0.72, 0.2, 0.8))
                    box(g, CGRect(x: cc - 44, y: y0, width: 1.5, height: cell - W.road), rgb(1, 1, 1, 0.22))
                    box(g, CGRect(x: cc + 42, y: y0, width: 1.5, height: cell - W.road), rgb(1, 1, 1, 0.22))
                }
            }
        }
        // crosswalks
        for i in i0..<min(W.n, i0 + per) {
            for j in j0..<min(W.n, j0 + per) {
                var t: CGFloat = 6
                while t < 90 {
                    box(g, CGRect(x: CGFloat(i) * cell + 100, y: CGFloat(j) * cell + t, width: 14, height: 6), rgb(1, 1, 1, 0.5))
                    box(g, CGRect(x: CGFloat(i) * cell + t, y: CGFloat(j) * cell + 100, width: 6, height: 14), rgb(1, 1, 1, 0.5))
                    t += 12
                }
            }
        }
        // manholes
        for m in manholes where m.x > ox - 14 && m.x < ox + cs + 14 && m.y > oy - 14 && m.y < oy + cs + 14 {
            ell(g, CGRect(x: m.x - 10, y: m.y - 10, width: 20, height: 20), rgb(0.30, 0.31, 0.34))
            ell(g, CGRect(x: m.x - 8, y: m.y - 8, width: 16, height: 16), rgb(0.06, 0.06, 0.08))
            g.setStrokeColor(rgb(0.25, 0.26, 0.3).cgColor)
            g.setLineWidth(1.2)
            for q in -2...2 {
                g.move(to: CGPoint(x: m.x - 7, y: m.y + CGFloat(q) * 3))
                g.addLine(to: CGPoint(x: m.x + 7, y: m.y + CGFloat(q) * 3))
            }
            g.strokePath()
        }

        // sidewalks + block ground
        for i in i0..<min(W.n, i0 + per) {
            for j in j0..<min(W.n, j0 + per) {
                let b = blocks[i * W.n + j]
                box(g, b.area, rgb(0.25, 0.26, 0.30))
                g.setStrokeColor(rgb(0.42, 0.43, 0.48, 0.9).cgColor)
                g.setLineWidth(2)
                g.stroke(b.area.insetBy(dx: 1, dy: 1))
                g.setStrokeColor(rgb(0, 0, 0, 0.18).cgColor)
                g.setLineWidth(1)
                var t: CGFloat = 24
                while t < b.area.width {
                    g.move(to: CGPoint(x: b.area.minX + t, y: b.area.minY))
                    g.addLine(to: CGPoint(x: b.area.minX + t, y: b.area.maxY))
                    g.move(to: CGPoint(x: b.area.minX, y: b.area.minY + t))
                    g.addLine(to: CGPoint(x: b.area.maxX, y: b.area.minY + t))
                    t += 24
                }
                g.strokePath()
                let inner = b.area.insetBy(dx: 18, dy: 18)
                switch b.kind {
                case .park:
                    box(g, inner, rgb(0.10, 0.22, 0.12))
                    g.setStrokeColor(rgb(0.55, 0.52, 0.45, 0.5).cgColor)
                    g.setLineWidth(6)
                    g.move(to: CGPoint(x: inner.minX, y: inner.midY))
                    g.addLine(to: CGPoint(x: inner.maxX, y: inner.midY))
                    g.move(to: CGPoint(x: inner.midX, y: inner.minY))
                    g.addLine(to: CGPoint(x: inner.midX, y: inner.maxY))
                    g.strokePath()
                case .bank:
                    box(g, inner, rgb(0.33, 0.33, 0.36))
                case .gang:
                    box(g, inner, rgb(0.16, 0.14, 0.13))
                    for _ in 0..<8 {
                        ell(g, CGRect(x: rng.range(inner.minX + 70, inner.maxX - 30), y: rng.range(inner.minY + 80, inner.maxY - 30), width: rng.range(14, 40), height: rng.range(10, 24)), rgb(0, 0, 0, 0.35))
                    }
                case .safehouse:
                    box(g, inner, rgb(0.13, 0.25, 0.15))
                case .jewelry:
                    box(g, inner, rgb(0.26, 0.24, 0.30))
                case .buildings:
                    box(g, inner, rgb(0.14, 0.15, 0.18))
                }
            }
        }

        // street lamp glows (wet road look)
        for i in max(0, i0 - 1)...min(W.n - 1, i0 + per) {
            for j in max(0, j0 - 1)...min(W.n - 1, j0 + per) {
                let bx = CGFloat(i) * cell
                let by = CGFloat(j) * cell
                let lamps: [CGPoint] = [
                    CGPoint(x: bx + 6, y: by + 6), CGPoint(x: bx + 90, y: by + 6),
                    CGPoint(x: bx + 6, y: by + 90), CGPoint(x: bx + 90, y: by + 90)
                ]
                for l in lamps {
                    glowFill(g, l, 150, rgb(1.0, 0.78, 0.45), 0.34)
                }
            }
        }
        for i in i0..<min(W.n, i0 + per) {
            for j in j0..<min(W.n, j0 + per) {
                let bx = CGFloat(i) * cell
                let by = CGFloat(j) * cell
                let lamps: [CGPoint] = [
                    CGPoint(x: bx + 6, y: by + 6), CGPoint(x: bx + 90, y: by + 6),
                    CGPoint(x: bx + 6, y: by + 90), CGPoint(x: bx + 90, y: by + 90)
                ]
                for l in lamps {
                    ell(g, CGRect(x: l.x - 3, y: l.y - 3, width: 6, height: 6), rgb(0.3, 0.3, 0.33))
                    ell(g, CGRect(x: l.x - 1.8, y: l.y - 1.8, width: 3.6, height: 3.6), rgb(1, 0.95, 0.75))
                }
            }
        }

        // buildings, trees, neon
        for i in i0..<min(W.n, i0 + per) {
            for j in j0..<min(W.n, j0 + per) {
                let b = blocks[i * W.n + j]
                let inner = b.area.insetBy(dx: 18, dy: 18)
                if b.kind == .park {
                    for _ in 0..<10 {
                        let tx = rng.range(inner.minX + 14, inner.maxX - 14)
                        let ty = rng.range(inner.minY + 14, inner.maxY - 14)
                        let rad = rng.range(10, 17)
                        ell(g, CGRect(x: tx - rad + 8, y: ty - rad - 8, width: rad * 2, height: rad * 2), rgb(0, 0, 0, 0.35))
                        ell(g, CGRect(x: tx - rad, y: ty - rad, width: rad * 2, height: rad * 2), rgb(0.10, 0.27, 0.14))
                        ell(g, CGRect(x: tx - rad * 0.6 - 2, y: ty - rad * 0.6 + 2, width: rad * 1.2, height: rad * 1.2), rgb(0.16, 0.38, 0.19))
                    }
                    continue
                }
                for (k, r) in b.rects.enumerated() {
                    let col = b.colors[min(k, b.colors.count - 1)]
                    drawRoof(g, r, col, &rng)
                    if b.kind == .bank {
                        for q in 0..<8 {
                            let cx = r.minX + 20 + CGFloat(q) * (r.width - 40) / 7
                            ell(g, CGRect(x: cx - 4, y: r.minY + 4, width: 8, height: 8), rgb(0.92, 0.88, 0.74))
                        }
                        box(g, CGRect(x: r.minX + 8, y: r.minY + 14, width: r.width - 16, height: 3), rgb(1.0, 0.82, 0.3))
                        glowFill(g, CGPoint(x: r.midX, y: r.minY - 6), 90, rgb(1.0, 0.8, 0.3), 0.5)
                    } else if b.kind == .jewelry {
                        let c = CGPoint(x: r.midX, y: r.minY + 10)
                        g.setFillColor(rgb(1.0, 0.4, 0.85).cgColor)
                        g.move(to: CGPoint(x: c.x, y: c.y + 9))
                        g.addLine(to: CGPoint(x: c.x + 12, y: c.y))
                        g.addLine(to: CGPoint(x: c.x, y: c.y - 9))
                        g.addLine(to: CGPoint(x: c.x - 12, y: c.y))
                        g.fillPath()
                        glowFill(g, CGPoint(x: c.x, y: c.y - 14), 100, rgb(1.0, 0.35, 0.8), 0.6)
                    } else if b.kind == .gang {
                        glowFill(g, CGPoint(x: r.midX, y: r.minY - 8), 80, rgb(1.0, 0.15, 0.1), 0.45)
                        box(g, CGRect(x: r.midX - 18, y: r.minY + 2, width: 36, height: 3), rgb(1.0, 0.2, 0.15))
                    } else if b.kind == .safehouse {
                        glowFill(g, CGPoint(x: r.midX, y: r.minY - 6), 70, rgb(0.35, 1.0, 0.55), 0.4)
                        box(g, CGRect(x: r.midX - 14, y: r.minY + 2, width: 28, height: 3), rgb(0.35, 1.0, 0.55))
                    } else if rng.f() < 0.65 {
                        let nc = neonColors[rng.i(neonColors.count)]
                        if rng.f() < 0.6 {
                            let px = rng.range(r.minX + 22, max(r.minX + 23, r.maxX - 22))
                            box(g, CGRect(x: px - 20, y: r.minY + 1, width: 40, height: 3), nc)
                            glowFill(g, CGPoint(x: px, y: r.minY - 6), 60, nc, 0.55)
                            streakFill(g, CGRect(x: px - 12, y: r.minY - 100, width: 24, height: 90), CGPoint(x: px, y: r.minY - 14), CGPoint(x: px, y: r.minY - 100), nc, 0.30)
                        } else {
                            let py = rng.range(r.minY + 22, max(r.minY + 23, r.maxY - 22))
                            box(g, CGRect(x: r.minX + 1, y: py - 20, width: 3, height: 40), nc)
                            glowFill(g, CGPoint(x: r.minX - 6, y: py), 60, nc, 0.55)
                            streakFill(g, CGRect(x: r.minX - 100, y: py - 12, width: 90, height: 24), CGPoint(x: r.minX - 14, y: py), CGPoint(x: r.minX - 100, y: py), nc, 0.30)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Sprite textures

func glowTex() -> SKTexture {
    if let t = texCache["glow"] { return t }
    let t = renderTex(CGSize(width: 64, height: 64), 2) { g in
        let cs = CGColorSpaceCreateDeviceRGB()
        let cols = [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0.35).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
        if let gr = CGGradient(colorsSpace: cs, colors: cols, locations: [0, 0.35, 1]) {
            g.drawRadialGradient(gr, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        }
    }
    texCache["glow"] = t
    return t
}

func glowNode(_ size: CGFloat, _ color: UIColor, _ alpha: CGFloat) -> SKSpriteNode {
    let s = SKSpriteNode(texture: glowTex(), size: CGSize(width: size, height: size))
    s.color = color
    s.colorBlendFactor = 1
    s.blendMode = .add
    s.alpha = alpha
    return s
}

func shadowTexture() -> SKTexture {
    if let t = texCache["shadow"] { return t }
    let t = renderTex(CGSize(width: 64, height: 32), 2) { g in
        rrect(g, CGRect(x: 1, y: 1, width: 62, height: 30), 12, rgb(0, 0, 0, 1))
    }
    texCache["shadow"] = t
    return t
}

func ringTexture() -> SKTexture {
    if let t = texCache["ring"] { return t }
    let t = renderTex(CGSize(width: 64, height: 64), 2) { g in
        g.setStrokeColor(UIColor.white.cgColor)
        g.setLineWidth(4)
        g.strokeEllipse(in: CGRect(x: 4, y: 4, width: 56, height: 56))
        g.setStrokeColor(rgb(1, 1, 1, 0.35).cgColor)
        g.setLineWidth(10)
        g.strokeEllipse(in: CGRect(x: 8, y: 8, width: 48, height: 48))
    }
    texCache["ring"] = t
    return t
}

enum CarKind { case sports, muscle, police, van, truck, bike, swat, tank }
enum CarMode { case traffic, chase, direct, parked, wreck, player }

struct CarSpec {
    let len: CGFloat
    let wid: CGFloat
    let accel: CGFloat
    let maxV: CGFloat
    let steer: CGFloat
    let grip: CGFloat
    let hp: CGFloat
    let mass: CGFloat
}

func carSpec(_ k: CarKind) -> CarSpec {
    switch k {
    case .sports: return CarSpec(len: 46, wid: 22, accel: 330, maxV: 470, steer: 2.9, grip: 9, hp: 100, mass: 1.0)
    case .muscle: return CarSpec(len: 50, wid: 23, accel: 310, maxV: 440, steer: 2.6, grip: 8, hp: 130, mass: 1.2)
    case .police: return CarSpec(len: 48, wid: 23, accel: 320, maxV: 450, steer: 2.8, grip: 9, hp: 130, mass: 1.1)
    case .van: return CarSpec(len: 58, wid: 27, accel: 230, maxV: 330, steer: 2.1, grip: 7, hp: 150, mass: 1.6)
    case .truck: return CarSpec(len: 84, wid: 30, accel: 190, maxV: 290, steer: 1.7, grip: 6, hp: 260, mass: 3.0)
    case .bike: return CarSpec(len: 28, wid: 10, accel: 380, maxV: 520, steer: 3.4, grip: 10, hp: 50, mass: 0.4)
    case .swat: return CarSpec(len: 62, wid: 28, accel: 260, maxV: 350, steer: 2.0, grip: 7.5, hp: 320, mass: 2.2)
    case .tank: return CarSpec(len: 74, wid: 44, accel: 150, maxV: 150, steer: 1.2, grip: 12, hp: 600, mass: 6.0)
    }
}

let carPalette: [UIColor] = [
    rgb(0.80, 0.12, 0.14), rgb(0.12, 0.30, 0.75), rgb(0.95, 0.78, 0.15), rgb(0.88, 0.88, 0.90),
    rgb(0.10, 0.10, 0.12), rgb(0.12, 0.55, 0.30), rgb(0.95, 0.45, 0.10), rgb(0.55, 0.58, 0.62)
]

func carTexture(_ k: CarKind, _ ci: Int) -> SKTexture {
    let key = "car\(k)\(ci % carPalette.count)"
    if let t = texCache[key] { return t }
    let sp = carSpec(k)
    let L = sp.len
    let Wd = sp.wid
    let col: UIColor
    switch k {
    case .police: col = rgb(0.92, 0.93, 0.95)
    case .swat: col = rgb(0.10, 0.11, 0.13)
    case .tank: col = rgb(0.30, 0.36, 0.22)
    default: col = carPalette[ci % carPalette.count]
    }
    let t = renderTex(CGSize(width: L, height: Wd), 3) { g in
        if k == .bike {
            box(g, CGRect(x: 1, y: Wd / 2 - 1, width: L - 2, height: 2), rgb(0.1, 0.1, 0.1))
            rrect(g, CGRect(x: 6, y: Wd / 2 - 2.5, width: 14, height: 5), 2.5, col)
            ell(g, CGRect(x: 10, y: Wd / 2 - 4.5, width: 8, height: 9), rgb(0.15, 0.15, 0.2))
            ell(g, CGRect(x: 12, y: Wd / 2 - 2.5, width: 5, height: 5), rgb(0.85, 0.65, 0.5))
            box(g, CGRect(x: 19, y: 0.5, width: 1.5, height: Wd - 1), rgb(0.7, 0.7, 0.7))
            ell(g, CGRect(x: L - 4, y: Wd / 2 - 1.5, width: 3, height: 3), rgb(1, 0.95, 0.7))
            return
        }
        if k == .tank {
            rrect(g, CGRect(x: 0, y: 0, width: L, height: 11), 3, rgb(0.12, 0.13, 0.10))
            rrect(g, CGRect(x: 0, y: Wd - 11, width: L, height: 11), 3, rgb(0.12, 0.13, 0.10))
            for i in 0..<10 {
                box(g, CGRect(x: 3 + CGFloat(i) * 7, y: 1, width: 2, height: 9), rgb(0.25, 0.26, 0.2))
                box(g, CGRect(x: 3 + CGFloat(i) * 7, y: Wd - 10, width: 2, height: 9), rgb(0.25, 0.26, 0.2))
            }
            vGradient(g, CGRect(x: 4, y: 7, width: L - 8, height: Wd - 14), col.shade(1.15), col.shade(0.8), 5)
            return
        }
        if k == .truck {
            rrect(g, CGRect(x: 0.5, y: 1, width: L * 0.68, height: Wd - 2), 3, rgb(0.78, 0.80, 0.82))
            for i in 0..<8 {
                box(g, CGRect(x: 4 + CGFloat(i) * 6.5, y: 1.5, width: 1, height: Wd - 3), rgb(0.6, 0.62, 0.65))
            }
            vGradient(g, CGRect(x: L * 0.70, y: 1.5, width: L * 0.30 - 1, height: Wd - 3), col.shade(1.2), col.shade(0.8), 4)
            rrect(g, CGRect(x: L * 0.84, y: 4, width: L * 0.12, height: Wd - 8), 2, rgb(0.08, 0.12, 0.18))
        } else {
            vGradient(g, CGRect(x: 0.5, y: 0.5, width: L - 1, height: Wd - 1), col.shade(1.25), col.shade(0.78), Wd * 0.32)
            let cx0: CGFloat = (k == .van) ? L * 0.12 : L * 0.28
            let cw: CGFloat = (k == .van) ? L * 0.62 : L * 0.42
            rrect(g, CGRect(x: cx0, y: Wd * 0.15, width: cw, height: Wd * 0.70), Wd * 0.18, rgb(0.07, 0.10, 0.16))
            rrect(g, CGRect(x: cx0 + cw * 0.18, y: Wd * 0.2, width: cw * 0.58, height: Wd * 0.6), Wd * 0.14, col.shade(1.05))
            box(g, CGRect(x: cx0 + cw - 3, y: Wd * 0.2, width: 1.5, height: Wd * 0.6), rgb(0.6, 0.75, 0.9, 0.5))
        }
        if k == .police {
            box(g, CGRect(x: L * 0.72, y: 1, width: L * 0.26, height: Wd - 2), rgb(0.08, 0.09, 0.12))
            box(g, CGRect(x: L * 0.45, y: Wd * 0.2, width: 3, height: Wd * 0.3), rgb(0.1, 0.3, 1.0))
            box(g, CGRect(x: L * 0.45, y: Wd * 0.5, width: 3, height: Wd * 0.3), rgb(1.0, 0.1, 0.1))
        }
        if k == .swat {
            box(g, CGRect(x: L * 0.3, y: 3, width: 3, height: Wd - 6), rgb(1, 0.8, 0))
        }
        if k == .sports {
            box(g, CGRect(x: L * 0.1, y: Wd / 2 - 1.5, width: L * 0.8, height: 3), rgb(1, 1, 1, 0.5))
        }
        ell(g, CGRect(x: L - 5, y: 2, width: 4, height: 3.5), rgb(1, 0.97, 0.8))
        ell(g, CGRect(x: L - 5, y: Wd - 5.5, width: 4, height: 3.5), rgb(1, 0.97, 0.8))
        box(g, CGRect(x: 0.5, y: 2, width: 2, height: 3.5), rgb(0.9, 0.1, 0.1))
        box(g, CGRect(x: 0.5, y: Wd - 5.5, width: 2, height: 3.5), rgb(0.9, 0.1, 0.1))
    }
    texCache[key] = t
    return t
}

func turretTexture() -> SKTexture {
    if let t = texCache["turret"] { return t }
    let t = renderTex(CGSize(width: 56, height: 16), 3) { g in
        rrect(g, CGRect(x: 14, y: 6, width: 42, height: 4), 1.5, rgb(0.12, 0.13, 0.1))
        ell(g, CGRect(x: 2, y: 0, width: 24, height: 16), rgb(0.36, 0.43, 0.27))
        ell(g, CGRect(x: 8, y: 4, width: 10, height: 8), rgb(0.25, 0.30, 0.19))
    }
    texCache["turret"] = t
    return t
}

func personTexture(_ key: String, _ shirt: UIColor, _ hat: UIColor, _ armed: Bool, _ skin: UIColor) -> SKTexture {
    if let t = texCache[key] { return t }
    let t = renderTex(CGSize(width: 24, height: 16), 3) { g in
        if armed { rrect(g, CGRect(x: 12, y: 7, width: 11, height: 2.6), 1, rgb(0.08, 0.08, 0.09)) }
        ell(g, CGRect(x: 7, y: 1.2, width: 9, height: 4), shirt.shade(0.75))
        ell(g, CGRect(x: 7, y: 10.8, width: 9, height: 4), shirt.shade(0.75))
        ell(g, CGRect(x: 4, y: 2, width: 9, height: 12), shirt)
        ell(g, CGRect(x: 5.2, y: 4.6, width: 7, height: 7), skin)
        ell(g, CGRect(x: 4.6, y: 4.2, width: 6.2, height: 7.6), hat)
    }
    texCache[key] = t
    return t
}

func heliTexture() -> SKTexture {
    if let t = texCache["heli"] { return t }
    let t = renderTex(CGSize(width: 70, height: 26), 3) { g in
        box(g, CGRect(x: 0, y: 11.5, width: 30, height: 3), rgb(0.12, 0.13, 0.15))
        box(g, CGRect(x: 0, y: 5, width: 5, height: 14), rgb(0.12, 0.13, 0.15))
        vGradient(g, CGRect(x: 24, y: 3, width: 44, height: 20), rgb(0.30, 0.32, 0.38), rgb(0.10, 0.11, 0.14), 9)
        ell(g, CGRect(x: 48, y: 6, width: 16, height: 14), rgb(0.35, 0.55, 0.75))
        ell(g, CGRect(x: 1, y: 11, width: 3, height: 3), rgb(1, 0.1, 0.1))
    }
    texCache["heli"] = t
    return t
}

func droneTexture() -> SKTexture {
    if let t = texCache["drone"] { return t }
    let t = renderTex(CGSize(width: 24, height: 24), 3) { g in
        g.setStrokeColor(rgb(0.15, 0.16, 0.2).cgColor)
        g.setLineWidth(2)
        g.move(to: CGPoint(x: 3, y: 3)); g.addLine(to: CGPoint(x: 21, y: 21))
        g.move(to: CGPoint(x: 21, y: 3)); g.addLine(to: CGPoint(x: 3, y: 21))
        g.strokePath()
        for p in [CGPoint(x: 4, y: 4), CGPoint(x: 20, y: 4), CGPoint(x: 4, y: 20), CGPoint(x: 20, y: 20)] {
            ell(g, CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8), rgb(0.5, 0.52, 0.58, 0.8))
        }
        ell(g, CGRect(x: 8, y: 8, width: 8, height: 8), rgb(0.12, 0.12, 0.15))
        ell(g, CGRect(x: 10.5, y: 10.5, width: 3, height: 3), rgb(1, 0.1, 0.1))
    }
    texCache["drone"] = t
    return t
}

func wlabel(_ text: String, _ fs: CGFloat, _ color: UIColor) -> SKLabelNode {
    let l = SKLabelNode(fontNamed: "AvenirNext-Bold")
    l.text = text
    l.fontSize = fs
    l.fontColor = color
    return l
}

// MARK: - Entities

final class Car {
    let node = SKNode()
    let body: SKSpriteNode
    let shadow: SKSpriteNode
    var kind: CarKind
    var ci: Int
    let spec: CarSpec
    var heading: CGFloat
    var vel = CGVector.zero
    var hp: CGFloat
    var mode: CarMode
    var dir = 0
    var road = 0
    var lastNode = -1
    var speed: CGFloat = 0
    var cruise: CGFloat = 150
    var radius: CGFloat
    var light: SKSpriteNode?
    var siren: SKSpriteNode?
    var turret: SKSpriteNode?
    var fireT: CGFloat = 2
    var skidT: CGFloat = 0
    var stuckT: CGFloat = 0
    var reverseT: CGFloat = 0
    var deployed = false
    var burnT: CGFloat = -1
    var wreckT: CGFloat = 0
    var sirenT: CGFloat = 0
    var slip: CGFloat = 0
    var pos: CGPoint {
        get { return node.position }
        set { node.position = newValue }
    }
    var isCop: Bool { return kind == .police || kind == .swat || kind == .tank }
    var mass: CGFloat { return spec.mass }

    init(_ kind: CarKind, _ ci: Int, _ p: CGPoint, _ h: CGFloat, _ mode: CarMode) {
        let sp = carSpec(kind)
        let bd = SKSpriteNode(texture: carTexture(kind, ci), size: CGSize(width: sp.len, height: sp.wid))
        let sh = SKSpriteNode(texture: shadowTexture(), size: CGSize(width: sp.len + 4, height: sp.wid + 4))
        sh.alpha = 0.4
        sh.zPosition = -1
        self.kind = kind
        self.ci = ci
        self.spec = sp
        self.heading = h
        self.hp = sp.hp
        self.mode = mode
        self.radius = max(sp.wid * 0.62, sp.len * 0.3)
        self.body = bd
        self.shadow = sh
        node.position = p
        node.zRotation = h
        node.addChild(sh)
        node.addChild(bd)
        let hl = glowNode(1, rgb(1.0, 0.92, 0.7), 0.30)
        hl.size = CGSize(width: 140, height: 90)
        hl.position = CGPoint(x: sp.len * 0.95, y: 0)
        hl.zPosition = 1
        node.addChild(hl)
        light = hl
        if kind == .police || kind == .swat {
            let s = glowNode(70, rgb(1, 0.1, 0.1), 0)
            s.zPosition = 3
            node.addChild(s)
            siren = s
        }
        if kind == .tank {
            let t = SKSpriteNode(texture: turretTexture(), size: CGSize(width: 56, height: 16))
            t.anchorPoint = CGPoint(x: 0.25, y: 0.5)
            t.zPosition = 2
            node.addChild(t)
            turret = t
        }
    }
}

enum UKind { case ped, cop, swat, gang, crew, heli, drone }

final class Unit {
    let node = SKNode()
    let sprite: SKSpriteNode
    var kind: UKind
    var hp: CGFloat
    var radius: CGFloat = 8
    var heading: CGFloat = 0
    var dirT: CGFloat = 0
    var walking = false
    var fleeT: CGFloat = 0
    var fireT: CGFloat = 1
    var angle: CGFloat = 0
    var speed: CGFloat = 60
    var animT: CGFloat = 0
    var leaving = false
    var leaveT: CGFloat = 0
    var gone = false
    var dead = false
    var tag = 0
    var home = CGPoint.zero
    var strafe: CGFloat = 1
    var rotor: SKNode?
    var pos: CGPoint {
        get { return node.position }
        set { node.position = newValue }
    }
    var air: Bool { return kind == .heli || kind == .drone }
    var hostile: Bool { return kind == .cop || kind == .swat || kind == .gang || kind == .heli || kind == .drone }

    init(_ kind: UKind, _ tex: SKTexture, _ size: CGSize, _ hp: CGFloat) {
        let sp = SKSpriteNode(texture: tex, size: size)
        let sh = SKSpriteNode(texture: shadowTexture(), size: CGSize(width: size.width * 0.7, height: size.height * 0.8))
        sh.alpha = 0.3
        sh.position = CGPoint(x: 2, y: -3)
        sh.zPosition = -1
        self.kind = kind
        self.hp = hp
        self.sprite = sp
        node.addChild(sh)
        node.addChild(sp)
    }
}

final class Bullet {
    let node: SKNode
    var pos: CGPoint
    var vel: CGVector
    var dmg: CGFloat
    var life: CGFloat
    var pierce: Int
    var wall: CGFloat
    var bounce: Int
    var explosive: Bool
    var team: Int
    var kind: Int
    var crew = false
    var inWall = false
    var trailT: CGFloat = 0
    var hit = Set<ObjectIdentifier>()
    var radius: CGFloat = 3

    init(node: SKNode, pos: CGPoint, vel: CGVector, dmg: CGFloat, life: CGFloat, pierce: Int, wall: CGFloat, bounce: Int, explosive: Bool, team: Int, kind: Int) {
        self.node = node
        self.pos = pos
        self.vel = vel
        self.dmg = dmg
        self.life = life
        self.pierce = pierce
        self.wall = wall
        self.bounce = bounce
        self.explosive = explosive
        self.team = team
        self.kind = kind
    }
}

final class Bomb {
    let node: SKNode
    var pos: CGPoint
    var vel: CGVector
    var t: CGFloat = 1.3
    let fromPlayer: Bool
    init(node: SKNode, pos: CGPoint, vel: CGVector, fromPlayer: Bool) {
        self.node = node
        self.pos = pos
        self.vel = vel
        self.fromPlayer = fromPlayer
    }
}

enum POIKind { case bank, jewelry, safehouse, race, gang }

final class POI {
    let kind: POIKind
    let pos: CGPoint
    var cool: CGFloat = 0
    var owned = false
    var tag = 0
    var ring: SKSpriteNode?
    var dot: SKShapeNode?
    init(_ k: POIKind, _ p: CGPoint) {
        kind = k
        pos = p
    }
}

struct Weapon {
    let name: String
    let short: String
    let rate: CGFloat
    let dmg: CGFloat
    let speed: CGFloat
    let life: CGFloat
    let pellets: Int
    let spread: CGFloat
    let pierce: Int
    let wall: CGFloat
    let bounce: Int
    let explosive: Bool
    let kind: Int
    let price: Int
}

let weapons: [Weapon] = [
    Weapon(name: "Pistol", short: "9MM", rate: 3.2, dmg: 22, speed: 900, life: 0.7, pellets: 1, spread: 0.02, pierce: 0, wall: 0, bounce: 1, explosive: false, kind: 0, price: 0),
    Weapon(name: "Dual UZI", short: "UZI", rate: 14, dmg: 9, speed: 950, life: 0.6, pellets: 1, spread: 0.10, pierce: 0, wall: 0, bounce: 1, explosive: false, kind: 0, price: 0),
    Weapon(name: "Shotgun", short: "SHOT", rate: 1.3, dmg: 14, speed: 800, life: 0.35, pellets: 7, spread: 0.30, pierce: 0, wall: 0, bounce: 0, explosive: false, kind: 0, price: 1500),
    Weapon(name: "Sniper", short: "SNIP", rate: 0.8, dmg: 95, speed: 1800, life: 1.0, pellets: 1, spread: 0, pierce: 4, wall: 90, bounce: 0, explosive: false, kind: 0, price: 3000),
    Weapon(name: "Flamethrower", short: "FIRE", rate: 22, dmg: 4, speed: 330, life: 0.38, pellets: 1, spread: 0.22, pierce: 99, wall: 0, bounce: 0, explosive: false, kind: 1, price: 4000),
    Weapon(name: "RPG", short: "RPG", rate: 0.7, dmg: 140, speed: 420, life: 2.0, pellets: 1, spread: 0.01, pierce: 0, wall: 0, bounce: 0, explosive: true, kind: 2, price: 6000)
]

final class HudButton {
    let node = SKNode()
    let circle: SKShapeNode
    let label: SKLabelNode
    let r: CGFloat

    init(_ text: String, _ r: CGFloat, _ color: UIColor) {
        let c = SKShapeNode(circleOfRadius: r)
        c.fillColor = color.withAlphaComponent(0.35)
        c.strokeColor = rgb(1, 1, 1, 0.75)
        c.lineWidth = 2
        let l = SKLabelNode(fontNamed: "AvenirNext-Bold")
        l.text = text
        l.fontSize = r * 0.42
        l.fontColor = UIColor.white
        l.verticalAlignmentMode = .center
        self.r = r
        self.circle = c
        self.label = l
        node.addChild(c)
        node.addChild(l)
    }

    func hit(_ p: CGPoint) -> Bool {
        return dist(p, node.position) <= r + 10
    }

    var visible: Bool {
        get { return !node.isHidden }
        set { node.isHidden = !newValue }
    }
}

// MARK: - The game scene

final class WorldScene: SKScene {
    static func make() -> WorldScene {
        let s = WorldScene(size: CGSize(width: 852, height: 393))
        s.scaleMode = .resizeFill
        return s
    }

    // layers
    let ground = SKNode(), decals = SKNode(), poiLayer = SKNode(), sewerLayer = SKNode()
    let unitLayer = SKNode(), carLayer = SKNode(), meLayer = SKNode(), airLayer = SKNode(), fxLayer = SKNode()
    let cam = SKCameraNode()
    let hud = SKNode()

    // state
    var didSetup = false
    var chunksLoaded = 0
    var lastT: TimeInterval = 0
    var clock: CGFloat = 0
    var blocks: [Block] = []
    var manholes: [CGPoint] = []
    var pois: [POI] = []
    var cars: [Car] = []
    var units: [Unit] = []
    var bullets: [Bullet] = []
    var bombs: [Bomb] = []
    var me: Unit!
    var inCar: Car?
    var cash = 500
    var stars = 0
    var seen = false
    var seenT: CGFloat = 0
    var loseT: CGFloat = 0
    var crimeCD: CGFloat = 0
    var stunT: CGFloat = 0
    var dead = false
    var deadT: CGFloat = 0
    var underground = false
    var weaponIdx = 0
    var unlocked = 3
    var fireCD: CGFloat = 0
    var bombCD: CGFloat = 0
    var ownsHouse = false
    var garage: (CarKind, Int)?
    var incomeT: CGFloat = 0
    var spawnT: CGFloat = 0
    var roadblockT: CGFloat = 6
    var mgrT: CGFloat = 0
    var robbing: POI?
    var robT: CGFloat = 0
    var raceOn = false
    var raceIdx = 0
    var raceT: CGFloat = 0
    var raceRing: SKSpriteNode?
    var shake: CGFloat = 0
    var aimAngle: CGFloat = 0
    var saveT: CGFloat = 0
    var heliSpot: SKSpriteNode?

    // input
    var moveTouch: UITouch?
    var aimTouch: UITouch?
    var moveCenter = CGPoint.zero
    var aimCenter = CGPoint.zero
    var mv = CGVector.zero
    var aim = CGVector.zero
    var brakeHeld = false
    var brakeTouch: UITouch?
    var actLabel: String?
    var actHandler: (() -> Void)?

    // hud
    var hpFill: SKSpriteNode!
    var cashLabel: SKLabelNode!
    var starsLabel: SKLabelNode!
    var toastLabel: SKLabelNode!
    var infoLabel: SKLabelNode!
    var wastedLabel: SKLabelNode!
    var weaponLabel: SKLabelNode!
    var loadingLabel: SKLabelNode!
    var actBtn: HudButton!
    var brakeBtn: HudButton!
    var weaponBtn: HudButton!
    var bombBtn: HudButton!
    var paintBtn: HudButton!
    var stickRingL: SKShapeNode!
    var stickKnobL: SKShapeNode!
    var stickRingR: SKShapeNode!
    var stickKnobR: SKShapeNode!
    var hurtFlash: SKSpriteNode!
    var vignette: SKSpriteNode!
    var underOverlay: SKSpriteNode!
    var aimLine: SKSpriteNode!
    var hpBack: SKSpriteNode!
    var mapCrop: SKCropNode!
    var mapContent: SKSpriteNode!
    var mapFrame: SKShapeNode!
    var mapArrow: SKShapeNode!
    var copDots: [SKShapeNode] = []
    var rain: SKEmitterNode?
    let mapScale: CGFloat = 0.11

    // MARK: lifecycle

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        if !didSetup {
            didSetup = true
            setupWorld()
        }
        layoutHUD()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        if didSetup { layoutHUD() }
    }

    func setupWorld() {
        backgroundColor = rgb(0.03, 0.04, 0.07)
        blocks = buildBlocks()
        manholes = buildManholes()
        buildPOIs()
        let layers: [SKNode] = [ground, decals, poiLayer, sewerLayer, unitLayer, carLayer, meLayer, airLayer, fxLayer]
        let zs: [CGFloat] = [-10, -5, -4, -9, 5, 10, 12, 40, 50]
        for (i, l) in layers.enumerated() {
            l.zPosition = zs[i]
            addChild(l)
        }
        addChild(cam)
        camera = cam
        cam.addChild(hud)
        buildChunks()
        buildSewer()
        buildPOINodes()
        buildHUD()
        buildRain()

        me = Unit(.crew, personTexture("me", rgb(1.0, 0.5, 0.1), rgb(0.12, 0.09, 0.07), true, rgb(0.82, 0.62, 0.46)), CGSize(width: 24, height: 16), 100)
        me.pos = CGPoint(x: W.c(1) + 30, y: W.c(1) + 10)
        meLayer.addChild(me.node)
        cam.position = me.pos

        loadSave()
        if ownsHouse, let h = pois.first(where: { $0.kind == .safehouse }) {
            me.pos = CGPoint(x: h.pos.x + 30, y: h.pos.y - 20)
            cam.position = me.pos
        }

        // parked car for you
        addCar(.sports, 0, CGPoint(x: W.c(1) + 100, y: W.c(1) - 18), 0, .parked)
        for _ in 0..<16 { spawnTrafficCar(minD: 150, maxD: 1500) }
        for _ in 0..<26 { spawnPed(minD: 100, maxD: 800) }
        for p in pois where p.kind == .gang && !p.owned { spawnGangMembers(p) }
        showToast("Welcome to the city. Right stick = aim & shoot, left = move")
    }

    // MARK: map building

    func buildPOIs() {
        func blk(_ i: Int, _ j: Int) -> Block { return blocks[i * W.n + j] }
        let bank = blk(3, 3).area
        pois.append(POI(.bank, CGPoint(x: bank.midX, y: bank.minY + 36)))
        let jw = blk(5, 2).area
        pois.append(POI(.jewelry, CGPoint(x: jw.midX, y: jw.minY + 44)))
        let sh = blk(2, 6).area
        pois.append(POI(.safehouse, CGPoint(x: sh.minX + 18 + 85, y: sh.maxY - 18 - 110 - 16)))
        let gangs: [(Int, Int)] = [(1, 5), (6, 6), (6, 1)]
        for (n, g) in gangs.enumerated() {
            let a = blk(g.0, g.1).area
            let p = POI(.gang, CGPoint(x: a.minX + 18 + 150, y: a.minY + 18 + 150))
            p.tag = n
            pois.append(p)
        }
        pois.append(POI(.race, CGPoint(x: W.c(4), y: W.c(4))))
    }

    func buildChunks() {
        let per = Int(W.size / W.chunk)
        let blocksCopy = blocks
        let mh = manholes
        loadingLabel = wlabel("Building city...", 22, UIColor.white)
        loadingLabel.zPosition = 2000
        hud.addChild(loadingLabel)
        for a in 0..<per {
            for b in 0..<per {
                DispatchQueue.global(qos: .userInitiated).async {
                    let img = renderChunk(a, b, blocksCopy, mh)
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        let tex = SKTexture(image: img)
                        tex.filteringMode = .linear
                        let s = SKSpriteNode(texture: tex, size: CGSize(width: W.chunk, height: W.chunk))
                        s.anchorPoint = CGPoint.zero
                        s.position = CGPoint(x: CGFloat(a) * W.chunk, y: CGFloat(b) * W.chunk)
                        self.ground.addChild(s)
                        self.chunksLoaded += 1
                        if self.chunksLoaded >= per * per { self.loadingLabel.removeFromParent() }
                    }
                }
            }
        }
    }

    func buildSewer() {
        let p = CGMutablePath()
        for k in 0..<W.n {
            let c = W.c(k)
            p.move(to: CGPoint(x: 0, y: c))
            p.addLine(to: CGPoint(x: W.size, y: c))
            p.move(to: CGPoint(x: c, y: 0))
            p.addLine(to: CGPoint(x: c, y: W.size))
        }
        let wall = SKShapeNode(path: p)
        wall.strokeColor = rgb(0.10, 0.17, 0.15)
        wall.lineWidth = 40
        sewerLayer.addChild(wall)
        let water = SKShapeNode(path: p)
        water.strokeColor = rgb(0.10, 0.30, 0.28)
        water.lineWidth = 16
        sewerLayer.addChild(water)
        let shine = SKShapeNode(path: p)
        shine.strokeColor = rgb(0.5, 1.0, 0.8, 0.25)
        shine.lineWidth = 2
        sewerLayer.addChild(shine)
        for m in manholes {
            let g = glowNode(70, rgb(1.0, 0.85, 0.4), 0.55)
            g.position = m
            sewerLayer.addChild(g)
        }
        sewerLayer.isHidden = true
    }

    func buildPOINodes() {
        for p in pois {
            let col: UIColor
            let name: String
            switch p.kind {
            case .bank: col = rgb(1.0, 0.85, 0.3); name = "BANK"
            case .jewelry: col = rgb(1.0, 0.4, 0.85); name = "JEWELRY"
            case .safehouse: col = rgb(0.35, 1.0, 0.55); name = "SAFEHOUSE"
            case .race: col = rgb(0.3, 0.8, 1.0); name = "DRAG RACE"
            case .gang: col = rgb(1.0, 0.2, 0.15); name = "GANG HQ"
            }
            let r = SKSpriteNode(texture: ringTexture(), size: CGSize(width: 76, height: 76))
            r.color = col
            r.colorBlendFactor = 1
            r.blendMode = .add
            r.position = p.pos
            r.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.scale(to: 1.15, duration: 0.8),
                SKAction.scale(to: 0.9, duration: 0.8)
            ])))
            poiLayer.addChild(r)
            p.ring = r
            let l = wlabel(name, 11, col)
            l.position = CGPoint(x: p.pos.x, y: p.pos.y + 44)
            poiLayer.addChild(l)
        }
    }

    // MARK: HUD

    func buildHUD() {
        hud.zPosition = 1000
        hpBack = SKSpriteNode(color: rgb(0, 0, 0, 0.55), size: CGSize(width: 134, height: 14))
        hpBack.anchorPoint = CGPoint(x: 0, y: 0.5)
        hud.addChild(hpBack)
        hpFill = SKSpriteNode(color: rgb(0.2, 0.85, 0.35), size: CGSize(width: 130, height: 10))
        hpFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        hpFill.position = CGPoint(x: 2, y: 0)
        hpBack.addChild(hpFill)

        cashLabel = wlabel("$0", 20, rgb(0.5, 1.0, 0.5))
        cashLabel.horizontalAlignmentMode = .left
        hud.addChild(cashLabel)
        starsLabel = wlabel("☆☆☆☆☆", 24, UIColor.white)
        hud.addChild(starsLabel)
        toastLabel = wlabel("", 16, UIColor.white)
        toastLabel.alpha = 0
        hud.addChild(toastLabel)
        infoLabel = wlabel("", 15, rgb(1, 0.9, 0.4))
        hud.addChild(infoLabel)
        wastedLabel = wlabel("WASTED", 64, rgb(0.9, 0.1, 0.1))
        wastedLabel.isHidden = true
        wastedLabel.zPosition = 500
        hud.addChild(wastedLabel)
        weaponLabel = wlabel("", 12, UIColor.white)
        hud.addChild(weaponLabel)

        stickRingL = SKShapeNode(circleOfRadius: 52)
        stickRingL.strokeColor = rgb(1, 1, 1, 0.3)
        stickRingL.fillColor = rgb(1, 1, 1, 0.06)
        stickRingL.lineWidth = 2
        stickKnobL = SKShapeNode(circleOfRadius: 22)
        stickKnobL.fillColor = rgb(1, 1, 1, 0.35)
        stickKnobL.strokeColor = rgb(1, 1, 1, 0.6)
        stickRingL.addChild(stickKnobL)
        hud.addChild(stickRingL)
        stickRingR = SKShapeNode(circleOfRadius: 52)
        stickRingR.strokeColor = rgb(1, 0.5, 0.4, 0.35)
        stickRingR.fillColor = rgb(1, 0.4, 0.3, 0.06)
        stickRingR.lineWidth = 2
        stickKnobR = SKShapeNode(circleOfRadius: 22)
        stickKnobR.fillColor = rgb(1, 0.5, 0.4, 0.4)
        stickKnobR.strokeColor = rgb(1, 0.6, 0.5, 0.7)
        stickRingR.addChild(stickKnobR)
        hud.addChild(stickRingR)

        actBtn = HudButton("JACK", 38, rgb(1.0, 0.7, 0.1))
        brakeBtn = HudButton("BRAKE", 32, rgb(0.9, 0.2, 0.2))
        weaponBtn = HudButton("9MM", 28, rgb(0.3, 0.5, 1.0))
        bombBtn = HudButton("💣", 28, rgb(0.8, 0.3, 0.1))
        paintBtn = HudButton("PAINT", 28, rgb(0.6, 0.3, 0.9))
        for b in [actBtn!, brakeBtn!, weaponBtn!, bombBtn!, paintBtn!] { hud.addChild(b.node) }

        aimLine = SKSpriteNode(color: rgb(1, 0.3, 0.2, 0.45), size: CGSize(width: 140, height: 1.5))
        aimLine.anchorPoint = CGPoint(x: 0, y: 0.5)
        aimLine.isHidden = true
        aimLine.zPosition = 60
        addChild(aimLine)

        // minimap
        let m = mapScale
        let px: CGFloat = 384
        let tex = renderTex(CGSize(width: px, height: px), 1) { g in
            box(g, CGRect(x: 0, y: 0, width: px, height: px), rgb(0.30, 0.32, 0.36))
            for b in self.blocks {
                var col = rgb(0.12, 0.13, 0.17)
                switch b.kind {
                case .park: col = rgb(0.10, 0.28, 0.14)
                case .bank: col = rgb(0.5, 0.42, 0.15)
                case .jewelry: col = rgb(0.45, 0.2, 0.4)
                case .gang: col = rgb(0.4, 0.12, 0.1)
                case .safehouse: col = rgb(0.15, 0.4, 0.22)
                case .buildings: break
                }
                let a = b.area
                box(g, CGRect(x: a.minX * 0.125, y: px - a.maxY * 0.125, width: a.width * 0.125, height: a.height * 0.125), col)
            }
        }
        _ = m
        mapContent = SKSpriteNode(texture: tex, size: CGSize(width: W.size * mapScale, height: W.size * mapScale))
        mapContent.anchorPoint = CGPoint.zero
        mapCrop = SKCropNode()
        let mask = SKShapeNode(circleOfRadius: 54)
        mask.fillColor = UIColor.white
        mask.strokeColor = UIColor.clear
        mapCrop.maskNode = mask
        mapCrop.addChild(mapContent)
        hud.addChild(mapCrop)
        mapFrame = SKShapeNode(circleOfRadius: 54)
        mapFrame.strokeColor = rgb(1, 1, 1, 0.7)
        mapFrame.lineWidth = 2
        mapFrame.fillColor = UIColor.clear
        hud.addChild(mapFrame)
        mapArrow = SKShapeNode(path: {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 6, y: 0))
            p.addLine(to: CGPoint(x: -4, y: 4))
            p.addLine(to: CGPoint(x: -4, y: -4))
            p.closeSubpath()
            return p
        }())
        mapArrow.fillColor = UIColor.white
        mapArrow.strokeColor = UIColor.clear
        hud.addChild(mapArrow)
        for p in pois {
            let d = SKShapeNode(circleOfRadius: 3)
            switch p.kind {
            case .bank: d.fillColor = rgb(1.0, 0.85, 0.3)
            case .jewelry: d.fillColor = rgb(1.0, 0.4, 0.85)
            case .safehouse: d.fillColor = rgb(0.35, 1.0, 0.55)
            case .race: d.fillColor = rgb(0.3, 0.8, 1.0)
            case .gang: d.fillColor = rgb(1.0, 0.2, 0.15)
            }
            d.strokeColor = UIColor.clear
            d.position = CGPoint(x: p.pos.x * mapScale, y: p.pos.y * mapScale)
            mapContent.addChild(d)
            p.dot = d
        }
        for _ in 0..<14 {
            let d = SKShapeNode(circleOfRadius: 2.5)
            d.fillColor = rgb(0.3, 0.5, 1.0)
            d.strokeColor = UIColor.white
            d.lineWidth = 0.5
            d.isHidden = true
            mapContent.addChild(d)
            copDots.append(d)
        }

        // overlays
        let vtex = renderTex(CGSize(width: 128, height: 128), 1) { g in
            let cs = CGColorSpaceCreateDeviceRGB()
            let cols = [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.55).cgColor] as CFArray
            if let gr = CGGradient(colorsSpace: cs, colors: cols, locations: [0, 0.5, 1]) {
                g.drawRadialGradient(gr, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 90, options: [.drawsAfterEndLocation])
            }
        }
        vignette = SKSpriteNode(texture: vtex)
        vignette.zPosition = -50
        hud.addChild(vignette)
        hurtFlash = SKSpriteNode(color: rgb(0.9, 0.0, 0.0, 1), size: CGSize(width: 2000, height: 1200))
        hurtFlash.alpha = 0
        hurtFlash.zPosition = -40
        hud.addChild(hurtFlash)
        let utex = renderTex(CGSize(width: 256, height: 256), 1) { g in
            let cs = CGColorSpaceCreateDeviceRGB()
            let cols = [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0).cgColor, UIColor(red: 0, green: 0.03, blue: 0.03, alpha: 0.96).cgColor] as CFArray
            if let gr = CGGradient(colorsSpace: cs, colors: cols, locations: [0, 0.16, 0.5]) {
                g.drawRadialGradient(gr, startCenter: CGPoint(x: 128, y: 128), startRadius: 0, endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [.drawsAfterEndLocation])
            }
        }
        underOverlay = SKSpriteNode(texture: utex, size: CGSize(width: 1800, height: 1800))
        underOverlay.zPosition = -30
        underOverlay.isHidden = true
        hud.addChild(underOverlay)
    }

    func layoutHUD() {
        guard hud.parent != nil, hpBack != nil else { return }
        let w = size.width
        let h = size.height
        hud.position = CGPoint(x: -w / 2, y: -h / 2)
        hpBack.position = CGPoint(x: 70, y: h - 28)
        cashLabel.position = CGPoint(x: 70, y: h - 58)
        starsLabel.position = CGPoint(x: w / 2, y: h - 42)
        toastLabel.position = CGPoint(x: w / 2, y: h - 78)
        infoLabel.position = CGPoint(x: w / 2, y: 28)
        wastedLabel.position = CGPoint(x: w / 2, y: h / 2 - 20)
        loadingLabel?.position = CGPoint(x: w / 2, y: h / 2)
        stickRingL.position = CGPoint(x: 120, y: 85)
        stickRingR.position = CGPoint(x: w - 120, y: 85)
        actBtn.node.position = CGPoint(x: w - 70, y: 200)
        weaponBtn.node.position = CGPoint(x: w - 70, y: 255)
        bombBtn.node.position = CGPoint(x: w - 200, y: 175)
        weaponLabel.position = CGPoint(x: w - 70, y: 222)
        brakeBtn.node.position = CGPoint(x: 80, y: 190)
        paintBtn.node.position = CGPoint(x: 80, y: 255)
        mapCrop.position = CGPoint(x: w - 70, y: h - 70)
        mapFrame.position = mapCrop.position
        mapArrow.position = mapCrop.position
        vignette.size = CGSize(width: w, height: h)
        vignette.position = CGPoint(x: w / 2, y: h / 2)
        underOverlay.position = CGPoint(x: w / 2, y: h / 2)
        hurtFlash.position = CGPoint(x: w / 2, y: h / 2)
        rain?.position = CGPoint(x: w / 2, y: h * 1.1)
        rain?.particlePositionRange = CGVector(dx: w * 1.4, dy: 0)
    }

    func buildRain() {
        let tex = renderTex(CGSize(width: 2, height: 16), 2) { g in
            box(g, CGRect(x: 0, y: 0, width: 2, height: 16), rgb(0.75, 0.85, 1.0, 0.9))
        }
        let e = SKEmitterNode()
        e.particleTexture = tex
        e.particleSize = CGSize(width: 1.5, height: 14)
        e.particleBirthRate = 240
        e.particleLifetime = 0.9
        e.emissionAngle = -CGFloat.pi / 2
        e.particleSpeed = 800
        e.particleSpeedRange = 120
        e.particleAlpha = 0.28
        e.particleAlphaRange = 0.15
        e.zPosition = -20
        hud.addChild(e)
        e.advanceSimulationTime(1.0)
        rain = e
    }

    func showToast(_ s: String) {
        toastLabel.text = s
        toastLabel.removeAllActions()
        toastLabel.alpha = 1
        toastLabel.run(SKAction.sequence([SKAction.wait(forDuration: 2.4), SKAction.fadeOut(withDuration: 0.5)]))
    }

    // MARK: save/load

    func saveGame() {
        let d = UserDefaults.standard
        d.set(cash, forKey: "w_cash")
        d.set(ownsHouse, forKey: "w_house")
        d.set(unlocked, forKey: "w_unlock")
        var mask = 0
        for p in pois where p.kind == .gang && p.owned { mask |= (1 << p.tag) }
        d.set(mask, forKey: "w_terr")
    }

    func loadSave() {
        let d = UserDefaults.standard
        if d.object(forKey: "w_cash") != nil { cash = d.integer(forKey: "w_cash") }
        ownsHouse = d.bool(forKey: "w_house")
        let u = d.integer(forKey: "w_unlock")
        if u > 0 { unlocked = u | 3 }
        let mask = d.integer(forKey: "w_terr")
        for p in pois where p.kind == .gang {
            if mask & (1 << p.tag) != 0 {
                p.owned = true
                p.dot?.fillColor = rgb(0.3, 1.0, 0.4)
                p.ring?.color = rgb(0.3, 1.0, 0.4)
            }
        }
    }

    // MARK: collision world

    func wallRect(_ p: CGPoint) -> CGRect? {
        let ci = Int(p.x / W.cell)
        let cj = Int(p.y / W.cell)
        if p.x < 0 || p.y < 0 || ci >= W.n || cj >= W.n { return nil }
        for r in blocks[ci * W.n + cj].rects where r.contains(p) { return r }
        return nil
    }

    func solidAt(_ p: CGPoint) -> Bool {
        return wallRect(p) != nil
    }

    func los(_ a: CGPoint, _ b: CGPoint) -> Bool {
        let d = dist(a, b)
        let steps = Int(d / 14)
        if steps < 2 { return true }
        for s in 1..<steps {
            let t = CGFloat(s) / CGFloat(steps)
            if solidAt(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)) { return false }
        }
        return true
    }

    func pushOut(_ p: inout CGPoint, _ r: CGFloat) -> CGVector? {
        var nx: CGFloat = 0
        var ny: CGFloat = 0
        var hit = false
        let ci = min(max(Int(p.x / W.cell), 0), W.n - 1)
        let cj = min(max(Int(p.y / W.cell), 0), W.n - 1)
        for i in max(0, ci - 1)...min(W.n - 1, ci + 1) {
            for j in max(0, cj - 1)...min(W.n - 1, cj + 1) {
                for rc in blocks[i * W.n + j].rects {
                    let cx = min(max(p.x, rc.minX), rc.maxX)
                    let cy = min(max(p.y, rc.minY), rc.maxY)
                    var dx = p.x - cx
                    var dy = p.y - cy
                    let d2 = dx * dx + dy * dy
                    if d2 < r * r {
                        hit = true
                        if d2 > 0.0001 {
                            let d = sqrt(d2)
                            dx /= d
                            dy /= d
                            p.x += dx * (r - d)
                            p.y += dy * (r - d)
                        } else {
                            let l = p.x - rc.minX
                            let rr = rc.maxX - p.x
                            let b = p.y - rc.minY
                            let t = rc.maxY - p.y
                            let m = min(min(l, rr), min(b, t))
                            if m == l { dx = -1; dy = 0; p.x = rc.minX - r }
                            else if m == rr { dx = 1; dy = 0; p.x = rc.maxX + r }
                            else if m == b { dx = 0; dy = -1; p.y = rc.minY - r }
                            else { dx = 0; dy = 1; p.y = rc.maxY + r }
                        }
                        nx += dx
                        ny += dy
                    }
                }
            }
        }
        if p.x < r { p.x = r; nx += 1; hit = true }
        if p.y < r { p.y = r; ny += 1; hit = true }
        if p.x > W.size - r { p.x = W.size - r; nx -= 1; hit = true }
        if p.y > W.size - r { p.y = W.size - r; ny -= 1; hit = true }
        if !hit { return nil }
        let m = hypot(nx, ny)
        if m < 0.0001 { return CGVector(dx: 0, dy: 1) }
        return CGVector(dx: nx / m, dy: ny / m)
    }

    func sewerClamp(_ p: inout CGPoint) {
        let kx = Int(((p.x - W.road / 2) / W.cell).rounded())
        let ky = Int(((p.y - W.road / 2) / W.cell).rounded())
        let cx = W.c(min(max(kx, 0), W.n - 1))
        let cy = W.c(min(max(ky, 0), W.n - 1))
        let dx = p.x - cx
        let dy = p.y - cy
        if abs(dx) > 16 && abs(dy) > 16 {
            if abs(dx) < abs(dy) { p.x = cx } else { p.y = cy }
        }
        p.x = clampf(p.x, 10, W.size - 10)
        p.y = clampf(p.y, 10, W.size - 10)
    }

    // MARK: player helpers

    var playerCenter: CGPoint { return inCar?.pos ?? me.pos }
    var playerRadius: CGFloat { return inCar?.radius ?? 8 }
    var targetPoint: CGPoint {
        if let c = inCar {
            return CGPoint(x: c.pos.x + c.vel.dx * 0.3, y: c.pos.y + c.vel.dy * 0.3)
        }
        return me.pos
    }

    // MARK: spawning

    @discardableResult
    func addCar(_ kind: CarKind, _ ci: Int, _ p: CGPoint, _ h: CGFloat, _ mode: CarMode) -> Car {
        let c = Car(kind, ci, p, h, mode)
        carLayer.addChild(c.node)
        cars.append(c)
        return c
    }

    func randomRoadSpawn(_ minD: CGFloat, _ maxD: CGFloat) -> (CGPoint, Int, Int)? {
        for _ in 0..<25 {
            let horiz = Bool.random()
            let road = Int.random(in: 0..<W.n)
            let along = CGFloat.random(in: 60...(W.size - 60))
            let pos = Bool.random()
            let dir: Int = horiz ? (pos ? 0 : 2) : (pos ? 1 : 3)
            let lane = laneOffset(dir)
            let p: CGPoint = horiz ? CGPoint(x: along, y: W.c(road) + lane) : CGPoint(x: W.c(road) + lane, y: along)
            let d = dist(p, playerCenter)
            if d < minD || d > maxD { continue }
            var clear = true
            for o in cars where dist(o.pos, p) < 90 {
                clear = false
                break
            }
            if clear { return (p, dir, road) }
        }
        return nil
    }

    func spawnTrafficCar(minD: CGFloat, maxD: CGFloat) {
        guard let (p, dir, road) = randomRoadSpawn(minD, maxD) else { return }
        let roll = Int.random(in: 0..<100)
        let kind: CarKind
        if roll < 12 { kind = .police }
        else if roll < 40 { kind = .sports }
        else if roll < 62 { kind = .muscle }
        else if roll < 78 { kind = .van }
        else if roll < 88 { kind = .truck }
        else { kind = .bike }
        let c = addCar(kind, Int.random(in: 0..<carPalette.count), p, CGFloat(dir) * CGFloat.pi / 2, .traffic)
        c.dir = dir
        c.road = road
        c.cruise = c.spec.maxV * CGFloat.random(in: 0.28...0.42)
        c.speed = c.cruise
    }

    func spawnChaser(_ kind: CarKind) {
        guard let (p, dir, road) = randomRoadSpawn(650, 1100) else { return }
        let c = addCar(kind, 0, p, CGFloat(dir) * CGFloat.pi / 2, kind == .tank ? .direct : .chase)
        c.dir = dir
        c.road = road
        c.speed = 200
    }

    @discardableResult
    func spawnUnit(_ kind: UKind, _ p: CGPoint) -> Unit {
        let u: Unit
        switch kind {
        case .ped:
            let pc: [UIColor] = [rgb(0.7, 0.2, 0.2), rgb(0.2, 0.4, 0.7), rgb(0.8, 0.7, 0.2), rgb(0.5, 0.5, 0.55), rgb(0.3, 0.6, 0.4), rgb(0.6, 0.3, 0.6)]
            let skins: [UIColor] = [rgb(0.85, 0.65, 0.5), rgb(0.6, 0.42, 0.3), rgb(0.4, 0.28, 0.2)]
            let ci = Int.random(in: 0..<pc.count)
            let si = Int.random(in: 0..<3)
            let tex = personTexture("ped\(ci)\(si)", pc[ci], rgb(0.15, 0.1, 0.08), false, skins[si])
            u = Unit(.ped, tex, CGSize(width: 24, height: 16), 30)
            u.speed = 38
        case .cop:
            let tex = personTexture("cop", rgb(0.12, 0.20, 0.45), rgb(0.06, 0.08, 0.16), true, rgb(0.82, 0.62, 0.46))
            u = Unit(.cop, tex, CGSize(width: 24, height: 16), 60)
            u.speed = 105
        case .swat:
            let tex = personTexture("swat", rgb(0.08, 0.08, 0.10), rgb(0.05, 0.05, 0.06), true, rgb(0.82, 0.62, 0.46))
            u = Unit(.swat, tex, CGSize(width: 24, height: 16), 110)
            u.speed = 112
        case .gang:
            let tex = personTexture("gang", rgb(0.65, 0.10, 0.10), rgb(0.05, 0.05, 0.05), true, rgb(0.6, 0.42, 0.3))
            u = Unit(.gang, tex, CGSize(width: 24, height: 16), 70)
            u.speed = 85
        case .crew:
            let tex = personTexture("crew", rgb(0.15, 0.55, 0.35), rgb(0.1, 0.1, 0.1), true, rgb(0.85, 0.65, 0.5))
            u = Unit(.crew, tex, CGSize(width: 24, height: 16), 80)
            u.speed = 125
        case .heli:
            u = Unit(.heli, heliTexture(), CGSize(width: 70, height: 26), 160)
            u.radius = 22
            u.speed = 170
            let rotor = SKNode()
            let b1 = SKSpriteNode(color: rgb(0.1, 0.1, 0.12, 0.55), size: CGSize(width: 64, height: 3))
            let b2 = SKSpriteNode(color: rgb(0.1, 0.1, 0.12, 0.55), size: CGSize(width: 3, height: 64))
            rotor.addChild(b1)
            rotor.addChild(b2)
            rotor.position = CGPoint(x: 46, y: 0)
            rotor.zPosition = 3
            rotor.run(SKAction.repeatForever(SKAction.rotate(byAngle: CGFloat.pi * 2, duration: 0.12)))
            u.node.addChild(rotor)
            u.rotor = rotor
        case .drone:
            u = Unit(.drone, droneTexture(), CGSize(width: 24, height: 24), 40)
            u.radius = 13
            u.speed = 150
        }
        u.pos = p
        if u.air { airLayer.addChild(u.node) } else { unitLayer.addChild(u.node) }
        units.append(u)
        return u
    }

    func randomSidewalkPoint(_ minD: CGFloat, _ maxD: CGFloat) -> CGPoint? {
        for _ in 0..<25 {
            let i = Int.random(in: 0..<W.n)
            let j = Int.random(in: 0..<W.n)
            let a = blocks[i * W.n + j].area
            let side = Int.random(in: 0..<4)
            let p: CGPoint
            switch side {
            case 0: p = CGPoint(x: CGFloat.random(in: a.minX...a.maxX), y: a.minY + 9)
            case 1: p = CGPoint(x: CGFloat.random(in: a.minX...a.maxX), y: a.maxY - 9)
            case 2: p = CGPoint(x: a.minX + 9, y: CGFloat.random(in: a.minY...a.maxY))
            default: p = CGPoint(x: a.maxX - 9, y: CGFloat.random(in: a.minY...a.maxY))
            }
            let d = dist(p, playerCenter)
            if d >= minD && d <= maxD { return p }
        }
        return nil
    }

    func spawnPed(minD: CGFloat, maxD: CGFloat) {
        guard let p = randomSidewalkPoint(minD, maxD) else { return }
        let u = spawnUnit(.ped, p)
        u.heading = [0, CGFloat.pi / 2, CGFloat.pi, -CGFloat.pi / 2].randomElement()!
        u.walking = true
        u.dirT = CGFloat.random(in: 1...4)
    }

    func spawnGangMembers(_ p: POI) {
        for k in 0..<4 {
            let ang = CGFloat(k) * CGFloat.pi / 2 + 0.4
            let u = spawnUnit(.gang, CGPoint(x: p.pos.x + cos(ang) * 40, y: p.pos.y + sin(ang) * 40))
            u.tag = p.tag
            u.home = p.pos
        }
    }

    func spawnCopFoot() {
        guard let p = randomSidewalkPoint(500, 900) else { return }
        let u = spawnUnit(stars >= 3 ? .swat : .cop, p)
        u.fireT = CGFloat.random(in: 0.5...1.5)
    }

    func spawnRoadblock() {
        let a = (inCar != nil ? atan2(inCar!.vel.dy, inCar!.vel.dx) : CGFloat.random(in: 0..<(2 * CGFloat.pi)))
        let c0 = playerCenter
        let tp = CGPoint(x: c0.x + cos(a) * 520, y: c0.y + sin(a) * 520)
        let horizRoad = abs(cos(a)) < 0.7
        var pos: CGPoint
        var h: CGFloat
        if horizRoad {
            let j = min(max(Int(((tp.y - W.road / 2) / W.cell).rounded()), 0), W.n - 1)
            pos = CGPoint(x: clampf(tp.x, 80, W.size - 80), y: W.c(j))
            h = CGFloat.pi / 2
        } else {
            let i = min(max(Int(((tp.x - W.road / 2) / W.cell).rounded()), 0), W.n - 1)
            pos = CGPoint(x: W.c(i), y: clampf(tp.y, 80, W.size - 80))
            h = 0
        }
        if dist(pos, c0) < 300 { return }
        for s in [-1, 1] {
            let off: CGFloat = CGFloat(s) * 26
            let p = horizRoad ? CGPoint(x: pos.x, y: pos.y + off) : CGPoint(x: pos.x + off, y: pos.y)
            let van = addCar(.swat, 0, p, h, .parked)
            van.deployed = true
            let u = spawnUnit(.swat, CGPoint(x: p.x + 30, y: p.y + 30))
            u.fireT = 1
        }
        showToast("ROADBLOCK ahead!")
    }

    // MARK: car physics

    func drive(_ c: Car, _ throttle: CGFloat, _ steerIn: CGFloat, _ brake: Bool, _ dt: CGFloat) {
        let sp = c.spec
        var fx = cos(c.heading)
        var fy = sin(c.heading)
        var vf = c.vel.dx * fx + c.vel.dy * fy
        let speedF = min(1, abs(vf) / 110)
        let sgn: CGFloat = vf >= 0 ? 1 : -1
        c.heading += steerIn * sp.steer * speedF * sgn * dt * (brake ? 1.7 : 1.0)
        fx = cos(c.heading)
        fy = sin(c.heading)
        vf = c.vel.dx * fx + c.vel.dy * fy
        var vl = -c.vel.dx * fy + c.vel.dy * fx
        if throttle != 0 {
            vf += sp.accel * throttle * dt
        } else {
            vf *= max(0, 1 - 0.8 * dt)
        }
        vf = clampf(vf, -sp.maxV * 0.4, sp.maxV)
        vf *= max(0, 1 - 0.25 * dt)
        let g: CGFloat = brake ? sp.grip * 0.12 : sp.grip
        let removed = vl * min(1, g * dt)
        vl -= removed
        if !brake { vf += abs(removed) * 0.45 * (vf >= 0 ? 1 : -1) }
        if brake { vf *= max(0, 1 - 1.3 * dt) }
        c.slip = vl
        c.vel = CGVector(dx: fx * vf - fy * vl, dy: fy * vf + fx * vl)
    }

    func addSkid(_ c: Car) {
        for s in [-1, 1] {
            let off: CGFloat = CGFloat(s) * c.spec.wid * 0.38
            let back = -c.spec.len * 0.32
            let p = CGPoint(x: c.pos.x + cos(c.heading) * back - sin(c.heading) * off,
                            y: c.pos.y + sin(c.heading) * back + cos(c.heading) * off)
            let m = SKSpriteNode(color: rgb(0, 0, 0, 0.5), size: CGSize(width: 7, height: 2.5))
            m.position = p
            m.zRotation = c.heading
            decals.addChild(m)
            m.run(SKAction.sequence([SKAction.wait(forDuration: 4), SKAction.fadeOut(withDuration: 2), SKAction.removeFromParent()]))
        }
    }

    func updateCars(_ dt: CGFloat) {
        for c in cars {
            switch c.mode {
            case .player:
                var thr = mv.dy
                var st = -mv.dx
                if abs(thr) < 0.15 { thr = 0 }
                if abs(st) < 0.1 { st = 0 }
                if dead || stunT > 0 { thr = 0; st = 0 }
                drive(c, thr, st, brakeHeld, dt)
                c.pos = CGPoint(x: c.pos.x + c.vel.dx * dt, y: c.pos.y + c.vel.dy * dt)
            case .traffic:
                updateTraffic(c, dt, false)
            case .chase:
                updateTraffic(c, dt, true)
                if dist(c.pos, playerCenter) < 240 { c.mode = .direct }
            case .direct:
                updateDirect(c, dt)
            case .parked:
                drive(c, 0, 0, true, dt)
                c.vel = CGVector(dx: c.vel.dx * max(0, 1 - 2 * dt), dy: c.vel.dy * max(0, 1 - 2 * dt))
                c.pos = CGPoint(x: c.pos.x + c.vel.dx * dt, y: c.pos.y + c.vel.dy * dt)
            case .wreck:
                c.vel = CGVector(dx: c.vel.dx * max(0, 1 - 2.5 * dt), dy: c.vel.dy * max(0, 1 - 2.5 * dt))
                c.pos = CGPoint(x: c.pos.x + c.vel.dx * dt, y: c.pos.y + c.vel.dy * dt)
                c.wreckT += dt
                if c.burnT > 0 {
                    c.burnT -= dt
                    if c.burnT <= 0 {
                        c.burnT = -1
                        explode(c.pos, 85, 70, false)
                    }
                }
            }
            if c.mode != .traffic && c.mode != .chase {
                var p = c.pos
                if let n = pushOut(&p, c.radius) {
                    c.pos = p
                    let vn = c.vel.dx * n.dx + c.vel.dy * n.dy
                    if vn < 0 {
                        c.vel = CGVector(dx: c.vel.dx - n.dx * vn * 1.45, dy: c.vel.dy - n.dy * vn * 1.45)
                        if -vn > 80 {
                            damageCar(c, -vn * 0.10, false)
                            spark(c.pos)
                            if c.mode == .player { shake = max(shake, min(10, -vn / 30)); UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                        }
                    }
                }
            }
            // drift marks
            if (c.mode == .player || c.mode == .direct) && abs(c.slip) > 70 {
                c.skidT -= dt
                if c.skidT <= 0 { c.skidT = 0.05; addSkid(c) }
            }
            // visuals
            c.node.zRotation = c.heading
            let a = -c.heading
            c.shadow.position = CGPoint(x: 3 * cos(a) + 5 * sin(a), y: 3 * sin(a) - 5 * cos(a))
            if let s = c.siren {
                let active = (c.mode == .chase || c.mode == .direct || (c.mode == .player && stars > 0))
                if active {
                    c.sirenT += dt
                    let ph = Int(c.sirenT * 6) % 2
                    s.color = ph == 0 ? rgb(1, 0.1, 0.1) : rgb(0.2, 0.4, 1)
                    s.alpha = 0.75
                } else {
                    s.alpha = 0
                }
            }
            if let l = c.light { l.alpha = (c.mode == .wreck) ? 0 : (c.mode == .player ? 0.42 : 0.26) }
            if c.mode == .wreck {
                c.body.color = UIColor.black
                c.body.colorBlendFactor = 0.8
            }
            if c.kind == .tank, let t = c.turret, c.mode != .wreck {
                let tp = playerCenter
                let ta = atan2(tp.y - c.pos.y, tp.x - c.pos.x)
                t.zRotation = ta - c.heading
                c.fireT -= dt
                if c.fireT <= 0 && stars > 0 && dist(c.pos, tp) < 520 && los(c.pos, tp) && !underground {
                    c.fireT = 3.2
                    let mp = CGPoint(x: c.pos.x + cos(ta) * 50, y: c.pos.y + sin(ta) * 50)
                    addBullet(mp, ta, speed: 480, dmg: 60, life: 1.8, team: 1, kind: 3, explosive: true)
                }
            }
        }
        // car <-> car
        for i in 0..<cars.count {
            for j in (i + 1)..<max(i + 1, cars.count) {
                let a = cars[i]
                let b = cars[j]
                if a.mode == .wreck && b.mode == .wreck { continue }
                let dx = b.pos.x - a.pos.x
                let dy = b.pos.y - a.pos.y
                let d = hypot(dx, dy)
                let rr = a.radius + b.radius
                if d < rr && d > 0.01 {
                    let nx = dx / d
                    let ny = dy / d
                    let pen = rr - d
                    let wa = b.mass / (a.mass + b.mass)
                    a.pos = CGPoint(x: a.pos.x - nx * pen * wa, y: a.pos.y - ny * pen * wa)
                    b.pos = CGPoint(x: b.pos.x + nx * pen * (1 - wa), y: b.pos.y + ny * pen * (1 - wa))
                    let rel = (a.vel.dx - b.vel.dx) * nx + (a.vel.dy - b.vel.dy) * ny
                    if rel > 0 {
                        a.vel = CGVector(dx: a.vel.dx - nx * rel * wa * 1.4, dy: a.vel.dy - ny * rel * wa * 1.4)
                        b.vel = CGVector(dx: b.vel.dx + nx * rel * (1 - wa) * 1.4, dy: b.vel.dy + ny * rel * (1 - wa) * 1.4)
                        if rel > 90 {
                            damageCar(a, rel * 0.07 * b.mass / a.mass, a.mode != .player && b.mode == .player)
                            damageCar(b, rel * 0.07 * a.mass / b.mass, b.mode != .player && a.mode == .player)
                            spark(CGPoint(x: (a.pos.x + b.pos.x) / 2, y: (a.pos.y + b.pos.y) / 2))
                            if a.mode == .player || b.mode == .player {
                                shake = max(shake, min(12, rel / 25))
                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                let other = a.mode == .player ? b : a
                                if other.isCop && stars == 0 { stars = 1; loseT = 0 }
                            }
                        }
                    }
                    if a.mode == .traffic || a.mode == .chase { a.speed = max(0, a.vel.dx * dirVec(a.dir).dx + a.vel.dy * dirVec(a.dir).dy) * 0.6 }
                    if b.mode == .traffic || b.mode == .chase { b.speed = max(0, b.vel.dx * dirVec(b.dir).dx + b.vel.dy * dirVec(b.dir).dy) * 0.6 }
                }
            }
        }
        // cleanup
        var rm: [Car] = []
        let pc = playerCenter
        for c in cars {
            if c === inCar { continue }
            let d = dist(c.pos, pc)
            if c.mode == .wreck && c.wreckT > 12 { rm.append(c) }
            else if c.mode == .traffic && d > 1500 { rm.append(c) }
            else if (c.mode == .parked || c.mode == .direct || c.mode == .chase) && d > 2200 { rm.append(c) }
        }
        for c in rm { c.node.removeFromParent() }
        cars.removeAll(where: { c in rm.contains(where: { $0 === c }) })
    }

    func updateTraffic(_ c: Car, _ dt: CGFloat, _ chase: Bool) {
        let dv = dirVec(c.dir)
        var target = chase ? 270 : c.cruise
        for o in cars where o !== c && o.mode != .wreck {
            let dx = o.pos.x - c.pos.x
            let dy = o.pos.y - c.pos.y
            let ahead = dx * dv.dx + dy * dv.dy
            let side = abs(-dx * dv.dy + dy * dv.dx)
            if ahead > 0 && ahead < 120 && side < 26 {
                target = min(target, max(0, (ahead - 48) * 2.2))
            }
        }
        if !chase {
            for u in units where !u.air && u.kind != .gang {
                let dx = u.pos.x - c.pos.x
                let dy = u.pos.y - c.pos.y
                let ahead = dx * dv.dx + dy * dv.dy
                let side = abs(-dx * dv.dy + dy * dv.dx)
                if ahead > 0 && ahead < 100 && side < 22 { target = min(target, max(0, (ahead - 34) * 2)) }
            }
            if inCar == nil && !dead {
                let dx = me.pos.x - c.pos.x
                let dy = me.pos.y - c.pos.y
                let ahead = dx * dv.dx + dy * dv.dy
                let side = abs(-dx * dv.dy + dy * dv.dx)
                if ahead > 0 && ahead < 100 && side < 22 { target = min(target, max(0, (ahead - 34) * 2)) }
            }
        }
        c.speed += (target - c.speed) * min(1, dt * (target < c.speed ? 4 : 1.5))
        c.pos = CGPoint(x: c.pos.x + dv.dx * c.speed * dt, y: c.pos.y + dv.dy * c.speed * dt)
        let lane = laneOffset(c.dir)
        if c.dir % 2 == 0 {
            let ty = W.c(c.road) + lane
            c.pos = CGPoint(x: c.pos.x, y: c.pos.y + (ty - c.pos.y) * min(1, dt * 3))
        } else {
            let tx = W.c(c.road) + lane
            c.pos = CGPoint(x: c.pos.x + (tx - c.pos.x) * min(1, dt * 3), y: c.pos.y)
        }
        let ta = CGFloat(c.dir) * CGFloat.pi / 2
        c.heading += angDiff(ta, c.heading) * min(1, dt * 6)
        c.vel = CGVector(dx: dv.dx * c.speed, dy: dv.dy * c.speed)
        trafficDecide(c, chase)
    }

    func trafficDecide(_ c: Car, _ chase: Bool) {
        let horiz = c.dir % 2 == 0
        let along = horiz ? c.pos.x : c.pos.y
        let k = Int(((along - W.road / 2) / W.cell).rounded())
        if k < 0 || k >= W.n || k == c.lastNode { return }
        let cc = W.c(k)
        let passed = (c.dir == 0 || c.dir == 1) ? along >= cc : along <= cc
        if !passed { return }
        let ix = horiz ? k : c.road
        let iy = horiz ? c.road : k
        func valid(_ nd: Int) -> Bool {
            switch nd {
            case 0: return ix < W.n - 1
            case 2: return ix > 0
            case 1: return iy < W.n - 1
            default: return iy > 0
            }
        }
        var opts: [Int] = []
        for nd in [c.dir, (c.dir + 1) % 4, (c.dir + 3) % 4] where valid(nd) { opts.append(nd) }
        var nd = (c.dir + 2) % 4
        if !opts.isEmpty {
            if chase {
                let node = CGPoint(x: W.c(ix), y: W.c(iy))
                let tp = playerCenter
                var best = CGFloat.greatestFiniteMagnitude
                for o in opts {
                    let v = dirVec(o)
                    let pp = CGPoint(x: node.x + v.dx * W.cell, y: node.y + v.dy * W.cell)
                    let d = dist(pp, tp) + CGFloat.random(in: 0...60)
                    if d < best { best = d; nd = o }
                }
            } else {
                let r = Int.random(in: 0..<100)
                if opts.contains(c.dir) && r < 55 { nd = c.dir }
                else { nd = opts.randomElement()! }
            }
        }
        c.dir = nd
        c.road = (nd % 2 == 0) ? iy : ix
        c.lastNode = (nd % 2 == 0) ? ix : iy
    }

    func updateDirect(_ c: Car, _ dt: CGFloat) {
        let tp = playerCenter
        let d = dist(c.pos, tp)
        var desired = atan2(tp.y - c.pos.y, tp.x - c.pos.x)
        func blocked(_ ang: CGFloat) -> Bool {
            return solidAt(CGPoint(x: c.pos.x + cos(ang) * 52, y: c.pos.y + sin(ang) * 52))
        }
        if blocked(c.heading) {
            let l = blocked(c.heading + 0.7)
            let r = blocked(c.heading - 0.7)
            desired = c.heading + ((l && !r) ? -1.1 : 1.1)
        }
        let diff = angDiff(desired, c.heading)
        var steer = clampf(diff * 2.2, -1, 1)
        var thr: CGFloat = 1
        if c.kind == .tank { thr = d > 280 ? 1 : 0 }
        if abs(diff) > 1.8 { thr = 0.3 }
        let spd = hypot(c.vel.dx, c.vel.dy)
        if spd < 20 && thr > 0.5 { c.stuckT += dt } else { c.stuckT = 0 }
        if c.stuckT > 0.8 { c.reverseT = 0.9; c.stuckT = 0 }
        if c.reverseT > 0 { c.reverseT -= dt; thr = -1; steer = -steer }
        if stars == 0 && c.kind != .tank {
            // stand down
            c.mode = .parked
            return
        }
        if c.kind == .police && !c.deployed && inCar == nil && !dead && d < 170 && stars < 3 {
            c.deployed = true
            c.mode = .parked
            for k in 0..<2 {
                let p = CGPoint(x: c.pos.x - sin(c.heading) * (c.radius + 10) * (k == 0 ? 1 : -1), y: c.pos.y + cos(c.heading) * (c.radius + 10) * (k == 0 ? 1 : -1))
                spawnUnit(.cop, p)
            }
            return
        }
        drive(c, thr, steer, false, dt)
        c.pos = CGPoint(x: c.pos.x + c.vel.dx * dt, y: c.pos.y + c.vel.dy * dt)
    }

    // MARK: units

    func moveUnit(_ u: Unit, _ dx: CGFloat, _ dy: CGFloat) -> Bool {
        var p = CGPoint(x: u.pos.x + dx, y: u.pos.y + dy)
        let hit = pushOut(&p, u.radius) != nil
        u.pos = p
        return hit
    }

    func updateUnits(_ dt: CGFloat) {
        for u in units {
            u.fireT -= dt
            switch u.kind {
            case .ped: updatePed(u, dt)
            case .cop, .swat: updateCop(u, dt)
            case .gang: updateGang(u, dt)
            case .crew: updateCrew(u, dt)
            case .heli: updateHeli(u, dt)
            case .drone: updateDrone(u, dt)
            }
            u.node.zRotation = u.air ? u.heading : u.heading
        }
        for u in units where u.gone { u.node.removeFromParent() }
        units.removeAll(where: { $0.gone })
    }

    func updatePed(_ u: Unit, _ dt: CGFloat) {
        var hit = false
        if u.fleeT > 0 {
            u.fleeT -= dt
            hit = moveUnit(u, cos(u.heading) * 150 * dt, sin(u.heading) * 150 * dt)
            u.animT += dt * 18
        } else {
            u.dirT -= dt
            if u.dirT <= 0 {
                u.dirT = CGFloat.random(in: 1.5...4)
                u.walking = Int.random(in: 0..<10) < 7
                u.heading = [0, CGFloat.pi / 2, CGFloat.pi, -CGFloat.pi / 2].randomElement()!
            }
            if u.walking {
                hit = moveUnit(u, cos(u.heading) * u.speed * dt, sin(u.heading) * u.speed * dt)
                u.animT += dt * 9
            }
        }
        if hit { u.heading += CGFloat.pi / 2 * (Bool.random() ? 1 : -1); u.dirT = 1.5 }
        u.sprite.yScale = 1 + 0.1 * sin(u.animT)
    }

    func updateCop(_ u: Unit, _ dt: CGFloat) {
        if stars == 0 {
            if !u.leaving { u.leaving = true; u.leaveT = 6 }
        }
        if u.leaving {
            u.leaveT -= dt
            _ = moveUnit(u, cos(u.heading) * 60 * dt, sin(u.heading) * 60 * dt)
            if u.leaveT <= 0 || dist(u.pos, playerCenter) > 1200 { u.gone = true }
            return
        }
        let tp = targetPoint
        let d = dist(u.pos, tp)
        let want: CGFloat = stars == 1 ? 70 : 170
        let ang = atan2(tp.y - u.pos.y, tp.x - u.pos.x)
        u.heading += angDiff(ang, u.heading) * min(1, dt * 10)
        var spd: CGFloat = 0
        if d > want { spd = u.speed } else if d < want * 0.6 { spd = -u.speed * 0.5 }
        if spd != 0 { _ = moveUnit(u, cos(ang) * spd * dt, sin(ang) * spd * dt) }
        u.animT += dt * 10
        u.sprite.yScale = 1 + 0.08 * sin(u.animT)
        if u.fireT <= 0 && d < 340 && !underground && !dead && los(u.pos, tp) {
            if stars == 1 {
                u.fireT = 1.6
                addBullet(CGPoint(x: u.pos.x + cos(ang) * 14, y: u.pos.y + sin(ang) * 14), ang + CGFloat.random(in: -0.05...0.05), speed: 500, dmg: 3, life: 0.28, team: 1, kind: 4)
            } else {
                u.fireT = u.kind == .swat ? 0.4 : 1.0
                let dm: CGFloat = u.kind == .swat ? 7 : 8
                addBullet(CGPoint(x: u.pos.x + cos(ang) * 14, y: u.pos.y + sin(ang) * 14), ang + CGFloat.random(in: -0.09...0.09), speed: 800, dmg: dm, life: 0.6, team: 1, kind: 0)
            }
        }
    }

    func updateGang(_ u: Unit, _ dt: CGFloat) {
        let tp = targetPoint
        let d = dist(u.pos, tp)
        if d < 420 && !underground && !dead && los(u.pos, tp) {
            let ang = atan2(tp.y - u.pos.y, tp.x - u.pos.x)
            u.heading += angDiff(ang, u.heading) * min(1, dt * 10)
            if d > 210 { _ = moveUnit(u, cos(ang) * u.speed * dt, sin(ang) * u.speed * dt) }
            else if d < 120 { _ = moveUnit(u, -cos(ang) * u.speed * dt, -sin(ang) * u.speed * dt) }
            else { _ = moveUnit(u, -sin(ang) * u.strafe * 40 * dt, cos(ang) * u.strafe * 40 * dt) }
            if Int(clock * 2) % 5 == 0 { u.strafe = Bool.random() ? 1 : -1 }
            if u.fireT <= 0 {
                u.fireT = 0.28
                addBullet(CGPoint(x: u.pos.x + cos(ang) * 14, y: u.pos.y + sin(ang) * 14), ang + CGFloat.random(in: -0.12...0.12), speed: 780, dmg: 5, life: 0.6, team: 1, kind: 0)
            }
        } else {
            u.dirT -= dt
            if u.dirT <= 0 { u.dirT = CGFloat.random(in: 1...3); u.heading = CGFloat.random(in: 0..<(2 * CGFloat.pi)) }
            if dist(u.pos, u.home) < 90 { _ = moveUnit(u, cos(u.heading) * 25 * dt, sin(u.heading) * 25 * dt) }
            else { u.heading = atan2(u.home.y - u.pos.y, u.home.x - u.pos.x) }
        }
    }

    func updateCrew(_ u: Unit, _ dt: CGFloat) {
        u.node.isHidden = inCar != nil || underground
        let me0 = me.pos
        if inCar != nil {
            u.pos = playerCenter
            return
        }
        let d = dist(u.pos, me0)
        if d > 700 { u.pos = CGPoint(x: me0.x + CGFloat.random(in: -50...50), y: me0.y + CGFloat.random(in: -50...50)) }
        var tgt: Unit?
        var bd: CGFloat = 280
        for o in units where o.hostile && !o.air && !o.gone {
            let od = dist(o.pos, u.pos)
            if od < bd && los(u.pos, o.pos) { bd = od; tgt = o }
        }
        if let t = tgt {
            let ang = atan2(t.pos.y - u.pos.y, t.pos.x - u.pos.x)
            u.heading += angDiff(ang, u.heading) * min(1, dt * 10)
            if u.fireT <= 0 {
                u.fireT = 0.45
                let b = addBullet(CGPoint(x: u.pos.x + cos(ang) * 14, y: u.pos.y + sin(ang) * 14), ang + CGFloat.random(in: -0.06...0.06), speed: 850, dmg: 9, life: 0.6, team: 0, kind: 0)
                b.crew = true
            }
            if d > 170 { _ = moveUnit(u, cos(u.heading) * u.speed * dt, sin(u.heading) * u.speed * dt) }
        } else if d > 60 {
            let ang = atan2(me0.y - u.pos.y, me0.x - u.pos.x)
            u.heading += angDiff(ang, u.heading) * min(1, dt * 10)
            _ = moveUnit(u, cos(ang) * u.speed * dt, sin(ang) * u.speed * dt)
            u.animT += dt * 10
            u.sprite.yScale = 1 + 0.08 * sin(u.animT)
        }
    }

    func updateHeli(_ u: Unit, _ dt: CGFloat) {
        if stars < 3 && !u.leaving { u.leaving = true; u.leaveT = 4 }
        if u.leaving {
            u.leaveT -= dt
            u.pos = CGPoint(x: u.pos.x + cos(u.heading) * 200 * dt, y: u.pos.y + sin(u.heading) * 200 * dt)
            if u.leaveT <= 0 { u.gone = true }
            return
        }
        let tp = playerCenter
        u.angle += dt * 0.5
        let goal = CGPoint(x: tp.x + cos(u.angle) * 170, y: tp.y + sin(u.angle) * 170)
        let ang = atan2(goal.y - u.pos.y, goal.x - u.pos.x)
        let d = dist(goal, u.pos)
        let sp = min(u.speed + d * 0.5, 320)
        u.heading += angDiff(ang, u.heading) * min(1, dt * 4)
        u.pos = CGPoint(x: u.pos.x + cos(ang) * sp * dt, y: u.pos.y + sin(ang) * sp * dt)
        if u.fireT <= 0 && !underground && !dead && dist(u.pos, tp) < 420 {
            u.fireT = 2.0
            let a2 = atan2(tp.y - u.pos.y, tp.x - u.pos.x)
            addBullet(u.pos, a2 + CGFloat.random(in: -0.07...0.07), speed: 1300, dmg: 14, life: 0.6, team: 1, kind: 0)
        }
    }

    func updateDrone(_ u: Unit, _ dt: CGFloat) {
        if stars < 5 && !u.leaving { u.leaving = true; u.leaveT = 3 }
        if u.leaving {
            u.leaveT -= dt
            u.pos = CGPoint(x: u.pos.x + cos(u.heading) * 200 * dt, y: u.pos.y + sin(u.heading) * 200 * dt)
            if u.leaveT <= 0 { u.gone = true }
            return
        }
        let tp = playerCenter
        let ang = atan2(tp.y - u.pos.y, tp.x - u.pos.x)
        let d = dist(tp, u.pos)
        u.heading += angDiff(ang, u.heading) * min(1, dt * 3)
        if d > 220 { u.pos = CGPoint(x: u.pos.x + cos(ang) * u.speed * dt, y: u.pos.y + sin(ang) * u.speed * dt) }
        else { u.pos = CGPoint(x: u.pos.x - sin(ang) * 60 * dt, y: u.pos.y + cos(ang) * 60 * dt) }
        if u.fireT <= 0 && !underground && !dead && d < 480 {
            u.fireT = 3.6
            addBullet(u.pos, ang, speed: 330, dmg: 45, life: 2.2, team: 1, kind: 2, explosive: true)
        }
    }

    // MARK: combat

    @discardableResult
    func addBullet(_ p: CGPoint, _ a: CGFloat, speed: CGFloat, dmg: CGFloat, life: CGFloat, team: Int, kind: Int, pierce: Int = 0, wall: CGFloat = 0, bounce: Int = 0, explosive: Bool = false) -> Bullet {
        let n = SKNode()
        n.position = p
        n.zRotation = a
        switch kind {
        case 1:
            let g = glowNode(26, rgb(1.0, 0.5, 0.1), 0.9)
            n.addChild(g)
            g.run(SKAction.group([SKAction.scale(to: 2.2, duration: Double(life)), SKAction.fadeOut(withDuration: Double(life))]))
        case 2, 3:
            let body = SKSpriteNode(color: rgb(0.6, 0.6, 0.62), size: CGSize(width: kind == 3 ? 16 : 14, height: kind == 3 ? 6 : 4))
            n.addChild(body)
            n.addChild(glowNode(34, rgb(1.0, 0.6, 0.2), 0.8))
        case 4:
            n.addChild(glowNode(20, rgb(0.4, 0.8, 1.0), 1.0))
        default:
            let tr = SKSpriteNode(color: team == 0 ? rgb(1.0, 0.92, 0.55) : rgb(1.0, 0.45, 0.3), size: CGSize(width: 16, height: 2))
            n.addChild(tr)
            n.addChild(glowNode(14, team == 0 ? rgb(1.0, 0.8, 0.4) : rgb(1.0, 0.3, 0.2), 0.7))
        }
        fxLayer.addChild(n)
        let b = Bullet(node: n, pos: p, vel: CGVector(dx: cos(a) * speed, dy: sin(a) * speed), dmg: dmg, life: life, pierce: pierce, wall: wall, bounce: bounce, explosive: explosive, team: team, kind: kind)
        if kind == 1 { b.radius = 12 }
        if kind == 3 { b.radius = 6 }
        bullets.append(b)
        return b
    }

    func updateBullets(_ dt: CGFloat) {
        var keep: [Bullet] = []
        for b in bullets {
            b.life -= dt
            var alive = b.life > 0
            let steps = max(1, Int(ceil(hypot(b.vel.dx, b.vel.dy) * dt / 8)))
            let sdt = dt / CGFloat(steps)
            var s = 0
            while alive && s < steps {
                s += 1
                let prev = b.pos
                b.pos = CGPoint(x: b.pos.x + b.vel.dx * sdt, y: b.pos.y + b.vel.dy * sdt)
                if b.pos.x < 0 || b.pos.y < 0 || b.pos.x > W.size || b.pos.y > W.size { alive = false; break }
                if b.kind != 1 || true {
                    if let rc = wallRect(b.pos) {
                        if b.explosive {
                            explode(b.pos, 90, b.dmg * 1.4, b.team == 0)
                            alive = false
                            break
                        }
                        if b.wall > 0 {
                            b.wall -= hypot(b.vel.dx, b.vel.dy) * sdt
                            if b.wall <= 0 { alive = false; spark(b.pos); break }
                            b.inWall = true
                        } else if b.bounce > 0 {
                            b.bounce -= 1
                            b.dmg *= 0.6
                            if prev.x < rc.minX || prev.x > rc.maxX { b.vel.dx = -b.vel.dx } else { b.vel.dy = -b.vel.dy }
                            b.pos = prev
                            b.node.zRotation = atan2(b.vel.dy, b.vel.dx)
                            spark(b.pos)
                        } else {
                            if b.kind != 1 { spark(b.pos) }
                            alive = false
                            break
                        }
                    }
                }
                // units
                for u in units where !u.dead && !u.gone {
                    if b.team == 0 {
                        if u.kind == .crew { continue }
                        if b.crew && u.kind == .ped { continue }
                    } else {
                        if u.kind != .crew { continue }
                    }
                    if b.hit.contains(ObjectIdentifier(u)) { continue }
                    if dist(b.pos, u.pos) < u.radius + b.radius + (b.kind == 1 ? 4 : 0) {
                        b.hit.insert(ObjectIdentifier(u))
                        if b.explosive {
                            explode(b.pos, 90, b.dmg * 1.4, b.team == 0)
                            alive = false
                        } else {
                            damageUnit(u, b.dmg, b.team == 0 && !b.crew)
                            if b.pierce > 0 { b.pierce -= 1 } else { alive = false }
                        }
                        if !alive { break }
                    }
                }
                if !alive { break }
                // cars
                for c in cars where c.mode != .wreck && c !== inCar {
                    if b.hit.contains(ObjectIdentifier(c)) { continue }
                    if b.team == 1 && c.isCop { continue }
                    if dist(b.pos, c.pos) < c.radius + b.radius {
                        b.hit.insert(ObjectIdentifier(c))
                        if b.explosive {
                            explode(b.pos, 90, b.dmg * 1.4, b.team == 0)
                            alive = false
                        } else {
                            damageCar(c, b.dmg * 0.6, b.team == 0)
                            spark(b.pos)
                            if b.pierce > 0 { b.pierce -= 1; b.dmg *= 0.7 } else { alive = false }
                        }
                        if !alive { break }
                    }
                }
                if !alive { break }
                // player
                if b.team == 1 && !underground && !dead {
                    if dist(b.pos, playerCenter) < playerRadius + b.radius {
                        if b.explosive {
                            explode(b.pos, 90, b.dmg * 1.4, false)
                        } else {
                            hurtPlayer(b.dmg, tase: b.kind == 4)
                        }
                        alive = false
                        break
                    }
                }
            }
            if b.kind == 2 || b.kind == 3 {
                b.trailT -= dt
                if b.trailT <= 0 { b.trailT = 0.04; puff(b.pos, 5) }
            }
            if alive {
                b.node.position = b.pos
                keep.append(b)
            } else {
                if b.explosive && b.life <= 0 { explode(b.pos, 90, b.dmg * 1.4, b.team == 0) }
                b.node.removeFromParent()
            }
        }
        bullets = keep
    }

    func updateBombs(_ dt: CGFloat) {
        var keep: [Bomb] = []
        for b in bombs {
            let prev = b.pos
            b.pos = CGPoint(x: b.pos.x + b.vel.dx * dt, y: b.pos.y + b.vel.dy * dt)
            b.vel = CGVector(dx: b.vel.dx * max(0, 1 - 2.2 * dt), dy: b.vel.dy * max(0, 1 - 2.2 * dt))
            if solidAt(b.pos) { b.pos = prev; b.vel = CGVector(dx: -b.vel.dx * 0.4, dy: -b.vel.dy * 0.4) }
            b.node.position = b.pos
            b.node.zRotation += dt * 8
            b.t -= dt
            if b.t <= 0 {
                b.node.removeFromParent()
                explode(b.pos, 105, 120, b.fromPlayer)
            } else {
                keep.append(b)
            }
        }
        bombs = keep
    }

    func throwBomb() {
        if bombCD > 0 || dead || underground { return }
        bombCD = 1.2
        let c0 = playerCenter
        let a: CGFloat
        if let c = inCar { a = c.heading + CGFloat.pi }
        else if hypot(aim.dx, aim.dy) > 0.25 { a = aimAngle }
        else { a = me.heading }
        let n = SKNode()
        n.addChild(SKSpriteNode(color: rgb(0.45, 0.46, 0.5), size: CGSize(width: 10, height: 4)))
        let led = glowNode(14, rgb(1, 0.1, 0.1), 1)
        led.run(SKAction.repeatForever(SKAction.sequence([SKAction.fadeAlpha(to: 0.1, duration: 0.15), SKAction.fadeAlpha(to: 1, duration: 0.15)])))
        n.addChild(led)
        n.position = c0
        fxLayer.addChild(n)
        var v = CGVector(dx: cos(a) * 300, dy: sin(a) * 300)
        if let c = inCar { v = CGVector(dx: v.dx + c.vel.dx * 0.6, dy: v.dy + c.vel.dy * 0.6) }
        bombs.append(Bomb(node: n, pos: c0, vel: v, fromPlayer: true))
        crime(1)
    }

    func spark(_ p: CGPoint) {
        for _ in 0..<3 {
            let s = SKSpriteNode(color: rgb(1.0, 0.85, 0.4), size: CGSize(width: 3, height: 1.5))
            s.position = p
            s.zRotation = CGFloat.random(in: 0..<(2 * CGFloat.pi))
            s.blendMode = .add
            fxLayer.addChild(s)
            let ang = CGFloat.random(in: 0..<(2 * CGFloat.pi))
            s.run(SKAction.sequence([
                SKAction.group([SKAction.moveBy(x: cos(ang) * 26, y: sin(ang) * 26, duration: 0.2), SKAction.fadeOut(withDuration: 0.2)]),
                SKAction.removeFromParent()
            ]))
        }
    }

    func puff(_ p: CGPoint, _ r: CGFloat) {
        let s = SKShapeNode(circleOfRadius: r)
        s.fillColor = rgb(0.6, 0.6, 0.6, 0.45)
        s.strokeColor = UIColor.clear
        s.position = p
        fxLayer.addChild(s)
        s.run(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 3, duration: 0.6), SKAction.fadeOut(withDuration: 0.6)]),
            SKAction.removeFromParent()
        ]))
    }

    func splat(_ p: CGPoint) {
        let s = SKShapeNode(circleOfRadius: CGFloat.random(in: 4...8))
        s.fillColor = rgb(0.5, 0.02, 0.02, 0.6)
        s.strokeColor = UIColor.clear
        s.position = p
        decals.addChild(s)
        s.run(SKAction.sequence([SKAction.wait(forDuration: 18), SKAction.fadeOut(withDuration: 5), SKAction.removeFromParent()]))
    }

    func explode(_ p: CGPoint, _ radius: CGFloat, _ dmg: CGFloat, _ byPlayer: Bool) {
        let fire = glowNode(radius * 1.6, rgb(1.0, 0.55, 0.15), 1.0)
        fire.position = p
        fire.setScale(0.3)
        fxLayer.addChild(fire)
        fire.run(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 1.8, duration: 0.35), SKAction.fadeOut(withDuration: 0.4)]),
            SKAction.removeFromParent()
        ]))
        let flash = glowNode(radius * 4, rgb(1.0, 0.9, 0.6), 0.6)
        flash.position = p
        fxLayer.addChild(flash)
        flash.run(SKAction.sequence([SKAction.fadeOut(withDuration: 0.5), SKAction.removeFromParent()]))
        for _ in 0..<5 { puff(CGPoint(x: p.x + CGFloat.random(in: -radius * 0.4...radius * 0.4), y: p.y + CGFloat.random(in: -radius * 0.4...radius * 0.4)), radius * 0.2) }
        for _ in 0..<8 { spark(p) }
        let scorch = SKShapeNode(circleOfRadius: radius * 0.45)
        scorch.fillColor = rgb(0, 0, 0, 0.4)
        scorch.strokeColor = UIColor.clear
        scorch.position = p
        decals.addChild(scorch)
        scorch.run(SKAction.sequence([SKAction.wait(forDuration: 25), SKAction.fadeOut(withDuration: 5), SKAction.removeFromParent()]))
        let pd = dist(p, playerCenter)
        shake = max(shake, clampf(16 - pd / 40, 0, 16))
        if pd < 300 { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
        for u in units where !u.dead && !u.gone {
            if u.kind == .crew && byPlayer { continue }
            let d = dist(u.pos, p)
            if d < radius + u.radius {
                damageUnit(u, dmg * (1 - d / (radius * 1.3)), byPlayer)
            }
        }
        for c in cars where c.mode != .wreck {
            let d = dist(c.pos, p)
            if d < radius + c.radius {
                damageCar(c, dmg * 1.1 * (1 - d / (radius * 1.5)), byPlayer)
                let m = max(d, 1)
                c.vel = CGVector(dx: c.vel.dx + (c.pos.x - p.x) / m * 160 / c.mass, dy: c.vel.dy + (c.pos.y - p.y) / m * 160 / c.mass)
            }
        }
        if !underground && !dead {
            let d = dist(playerCenter, p)
            if d < radius + 8 { hurtPlayer(dmg * 0.6 * (1 - d / (radius * 1.3)), tase: false) }
        }
    }

    func hurtPlayer(_ d: CGFloat, tase: Bool) {
        if dead { return }
        if tase {
            stunT = 1.2
            me.hp -= d
        } else if let c = inCar {
            damageCar(c, d * 0.8, false)
            me.hp -= d * 0.3
        } else {
            me.hp -= d
        }
        hurtFlash.alpha = 0.35
        if me.hp <= 0 { die() }
    }

    func die() {
        if dead { return }
        dead = true
        deadT = 3.5
        wastedLabel.text = "WASTED"
        wastedLabel.isHidden = false
        if let c = inCar { c.mode = .parked; inCar = nil }
        me.node.isHidden = false
        me.node.alpha = 0.6
        me.node.zRotation = 1.4
        robbing = nil
        raceOn = false
        raceRing?.removeFromParent()
        raceRing = nil
    }

    func respawn() {
        dead = false
        me.hp = 100
        me.node.alpha = 1
        me.node.isHidden = false
        wastedLabel.isHidden = true
        stars = 0
        loseT = 0
        standDown()
        setUnderground(false)
        cash = max(0, cash - 300)
        var sp = CGPoint(x: W.c(1) + 30, y: W.c(1) + 10)
        if ownsHouse, let h = pois.first(where: { $0.kind == .safehouse }) { sp = CGPoint(x: h.pos.x + 30, y: h.pos.y - 20) }
        me.pos = sp
        showToast("Hospital bill: -$300")
    }

    func damageUnit(_ u: Unit, _ d: CGFloat, _ byPlayer: Bool) {
        if u.dead { return }
        u.hp -= d
        u.sprite.removeAllActions()
        u.sprite.run(SKAction.sequence([SKAction.colorize(with: UIColor.red, colorBlendFactor: 0.8, duration: 0.03), SKAction.colorize(withColorBlendFactor: 0, duration: 0.15)]))
        if u.kind == .ped && u.hp > 0 { u.fleeT = 4; u.heading = CGFloat.random(in: 0..<(2 * CGFloat.pi)) }
        if byPlayer && (u.kind == .cop || u.kind == .swat) && stars == 0 && dist(u.pos, playerCenter) < 600 { stars = 1; loseT = 0 }
        if u.hp <= 0 { killUnit(u, byPlayer) }
    }

    func killUnit(_ u: Unit, _ byPlayer: Bool) {
        u.dead = true
        u.gone = true
        splat(u.pos)
        if u.air {
            explode(u.pos, 60, 30, byPlayer)
            cash += 200
            return
        }
        switch u.kind {
        case .ped:
            let c = Int.random(in: 5...45)
            cash += c
            if byPlayer { crime(1) }
        case .cop, .swat:
            if byPlayer { stars = max(stars, 2); loseT = 0; crimeCD = 0 }
            cash += 40
        case .gang:
            cash += 30
            checkTerritory(u.tag)
        case .crew:
            showToast("Crew member down")
        default:
            break
        }
    }

    func checkTerritory(_ tag: Int) {
        for u in units where u.kind == .gang && u.tag == tag && !u.dead { return }
        guard let p = pois.first(where: { $0.kind == .gang && $0.tag == tag }), !p.owned else { return }
        p.owned = true
        p.dot?.fillColor = rgb(0.3, 1.0, 0.4)
        p.ring?.color = rgb(0.3, 1.0, 0.4)
        cash += 500
        showToast("TERRITORY CAPTURED! +$500 and daily income")
        saveGame()
    }

    func damageCar(_ c: Car, _ d: CGFloat, _ byPlayer: Bool) {
        if c.mode == .wreck { return }
        c.hp -= d
        if byPlayer && c.isCop && stars == 0 && dist(c.pos, playerCenter) < 600 { stars = 1; loseT = 0 }
        if c.hp <= 0 { wreck(c) }
    }

    func wreck(_ c: Car) {
        if c === inCar {
            exitCar()
            hurtPlayer(35, tase: false)
        }
        c.mode = .wreck
        c.burnT = 1.2
        c.wreckT = 0
        let f = glowNode(60, rgb(1.0, 0.5, 0.1), 0.9)
        f.zPosition = 4
        f.run(SKAction.repeatForever(SKAction.sequence([SKAction.fadeAlpha(to: 0.5, duration: 0.15), SKAction.fadeAlpha(to: 0.9, duration: 0.2)])))
        c.node.addChild(f)
    }

    // MARK: wanted

    func crime(_ n: Int) {
        if underground || crimeCD > 0 { return }
        if seen || stars > 0 {
            stars = min(5, stars + n)
            loseT = 0
            crimeCD = stars > 2 ? 9 : 5
            showToast("WANTED LEVEL \(stars)")
        }
    }

    func updateSeen() {
        var s = false
        if !underground && !dead {
            let pc = playerCenter
            for u in units where (u.kind == .cop || u.kind == .swat || u.kind == .heli || u.kind == .drone) && !u.gone {
                let d = dist(u.pos, pc)
                if d < 520 && (u.air || los(u.pos, pc)) { s = true; break }
            }
            if !s {
                for c in cars where c.isCop && c.mode != .wreck {
                    let d = dist(c.pos, pc)
                    if d < 520 && los(c.pos, pc) { s = true; break }
                }
            }
        }
        seen = s
        if stars > 0 && s == false && underground == false { }
        if stars > 0 && (seen || underground == false && s) { }
        if s && stars > 0 { loseT = 0 }
        if s && stars == 0 { /* patrol sees you: only when a crime happens */ }
        // escalate patrol cruisers when wanted
        if stars > 0 {
            for c in cars where c.kind == .police && c.mode == .traffic && dist(c.pos, playerCenter) < 900 {
                c.mode = .chase
            }
        }
    }

    func standDown() {
        for c in cars where c.isCop && (c.mode == .chase || c.mode == .direct) && c.kind != .tank {
            c.mode = .parked
        }
        for c in cars where c.kind == .tank && c.mode != .wreck { c.mode = .parked }
        for u in units where u.kind == .cop || u.kind == .swat || u.kind == .heli || u.kind == .drone {
            u.leaving = true
            u.leaveT = 4
        }
    }

    func manageHeat(_ dt: CGFloat) {
        if stars > 0 {
            if seen { loseT = 0 } else {
                loseT += dt * (underground ? 3 : 1)
                if loseT > 9 {
                    loseT = 0
                    stars -= 1
                    if stars == 0 {
                        showToast("Wanted level cleared")
                        standDown()
                    }
                }
            }
        }
        if stars == 0 { return }
        spawnT -= dt
        if spawnT <= 0 {
            spawnT = 1.4
            let wantCars = [0, 2, 3, 3, 4, 4][stars]
            let wantFoot = [0, 2, 4, 6, 7, 8][stars]
            let chasers = cars.filter { $0.isCop && ($0.mode == .chase || $0.mode == .direct) && $0.kind != .tank }.count
            let foot = units.filter { ($0.kind == .cop || $0.kind == .swat) && !$0.leaving }.count
            if chasers < wantCars {
                spawnChaser((stars >= 3 && chasers % 2 == 1) ? .swat : .police)
            } else if foot < wantFoot && inCar == nil {
                spawnCopFoot()
            } else if foot < max(0, wantFoot - 3) {
                spawnCopFoot()
            }
            if stars >= 3 && !units.contains(where: { $0.kind == .heli && !$0.leaving }) {
                let side = CGFloat.random(in: 0..<(2 * CGFloat.pi))
                let pc = playerCenter
                let u = spawnUnit(.heli, CGPoint(x: pc.x + cos(side) * 700, y: pc.y + sin(side) * 700))
                u.angle = side
                showToast("Police chopper incoming")
            }
            if stars >= 5 {
                let dr = units.filter { $0.kind == .drone && !$0.leaving }.count
                if dr < 2 {
                    let side = CGFloat.random(in: 0..<(2 * CGFloat.pi))
                    let pc = playerCenter
                    spawnUnit(.drone, CGPoint(x: pc.x + cos(side) * 650, y: pc.y + sin(side) * 650))
                }
                if !cars.contains(where: { $0.kind == .tank && $0.mode != .wreck }) {
                    spawnChaser(.tank)
                    showToast("ARMY TANKS deployed - city lockdown")
                }
            }
        }
        roadblockT -= dt
        if stars >= 3 && roadblockT <= 0 {
            roadblockT = 28
            spawnRoadblock()
        }
    }

    // MARK: actions

    func nearestCar(_ maxD: CGFloat) -> Car? {
        var best: Car?
        var bd = maxD
        for c in cars where c.mode != .wreck && c.kind != .tank && c !== inCar {
            let d = dist(c.pos, me.pos) - c.radius
            if d < bd { bd = d; best = c }
        }
        return best
    }

    func enterCar(_ c: Car) {
        let hadDriver = (c.mode == .traffic || c.mode == .chase || c.mode == .direct)
        if hadDriver {
            let side = CGPoint(x: c.pos.x - sin(c.heading) * (c.radius + 12), y: c.pos.y + cos(c.heading) * (c.radius + 12))
            if c.isCop {
                let u = spawnUnit(.cop, side)
                u.fireT = 1.5
                stars = max(stars, 2)
                loseT = 0
            } else {
                let u = spawnUnit(.ped, side)
                u.fleeT = 5
                u.heading = CGFloat.random(in: 0..<(2 * CGFloat.pi))
                crime(1)
            }
            if c.mode == .traffic || c.mode == .chase { c.vel = CGVector(dx: dirVec(c.dir).dx * c.speed, dy: dirVec(c.dir).dy * c.speed) }
        }
        c.mode = .player
        inCar = c
        me.node.isHidden = true
        me.pos = c.pos
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showToast(hadDriver ? "JACKED!" : "In the car")
    }

    func exitCar() {
        guard let c = inCar else { return }
        c.mode = .parked
        inCar = nil
        var p = CGPoint(x: c.pos.x - sin(c.heading) * (c.radius + 12), y: c.pos.y + cos(c.heading) * (c.radius + 12))
        _ = pushOut(&p, 8)
        me.pos = p
        me.node.isHidden = false
        brakeHeld = false
    }

    func setUnderground(_ on: Bool) {
        underground = on
        ground.isHidden = on
        decals.isHidden = on
        poiLayer.isHidden = on
        unitLayer.isHidden = on
        carLayer.isHidden = on
        airLayer.isHidden = on
        sewerLayer.isHidden = !on
        underOverlay.isHidden = !on
        rain?.isHidden = on
        backgroundColor = on ? rgb(0.02, 0.04, 0.04) : rgb(0.03, 0.04, 0.07)
    }

    func nearestManhole(_ maxD: CGFloat) -> CGPoint? {
        var best: CGPoint?
        var bd = maxD
        for m in manholes {
            let d = dist(m, me.pos)
            if d < bd { bd = d; best = m }
        }
        return best
    }

    func recruit(_ u: Unit) {
        let crewCount = units.filter { $0.kind == .crew }.count
        if crewCount >= 4 { showToast("Crew is full (4)"); return }
        if cash >= 200 {
            cash -= 200
        } else if Bool.random() {
            showToast("Not enough cash - they ran away")
            u.fleeT = 5
            return
        }
        u.gone = true
        let c = spawnUnit(.crew, u.pos)
        c.fireT = 1
        showToast("Recruited into your crew")
    }

    func startRob(_ p: POI) {
        robbing = p
        robT = 0
        stars = max(stars, 2)
        loseT = 0
        showToast("ALARM! Stay inside the marker")
    }

    func startRace() {
        guard let c = inCar else { return }
        raceOn = true
        raceIdx = 0
        raceT = 55
        _ = c
        placeRaceRing()
        showToast("DRAG RACE! Hit all checkpoints in 55s")
    }

    var raceCPs: [CGPoint] {
        return [CGPoint(x: W.c(7), y: W.c(4)), CGPoint(x: W.c(7), y: W.c(7)), CGPoint(x: W.c(2), y: W.c(7)), CGPoint(x: W.c(2), y: W.c(4))]
    }

    func placeRaceRing() {
        raceRing?.removeFromParent()
        let r = SKSpriteNode(texture: ringTexture(), size: CGSize(width: 120, height: 120))
        r.color = rgb(0.3, 0.9, 1.0)
        r.colorBlendFactor = 1
        r.blendMode = .add
        r.position = raceCPs[raceIdx]
        poiLayer.addChild(r)
        raceRing = r
    }

    func safehouseAction(_ p: POI) {
        if !ownsHouse {
            if cash >= 5000 { cash -= 5000; ownsHouse = true; showToast("Safehouse bought! Heal, save, garage, armory"); saveGame() }
            else { showToast("Safehouse costs $5000") }
            return
        }
        if let g = garage {
            let c = addCar(g.0, g.1, CGPoint(x: p.pos.x + 70, y: p.pos.y - 6), 0, .parked)
            _ = c
            garage = nil
            showToast("Car out of the garage")
            return
        }
        me.hp = 100
        saveGame()
        if let idx = weapons.indices.first(where: { (unlocked & (1 << $0)) == 0 }) {
            let w = weapons[idx]
            if cash >= w.price {
                cash -= w.price
                unlocked |= (1 << idx)
                showToast("Bought \(w.name)")
            } else {
                showToast("Rested & saved. Next: \(w.name) $\(w.price)")
            }
        } else {
            showToast("Rested & saved")
        }
    }

    func storeCar(_ c: Car) {
        garage = (c.kind, c.ci)
        exitCar()
        c.node.removeFromParent()
        cars.removeAll(where: { $0 === c })
        showToast("Car stored in the garage")
    }

    func paintCar() {
        guard let c = inCar, stars > 0 else { return }
        if seen { showToast("Cops can see you! Break line of sight first"); return }
        if cash < 150 { showToast("Respray costs $150"); return }
        cash -= 150
        c.ci = (c.ci + 3) % carPalette.count
        c.body.texture = carTexture(c.kind, c.ci)
        stars = 0
        loseT = 0
        standDown()
        showToast("New paint job - wanted level lost")
    }

    func cycleWeapon() {
        for _ in 0..<weapons.count {
            weaponIdx = (weaponIdx + 1) % weapons.count
            if unlocked & (1 << weaponIdx) != 0 { break }
        }
        showToast(weapons[weaponIdx].name)
    }

    func computeAction() {
        actLabel = nil
        actHandler = nil
        if dead { return }
        if let c = inCar {
            if let race = pois.first(where: { $0.kind == .race }), !raceOn, dist(c.pos, race.pos) < 80 {
                actLabel = "RACE"
                actHandler = { [weak self] in self?.startRace() }
            } else if ownsHouse, let h = pois.first(where: { $0.kind == .safehouse }), dist(c.pos, h.pos) < 110 {
                actLabel = "GARAGE"
                actHandler = { [weak self] in self?.storeCar(c) }
            } else {
                actLabel = "EXIT"
                actHandler = { [weak self] in self?.exitCar() }
            }
            return
        }
        if underground {
            if nearestManhole(60) != nil {
                actLabel = "SURFACE"
                actHandler = { [weak self] in
                    guard let self = self, let m = self.nearestManhole(60) else { return }
                    self.setUnderground(false)
                    self.me.pos = CGPoint(x: m.x, y: m.y + 18)
                }
            }
            return
        }
        var bestD = CGFloat.greatestFiniteMagnitude
        func consider(_ d: CGFloat, _ label: String, _ h: @escaping () -> Void) {
            if d < bestD { bestD = d; actLabel = label; actHandler = h }
        }
        if let c = nearestCar(40) {
            let d = dist(c.pos, me.pos) - c.radius
            consider(d, c.mode == .parked ? "ENTER" : "JACK", { [weak self] in self?.enterCar(c) })
        }
        if let m = nearestManhole(36) {
            consider(dist(m, me.pos), "SEWER", { [weak self] in
                guard let self = self else { return }
                self.me.pos = m
                self.setUnderground(true)
                self.showToast("Underground - cops lost you")
            })
        }
        for u in units where u.kind == .ped && !u.gone {
            let d = dist(u.pos, me.pos)
            if d < 46 {
                consider(d + 5, cash >= 200 ? "RECRUIT" : "SCARE", { [weak self] in self?.recruit(u) })
            }
        }
        for p in pois {
            let d = dist(p.pos, me.pos)
            if d > 70 { continue }
            switch p.kind {
            case .bank, .jewelry:
                if p.cool <= 0 && robbing == nil { consider(d, "ROB", { [weak self] in self?.startRob(p) }) }
            case .safehouse:
                consider(d, ownsHouse ? "HOUSE" : "BUY", { [weak self] in self?.safehouseAction(p) })
            default:
                break
            }
        }
    }

    func doAction() {
        if let h = actHandler { h() }
    }

    // MARK: input

    func stickVec(_ p: CGPoint, _ center: CGPoint) -> CGVector {
        var dx = (p.x - center.x) / 55
        var dy = (p.y - center.y) / 55
        let m = hypot(dx, dy)
        if m > 1 { dx /= m; dy /= m }
        return CGVector(dx: dx, dy: dy)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: hud)
            if dead { continue }
            if actBtn.visible && actBtn.hit(p) { doAction(); continue }
            if brakeBtn.visible && brakeBtn.hit(p) { brakeHeld = true; brakeTouch = t; continue }
            if paintBtn.visible && paintBtn.hit(p) { paintCar(); continue }
            if weaponBtn.hit(p) { cycleWeapon(); continue }
            if bombBtn.hit(p) { throwBomb(); continue }
            if p.x < size.width * 0.5 {
                if moveTouch == nil {
                    moveTouch = t
                    moveCenter = p
                    stickRingL.position = p
                }
            } else {
                if aimTouch == nil {
                    aimTouch = t
                    aimCenter = p
                    stickRingR.position = p
                }
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: hud)
            if t === moveTouch {
                mv = stickVec(p, moveCenter)
                stickKnobL.position = CGPoint(x: mv.dx * 55, y: mv.dy * 55)
            } else if t === aimTouch {
                aim = stickVec(p, aimCenter)
                stickKnobR.position = CGPoint(x: aim.dx * 55, y: aim.dy * 55)
            }
        }
    }

    func endTouches(_ touches: Set<UITouch>) {
        for t in touches {
            if t === moveTouch {
                moveTouch = nil
                mv = CGVector.zero
                stickKnobL.position = CGPoint.zero
                stickRingL.position = CGPoint(x: 120, y: 85)
            } else if t === aimTouch {
                aimTouch = nil
                aim = CGVector.zero
                stickKnobR.position = CGPoint.zero
                stickRingR.position = CGPoint(x: size.width - 120, y: 85)
            } else if t === brakeTouch {
                brakeTouch = nil
                brakeHeld = false
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { endTouches(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { endTouches(touches) }

    // MARK: player firing + on-foot movement

    func playerFire() {
        let w = weapons[weaponIdx]
        let c0 = playerCenter
        for k in 0..<w.pellets {
            var a = aimAngle + CGFloat.random(in: -w.spread...w.spread)
            if w.pellets > 1 { a += (CGFloat(k) - CGFloat(w.pellets) / 2) * 0.01 }
            var origin = CGPoint(x: c0.x + cos(a) * 16, y: c0.y + sin(a) * 16)
            if weaponIdx == 1 {
                let off: CGFloat = (Int(clock * 20) % 2 == 0) ? 6 : -6
                origin = CGPoint(x: origin.x - sin(a) * off, y: origin.y + cos(a) * off)
            }
            addBullet(origin, a, speed: w.speed, dmg: w.dmg, life: w.life, team: 0, kind: w.kind, pierce: w.pierce, wall: w.wall, bounce: w.bounce, explosive: w.explosive)
        }
        let fl = glowNode(50, rgb(1.0, 0.8, 0.4), 0.9)
        fl.position = CGPoint(x: c0.x + cos(aimAngle) * 20, y: c0.y + sin(aimAngle) * 20)
        fxLayer.addChild(fl)
        fl.run(SKAction.sequence([SKAction.fadeOut(withDuration: 0.08), SKAction.removeFromParent()]))
        if w.kind == 0 && w.rate < 5 { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        shake = max(shake, w.explosive ? 6 : (w.pellets > 1 ? 4 : 1.2))
        for u in units where u.kind == .ped && dist(u.pos, c0) < 280 && u.fleeT <= 0 {
            u.fleeT = 5
            u.heading = atan2(u.pos.y - c0.y, u.pos.x - c0.x)
        }
        crime(1)
    }

    func updatePlayerFoot(_ dt: CGFloat) {
        if inCar != nil || dead { return }
        if stunT > 0 { stunT -= dt; return }
        let mag = hypot(mv.dx, mv.dy)
        let sp: CGFloat = underground ? 90 : 135
        let aimMag = hypot(aim.dx, aim.dy)
        if mag > 0.12 {
            var p = CGPoint(x: me.pos.x + mv.dx * sp * dt, y: me.pos.y + mv.dy * sp * dt)
            if underground { sewerClamp(&p) } else { _ = pushOut(&p, 7) }
            me.pos = p
            if aimMag <= 0.25 { me.heading = atan2(mv.dy, mv.dx) }
            me.animT += dt * 11
            me.sprite.yScale = 1 + 0.08 * sin(me.animT)
        }
        if aimMag > 0.25 { me.heading = aimAngle }
        me.node.zRotation = me.heading
        // parked/moving cars push you
        for c in cars where c.mode != .wreck {
            let d = dist(c.pos, me.pos)
            if d < c.radius + 7 && d > 0.01 {
                let spd = hypot(c.vel.dx, c.vel.dy)
                let nx = (me.pos.x - c.pos.x) / d
                let ny = (me.pos.y - c.pos.y) / d
                me.pos = CGPoint(x: c.pos.x + nx * (c.radius + 7), y: c.pos.y + ny * (c.radius + 7))
                if spd > 100 && c.mode != .parked { hurtPlayer(spd * 0.22, tase: false) }
            }
        }
    }

    func updateUnitCarHits() {
        for c in cars where c.mode != .wreck {
            let spd = hypot(c.vel.dx, c.vel.dy)
            if spd < 60 { continue }
            for u in units where !u.air && !u.dead && !u.gone {
                let d = dist(c.pos, u.pos)
                if d < c.radius + u.radius {
                    if spd > 90 {
                        damageUnit(u, spd * 0.35, c.mode == .player)
                        let m = max(d, 1)
                        u.pos = CGPoint(x: u.pos.x + (u.pos.x - c.pos.x) / m * 8, y: u.pos.y + (u.pos.y - c.pos.y) / m * 8)
                        if c.mode == .player { crime(1); shake = max(shake, 3) }
                    }
                }
            }
        }
    }

    // MARK: missions: robbery, race, passive income

    func updateMissions(_ dt: CGFloat) {
        for p in pois where p.cool > 0 { p.cool -= dt }
        if let p = robbing {
            if dead || dist(me.pos, p.pos) > 110 || inCar != nil {
                robbing = nil
                showToast("Robbery failed")
            } else {
                robT += dt
                if robT >= 6 {
                    let loot = p.kind == .bank ? 4000 : 1800
                    cash += loot
                    p.cool = 150
                    robbing = nil
                    showToast("HEIST DONE! +$\(loot)")
                    saveGame()
                }
            }
        }
        if raceOn {
            raceT -= dt
            if let c = inCar {
                if dist(c.pos, raceCPs[raceIdx]) < 70 {
                    raceIdx += 1
                    if raceIdx >= raceCPs.count {
                        raceOn = false
                        raceRing?.removeFromParent()
                        raceRing = nil
                        cash += 1500
                        showToast("RACE WON! +$1500")
                    } else {
                        placeRaceRing()
                        raceT += 6
                    }
                }
            } else {
                raceOn = false
                raceRing?.removeFromParent()
                raceRing = nil
                showToast("Race cancelled")
            }
            if raceOn && raceT <= 0 {
                raceOn = false
                raceRing?.removeFromParent()
                raceRing = nil
                showToast("Race failed")
            }
        }
        incomeT += dt
        if incomeT >= 20 {
            incomeT = 0
            let n = pois.filter { $0.kind == .gang && $0.owned }.count
            if n > 0 {
                cash += n * 150
                showToast("Daily income from territory +$\(n * 150)")
            }
        }
    }

    // MARK: spawn manager

    func manageSpawns() {
        let pc = playerCenter
        let traffic = cars.filter { $0.mode == .traffic }.count
        if traffic < 18 { spawnTrafficCar(minD: 650, maxD: 1300) }
        let peds = units.filter { $0.kind == .ped }.count
        if peds < 26 { spawnPed(minD: 520, maxD: 900) }
        for u in units where !u.gone {
            let d = dist(u.pos, pc)
            if u.kind == .ped && d > 1000 { u.gone = true }
            if (u.kind == .cop || u.kind == .swat) && d > 1400 { u.gone = true }
        }
    }

    // MARK: HUD / camera

    func updateCamera(_ dt: CGFloat) {
        let c0 = playerCenter
        var look = CGVector.zero
        if let c = inCar { look = CGVector(dx: c.vel.dx * 0.30, dy: c.vel.dy * 0.30) }
        else if aimTouch != nil { look = CGVector(dx: aim.dx * 60, dy: aim.dy * 60) }
        let tgt = CGPoint(x: c0.x + look.dx, y: c0.y + look.dy)
        let k = min(1, dt * 6)
        var np = CGPoint(x: cam.position.x + (tgt.x - cam.position.x) * k, y: cam.position.y + (tgt.y - cam.position.y) * k)
        if shake > 0.1 {
            np.x += CGFloat.random(in: -shake...shake)
            np.y += CGFloat.random(in: -shake...shake)
            shake *= max(0, 1 - 8 * dt)
        }
        cam.position = np
        var spd: CGFloat = 0
        if let c = inCar { spd = hypot(c.vel.dx, c.vel.dy) }
        let ts = 0.78 + min(0.5, spd / 800)
        let s = cam.xScale + (ts - cam.xScale) * min(1, dt * 2)
        cam.setScale(s)
    }

    func updateHUD(_ dt: CGFloat) {
        hpFill.xScale = max(0, me.hp / 100)
        cashLabel.text = "$\(cash)"
        var st = ""
        for i in 0..<5 { st += i < stars ? "★" : "☆" }
        starsLabel.text = st
        if stars > 0 {
            let flick = seen ? (Int(clock * 6) % 2 == 0) : true
            starsLabel.fontColor = flick ? rgb(1, 0.85, 0.2) : rgb(0.3, 0.5, 1)
        } else {
            starsLabel.fontColor = UIColor.white
        }
        hurtFlash.alpha = max(0, hurtFlash.alpha - dt * 1.5)
        let w = weapons[weaponIdx]
        weaponBtn.label.text = w.short
        weaponLabel.text = w.name
        computeAction()
        actBtn.visible = actLabel != nil && !dead
        if let l = actLabel { actBtn.label.text = l }
        brakeBtn.visible = inCar != nil
        paintBtn.visible = inCar != nil && stars > 0
        bombBtn.visible = !underground
        var info = ""
        if let p = robbing { info = "ROBBERY \(Int(robT / 6 * 100))%  stay in marker!"; _ = p }
        else if raceOn { info = "RACE  checkpoint \(raceIdx + 1)/\(raceCPs.count)   \(Int(max(0, raceT)))s" }
        else if underground { info = "Sewers - heat is cooling down" }
        infoLabel.text = info
        // minimap
        mapContent.position = CGPoint(x: -me.pos.x * mapScale, y: -me.pos.y * mapScale)
        mapArrow.zRotation = inCar?.heading ?? me.heading
        var di = 0
        for c in cars where c.isCop && c.mode != .wreck && di < copDots.count {
            if dist(c.pos, me.pos) < 600 {
                copDots[di].position = CGPoint(x: c.pos.x * mapScale, y: c.pos.y * mapScale)
                copDots[di].isHidden = false
                di += 1
            }
        }
        for u in units where (u.kind == .cop || u.kind == .swat || u.kind == .heli) && di < copDots.count {
            if dist(u.pos, me.pos) < 600 {
                copDots[di].position = CGPoint(x: u.pos.x * mapScale, y: u.pos.y * mapScale)
                copDots[di].isHidden = false
                di += 1
            }
        }
        while di < copDots.count { copDots[di].isHidden = true; di += 1 }
        if let h = heliSpot { _ = h }
        // aim line
        let aiming = hypot(aim.dx, aim.dy) > 0.25 && !dead && !underground
        aimLine.isHidden = !aiming
        if aiming {
            aimLine.position = playerCenter
            aimLine.zRotation = aimAngle
        }
        if dead { wastedLabel.isHidden = false }
    }

    // MARK: main loop

    override func update(_ t: TimeInterval) {
        if !didSetup || me == nil { return }
        if lastT == 0 { lastT = t; return }
        var dt = CGFloat(t - lastT)
        lastT = t
        if dt > 0.05 { dt = 0.05 }
        if dt <= 0 { return }
        clock += dt
        crimeCD = max(0, crimeCD - dt)
        bombCD = max(0, bombCD - dt)
        fireCD = max(0, fireCD - dt)

        if dead {
            deadT -= dt
            if deadT <= 0 { respawn() }
        }

        let aimMag = hypot(aim.dx, aim.dy)
        if aimMag > 0.25 { aimAngle = atan2(aim.dy, aim.dx) }
        updatePlayerFoot(dt)
        if aimMag > 0.5 && aimTouch != nil && !dead && stunT <= 0 && !underground && fireCD <= 0 {
            fireCD = 1 / weapons[weaponIdx].rate
            playerFire()
        }
        if stunT > 0 && inCar != nil { stunT -= dt }

        updateCars(dt)
        updateUnits(dt)
        updateBullets(dt)
        updateBombs(dt)
        updateUnitCarHits()
        if let c = inCar { me.pos = c.pos }

        seenT -= dt
        if seenT <= 0 { seenT = 0.25; updateSeen() }
        manageHeat(dt)
        updateMissions(dt)
        mgrT -= dt
        if mgrT <= 0 { mgrT = 0.6; manageSpawns() }

        saveT += dt
        if saveT > 8 { saveT = 0; saveGame() }

        updateCamera(dt)
        updateHUD(dt)
    }
}
