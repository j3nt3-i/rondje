import SwiftUI

// The top of a goal: the runner from the app icon, running towards the big day.
// On a road, or over hills when you train for a trail. The ring behind them fills as you get closer.

struct GoalHero: View {
    let trail: Bool
    /// The part of your schedule that is behind you, 0...1.
    let progress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            // Standing still, the runner is caught mid-stride.
            GoalScene(trail: trail, progress: progress,
                      time: reduceMotion ? 0.11 : context.date.timeIntervalSinceReferenceDate)
        }
        .accessibilityHidden(true)
    }
}

/// One frame of the scene. Everything follows from the time, so it can also be drawn as a still.
struct GoalScene: View {
    let trail: Bool
    let progress: Double
    let time: Double

    var body: some View {
        Canvas { g, size in draw(&g, size) }
    }

    private let lime = Theme.accent

    private func draw(_ g: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let speed = h * 0.85                 // how fast the ground passes under the runner
        let runnerX = w * 0.72
        let base = h * (trail ? 0.80 : 0.78)  // where the feet land on flat ground

        // The ground under the runner. Flat on a road, rolling on a trail.
        func ground(_ x: Double, depth: Double = 1) -> Double {
            guard trail else { return base }
            let u = (x + time * speed * depth) / h
            return base - h * 0.085 * sin(u * 1.5) - h * 0.03 * sin(u * 3.7 + 1.3)
        }
        func ridge(_ y0: Double, _ amp: Double, _ depth: Double, _ seed: Double) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: h))
            for x in stride(from: 0.0, through: w + 6, by: 6) {
                let u = (x + time * speed * depth) / h
                let y = y0 - amp * (0.6 * sin(u * 1.7 + seed) + 0.4 * sin(u * 3.9 + seed * 2.3))
                p.addLine(to: CGPoint(x: x, y: y))
            }
            p.addLine(to: CGPoint(x: w, y: h))
            p.closeSubpath()
            return p
        }

        // A soft glow where the runner is heading.
        g.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
            Gradient(colors: [lime.opacity(0.16), .clear]),
            center: CGPoint(x: runnerX, y: h * 0.5), startRadius: 0, endRadius: h * 0.9))

        // The ring from the icon, as a sun on the horizon: it fills as the big day comes closer.
        let ringCenter = CGPoint(x: runnerX, y: h * 0.47)
        let radius = h * 0.38
        let ring = StrokeStyle(lineWidth: h * 0.06, lineCap: .round)
        g.stroke(Path(ellipseIn: CGRect(x: ringCenter.x - radius, y: ringCenter.y - radius, width: radius * 2, height: radius * 2)),
                 with: .color(lime.opacity(0.16)), style: ring)
        let part = min(max(progress, 0), 1)
        if part > 0.005 {
            var arc = Path()
            arc.addArc(center: ringCenter, radius: radius, startAngle: .degrees(-90),
                       endAngle: .degrees(-90 + 360 * part), clockwise: false)
            g.stroke(arc, with: .color(lime), style: ring)
        }

        if trail {
            // Hills, far and near. The far ones pass slower, which gives the depth.
            g.fill(ridge(h * 0.60, h * 0.20, 0.16, 0.4), with: .color(Color(white: 0.19)))
            g.fill(ridge(h * 0.72, h * 0.13, 0.4, 2.1), with: .color(Color(white: 0.14)))
            // The trail itself.
            var soil = Path()
            var top = Path()
            soil.move(to: CGPoint(x: 0, y: h))
            for x in stride(from: 0.0, through: w + 4, by: 4) {
                let point = CGPoint(x: x, y: ground(x))
                soil.addLine(to: point)
                if x == 0 { top.move(to: point) } else { top.addLine(to: point) }
            }
            soil.addLine(to: CGPoint(x: w, y: h))
            soil.closeSubpath()
            g.fill(soil, with: .color(Color(white: 0.05)))
            g.stroke(top, with: .color(lime.opacity(0.9)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            // Stones on the path, so you see it move.
            let gap = h * 0.42
            let shift = (time * speed).truncatingRemainder(dividingBy: gap)
            for x in stride(from: -shift, through: w + gap, by: gap) {
                let y = ground(x) + h * 0.07
                g.fill(Path(ellipseIn: CGRect(x: x, y: y, width: h * 0.05, height: h * 0.018)), with: .color(.white.opacity(0.16)))
            }
        } else {
            // A road seen from the side and a little from above: the far edge thin, the near edge wide.
            let far = base - h * 0.07
            g.fill(Path(CGRect(x: 0, y: far, width: w, height: h - far)), with: .linearGradient(
                Gradient(colors: [Color(white: 0.14), Color(white: 0.06)]),
                startPoint: CGPoint(x: 0, y: far), endPoint: CGPoint(x: 0, y: h)))
            g.stroke(Path { $0.move(to: CGPoint(x: 0, y: far)); $0.addLine(to: CGPoint(x: w, y: far)) },
                     with: .color(lime.opacity(0.55)), lineWidth: 1.5)
            // Three rows of stripes. The nearer the row, the bigger and faster: that is the depth.
            for (y, scale, opacity) in [(far + h * 0.025, 0.45, 0.22), (base + h * 0.075, 1.0, 0.55), (h * 0.985, 1.7, 0.85)] {
                let dash = h * 0.17 * scale, gap = h * 0.15 * scale, thick = h * 0.022 * scale
                let shift = (time * speed * scale).truncatingRemainder(dividingBy: dash + gap)
                for x in stride(from: -shift - dash, through: w + dash, by: dash + gap) {
                    var stripe = Path()
                    let lean = thick * 1.2 // leaning, as stripes on a floor do when you look along it
                    stripe.move(to: CGPoint(x: x + lean, y: y - thick / 2))
                    stripe.addLine(to: CGPoint(x: x + lean + dash, y: y - thick / 2))
                    stripe.addLine(to: CGPoint(x: x + dash, y: y + thick / 2))
                    stripe.addLine(to: CGPoint(x: x, y: y + thick / 2))
                    stripe.closeSubpath()
                    g.fill(stripe, with: .color(scale > 1.5 ? lime.opacity(opacity) : .white.opacity(opacity)))
                }
            }
        }

        // The runner.
        let unit = h * 0.215                       // one unit is about a lower leg
        let cycle = time * 2 * .pi * 1.45          // one full stride of both legs
        let footY = ground(runnerX)
        let slope = (ground(runnerX + 4) - ground(runnerX - 4)) / 8
        let bob = -0.05 * cos(cycle * 2)

        // A shadow on the ground, smaller when both feet are in the air.
        let shadowWidth = unit * (1.25 - 0.25 * abs(sin(cycle)))
        g.fill(Path(ellipseIn: CGRect(x: runnerX - shadowWidth / 2, y: footY - unit * 0.03, width: shadowWidth, height: unit * 0.16)),
               with: .color(.black.opacity(0.45)))

        var body = g
        body.translateBy(x: runnerX, y: footY)
        body.rotate(by: .radians(atan(slope) * 0.6)) // leaning into the hill
        let hip = CGPoint(x: 0, y: (-1.02 + bob) * unit)

        func from(_ p: CGPoint, _ angle: Double, _ length: Double) -> CGPoint {
            // Angle from straight down, forward is positive.
            CGPoint(x: p.x + sin(angle) * length * unit, y: p.y + cos(angle) * length * unit)
        }
        func limb(_ points: [CGPoint], _ color: Color, _ width: Double) {
            var p = Path()
            p.addLines(points)
            body.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width * unit, lineCap: .round, lineJoin: .round))
        }
        func leg(_ phase: Double, _ color: Color) {
            let thigh = 0.2 + 0.8 * sin(phase)
            // The knee folds while the leg swings forward and is almost straight on the ground.
            let bend = 0.25 + 1.4 * pow(max(0, cos(phase - 0.5)), 1.2)
            let knee = from(hip, thigh, 0.52)
            limb([hip, knee, from(knee, thigh - bend, 0.55)], color, 0.25)
        }
        let lean = 0.24
        let shoulder = from(hip, .pi - lean, 0.6)
        func arm(_ phase: Double, _ color: Color) {
            let upper = 0.1 - 0.85 * sin(phase)
            let elbow = from(shoulder, upper, 0.34)
            limb([shoulder, elbow, from(elbow, upper + 1.45, 0.32)], color, 0.2)
        }

        let behind = Color(white: 0.62)
        // The far arm and leg first, a shade darker, so the body has depth.
        arm(cycle + .pi, behind)
        leg(cycle + .pi, behind)
        limb([hip, shoulder], .white, 0.36)
        let head = from(shoulder, .pi - lean - 0.12, 0.42)
        body.fill(Path(ellipseIn: CGRect(x: head.x - 0.22 * unit, y: head.y - 0.22 * unit, width: 0.44 * unit, height: 0.44 * unit)),
                  with: .color(.white))
        leg(cycle, .white)
        arm(cycle, .white)
    }
}
