/// How much of a QR tier a card uses. The editor shows this live so the user
/// sees a card grow past the Lock Screen before it happens.
public struct Budget: Sendable, Equatable {
    /// The Lock Screen Live Activity is 160 pt tall; a version 10 symbol at
    /// medium error correction is the largest that scans there reliably.
    public static let lockScreenMaxVersion = 10
    /// The in-app full-screen code stays scannable to about version 25.
    public static let fullQRMaxVersion = 25
    public static let errorCorrection = QRCode.ErrorCorrection.medium

    public let bytes: Int
    public let characters: Int
    /// Smallest QR version that holds the URL form at medium correction, or
    /// nil past version 40.
    public let version: Int?

    public init(card: Card) {
        let url = HB1.url(for: card)
        bytes = HB1.encodedSize(of: card)
        characters = url.utf8.count
        version = QRCode.smallestVersion(for: QRSegment.segments(forURL: url), errorCorrection: Budget.errorCorrection)
    }

    public var fitsLockScreen: Bool { version.map { $0 <= Budget.lockScreenMaxVersion } ?? false }
    public var fitsFullQR: Bool { version.map { $0 <= Budget.fullQRMaxVersion } ?? false }

    /// The QR for a form, or nil when the card is too large for it.
    public static func qrCode(for card: Card, form: CardForm) throws -> QRCode? {
        let limit: Int
        switch form {
        case .lockScreen: limit = lockScreenMaxVersion
        case .fullQR: limit = fullQRMaxVersion
        case .file: return nil
        }
        let segments = QRSegment.segments(forURL: HB1.url(for: card))
        do {
            return try QRCode.encode(segments, errorCorrection: errorCorrection, maxVersion: limit)
        } catch QRError.dataTooLong {
            return nil
        }
    }
}
