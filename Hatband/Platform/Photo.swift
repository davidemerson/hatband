import CoreGraphics
import Foundation
import UIKit

/// The headshot: a JPEG at most 256 pixels on a side and 12 288 bytes,
/// with no APP1 (Exif), other APPn or COM segments, so nothing about the
/// camera, the place or the time rides in a card.
nonisolated enum Photo {
    static let maxSide = 256
    static let maxBytes = 12_288
    /// Aimed at before the cap is. A photo is the largest thing a card can
    /// carry, and every byte of it is Base32'd into the link and the QR, so
    /// the smallest one that still looks like a face is the right one.
    static let preferredBytes = 6_144

    /// Nil when the data is not an image or no size and quality fit the cap.
    /// Full size is tried against the smaller budget first, so a face stays
    /// 256 pixels and simply loses some quality rather than being halved.
    @MainActor static func thumbnailJPEG(from data: Data) -> [UInt8]? {
        guard let image = UIImage(data: data) else { return nil }
        if let small = fitting(scaled(image, maxSide: maxSide), within: preferredBytes) {
            return small
        }
        var side = maxSide
        while side >= 32 {
            if let jpeg = fitting(scaled(image, maxSide: side), within: maxBytes) {
                return jpeg
            }
            side /= 2
        }
        return nil
    }

    /// The best quality of this image that fits `budget`, stripped.
    @MainActor private static func fitting(_ image: UIImage, within budget: Int) -> [UInt8]? {
        for quality in [0.8, 0.65, 0.5, 0.35, 0.2] as [CGFloat] {
            guard let jpeg = image.jpegData(compressionQuality: quality) else { return nil }
            let stripped = strippingMetadata(Array(jpeg))
            if stripped.count <= budget {
                return stripped
            }
        }
        return nil
    }

    /// The JPEG without its APP1 to APP15 and COM segments. APP0 (JFIF)
    /// stays; everything from the start of scan on is copied as it is.
    /// Anything that is not a JPEG comes back unchanged.
    static func strippingMetadata(_ jpeg: [UInt8]) -> [UInt8] {
        guard jpeg.count >= 4, jpeg[0] == 0xFF, jpeg[1] == 0xD8 else { return jpeg }
        var out: [UInt8] = [0xFF, 0xD8]
        var index = 2
        while index + 3 < jpeg.count, jpeg[index] == 0xFF {
            let marker = jpeg[index + 1]
            if marker == 0xDA {
                break
            }
            if marker == 0xFF {
                index += 1
                continue
            }
            if marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8) {
                out.append(contentsOf: jpeg[index..<(index + 2)])
                index += 2
                continue
            }
            let length = Int(jpeg[index + 2]) << 8 | Int(jpeg[index + 3])
            guard length >= 2, index + 2 + length <= jpeg.count else { return jpeg }
            let dropped = (marker >= 0xE1 && marker <= 0xEF) || marker == 0xFE
            if !dropped {
                out.append(contentsOf: jpeg[index..<(index + 2 + length)])
            }
            index += 2 + length
        }
        out.append(contentsOf: jpeg[index...])
        return out
    }

    /// Drawn through UIKit, so the orientation is baked into the pixels.
    @MainActor private static func scaled(_ image: UIImage, maxSide: Int) -> UIImage {
        let width = image.size.width
        let height = image.size.height
        let longest = max(width, height)
        guard longest > 0 else { return image }
        let factor = min(1, CGFloat(maxSide) / longest)
        let target = CGSize(width: max(1, (width * factor).rounded()), height: max(1, (height * factor).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
