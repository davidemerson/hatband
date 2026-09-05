import CoreGraphics
import Foundation
import HatbandCore
import Testing
import UIKit
@testable import Hatband

@MainActor struct PrintExportTests {
    private func code() throws -> QRCode {
        try #require(try Budget.qrCode(for: try Vectors.card("typical-signed"), form: .fullQR))
    }

    /// Gray value of the pixel at the centre of module (x, y).
    private func gray(_ image: CGImage, x: Int, y: Int) throws -> UInt8 {
        let module = Double(image.width) / Double(try code().size + 2 * PrintExport.quietZone)
        let px = Int((Double(x + PrintExport.quietZone) + 0.5) * module)
        let py = Int((Double(y + PrintExport.quietZone) + 0.5) * module)
        let data = try #require(image.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        return bytes[py * image.bytesPerRow + px]
    }

    @Test func svgMatchesCore() throws {
        let qr = try code()
        let svg = PrintExport.svg(qr)
        #expect(svg == Array(qr.svg(moduleSize: 8, quietZone: 4).utf8))
        #expect(String(decoding: svg, as: UTF8.self).hasPrefix("<svg"))
    }

    @Test func pngIs1024() throws {
        let qr = try code()
        let bytes = try #require(PrintExport.png(qr))
        #expect(bytes.prefix(8) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let image = try #require(UIImage(data: Data(bytes)))
        #expect(image.cgImage?.width == 1024)
        #expect(image.cgImage?.height == 1024)
        // Every module of three rows matches the code, so the image is
        // neither flipped nor mirrored, and the quiet zone is white.
        let raw = try #require(PrintExport.cgImage(qr))
        #expect(raw.width == 1024)
        #expect(raw.bitsPerPixel == 8)
        for y in [0, 3, qr.size - 1] {
            for x in 0..<qr.size {
                #expect(try gray(raw, x: x, y: y) == (qr.module(x: x, y: y) ? 0 : 255), "module \(x),\(y)")
            }
        }
        #expect(try gray(raw, x: -2, y: -2) == 255)
        #expect(try gray(raw, x: qr.size + 1, y: qr.size + 1) == 255)
    }

    @Test func pdfHasHeader() throws {
        let qr = try code()
        let bytes = try #require(PrintExport.pdf(code: qr, name: "Leopold Bloom", company: "Freeman's Journal", color: 2))
        #expect(bytes.starts(with: Array("%PDF".utf8)))
        #expect(bytes.count > 500)
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let document = try #require(CGPDFDocument(provider))
        #expect(document.numberOfPages == 1)
        let page = try #require(document.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        #expect(box.width == PrintExport.cardSize.width)
        #expect(box.height == PrintExport.cardSize.height)
        #expect(PrintExport.pdf(code: qr, name: nil, company: nil, color: 0) != nil)
    }
}
