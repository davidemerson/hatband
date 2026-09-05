import CoreGraphics
import Foundation
import HatbandCore
import SwiftUI
import UIKit

/// The three print forms of a code: SVG straight from the library, a
/// 1024-pixel PNG, and a PDF business card with the name and the
/// persona's colour band, all rendered on the phone.
nonisolated enum PrintExport {
    static let pngSide = 1024
    static let quietZone = 4
    /// 3.5 by 2 inches, in points.
    static let cardSize = CGSize(width: 252, height: 144)

    static func svg(_ code: QRCode) -> [UInt8] {
        Array(code.svg(moduleSize: 8, quietZone: quietZone).utf8)
    }

    static func png(_ code: QRCode) -> [UInt8]? {
        guard let image = cgImage(code), let data = UIImage(cgImage: image).pngData() else { return nil }
        return Array(data)
    }

    /// One page the size of a business card, drawn by `PrintCardView`
    /// into a PDF context.
    @MainActor static func pdf(code: QRCode, name: String?, company: String?, color: UInt8) -> [UInt8]? {
        guard let image = cgImage(code) else { return nil }
        let content = PrintCardView(qr: image, name: name, company: company, color: color)
            .frame(width: cardSize.width, height: cardSize.height)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(cardSize)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var box = CGRect(origin: .zero, size: cardSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
        }
        context.closePDF()
        return Array(Data(referencing: data))
    }

    /// Black modules on white with the quiet zone, scaled to `side`
    /// pixels, row 0 at the top.
    static func cgImage(_ code: QRCode, side: Int = pngSide) -> CGImage? {
        guard side > 0,
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setShouldAntialias(false)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(gray: 0, alpha: 1)
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: 1, y: -1)
        let module = CGFloat(side) / CGFloat(code.size + 2 * quietZone)
        for y in 0..<code.size {
            var x = 0
            while x < code.size {
                guard code.module(x: x, y: y) else {
                    x += 1
                    continue
                }
                var end = x
                while end < code.size, code.module(x: end, y: y) {
                    end += 1
                }
                let rect = CGRect(x: CGFloat(x + quietZone) * module, y: CGFloat(y + quietZone) * module,
                                  width: CGFloat(end - x) * module, height: module)
                context.fill(rect)
                x = end
            }
        }
        return context.makeImage()
    }
}

/// The printed card: the persona's colour band, name and company, and
/// the code. Always light, whatever the phone's appearance.
@MainActor struct PrintCardView: View {
    let qr: CGImage
    let name: String?
    let company: String?
    let color: UInt8

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Theme.personaColor(color))
                .frame(width: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(name ?? " ")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                if let company {
                    Text(company)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.35))
                }
                Spacer(minLength: 0)
                Text("hatband.link")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(white: 0.35))
            }
            .padding(12)
            Spacer(minLength: 0)
            Image(decorative: qr, scale: 1)
                .resizable()
                .interpolation(.none)
                .aspectRatio(1, contentMode: .fit)
                .padding(8)
        }
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
