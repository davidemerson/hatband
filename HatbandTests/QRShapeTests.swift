import CoreGraphics
import HatbandCore
import SwiftUI
import Testing
@testable import Hatband

struct QRShapeTests {
    private func code() throws -> QRCode {
        try #require(CardQR.code(for: try Vectors.url("compact-two-channels"), form: .lockScreen))
    }

    /// Horizontal runs of dark modules, counted the slow way.
    private func runCount(_ code: QRCode) -> Int {
        var runs = 0
        for y in 0..<code.size {
            var inRun = false
            for x in 0..<code.size {
                let dark = code.module(x: x, y: y)
                if dark, !inRun {
                    runs += 1
                }
                inRun = dark
            }
        }
        return runs
    }

    private func moves(_ path: Path) -> [CGPoint] {
        var points: [CGPoint] = []
        path.forEach { element in
            if case .move(let point) = element {
                points.append(point)
            }
        }
        return points
    }

    @Test func pathStaysInsideRect() throws {
        let code = try code()
        let rect = CGRect(x: 10, y: 20, width: 150, height: 150)
        let path = QRShape(code: code).path(in: rect)
        #expect(!path.isEmpty)
        #expect(rect.insetBy(dx: -0.001, dy: -0.001).contains(path.boundingRect))
        // The quiet zone keeps the first run off the edge.
        let first = try #require(moves(path).first)
        #expect(first.x > rect.minX)
        #expect(first.y > rect.minY)
    }

    @Test func rectCountEqualsRunCount() throws {
        let code = try code()
        let path = QRShape(code: code).path(in: CGRect(x: 0, y: 0, width: 200, height: 200))
        #expect(moves(path).count == runCount(code))
        var closes = 0
        path.forEach { element in
            if case .closeSubpath = element {
                closes += 1
            }
        }
        #expect(closes == runCount(code))
    }

    @Test func moduleUsesShorterSide() throws {
        let code = try code()
        let quietZone = 2
        let shape = QRShape(code: code, quietZone: quietZone)
        let module = CGFloat(100) / CGFloat(code.size + 2 * quietZone)

        let wide = shape.path(in: CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(wide.boundingRect.maxX <= 100.001)
        #expect(wide.boundingRect.maxY <= 100.001)
        let tall = shape.path(in: CGRect(x: 0, y: 0, width: 100, height: 200))
        #expect(tall.boundingRect.maxX <= 100.001)
        #expect(tall.boundingRect.maxY <= 100.001)
        #expect(abs(wide.boundingRect.width - tall.boundingRect.width) < 0.001)

        // The first run is the top row of the finder pattern: seven modules
        // starting after the quiet zone, one module tall.
        let first = try #require(moves(wide).first)
        #expect(abs(first.x - CGFloat(quietZone) * module) < 0.001)
        #expect(abs(first.y - CGFloat(quietZone) * module) < 0.001)
        let corners = firstSubpathPoints(wide)
        let maxX = try #require(corners.map { $0.x }.max())
        let maxY = try #require(corners.map { $0.y }.max())
        #expect(abs(maxX - CGFloat(quietZone + 7) * module) < 0.001)
        #expect(abs(maxY - CGFloat(quietZone + 1) * module) < 0.001)
    }

    /// Every point of the first closed subpath, whatever order `addRect` emits.
    private func firstSubpathPoints(_ path: Path) -> [CGPoint] {
        var points: [CGPoint] = []
        var closed = false
        path.forEach { element in
            guard !closed else { return }
            switch element {
            case .move(let point), .line(let point):
                points.append(point)
            case .closeSubpath:
                closed = true
            default:
                break
            }
        }
        return points
    }
}
