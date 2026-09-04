/// Hard caps for one form of a card. A value over its cap is rejected, never
/// truncated: truncation could split a URL or hide a warning. Text caps are
/// UTF-8 bytes, the unit every budget is measured in.
public struct Limits: Sendable {
    /// CBOR bytes of the whole card.
    public var payloadBytes: Int
    public var name = 64
    public var company = 64
    /// RFC 5321 §4.5.3.1: a 256-octet path less its angle brackets.
    public var email = 254
    /// `+` and the fifteen digits E.164 allows.
    public var phone = 16
    public var website = 128
    /// GitHub, LinkedIn, Mastodon and Calendly identifiers.
    public var handle = 64
    public var signalURL = 128
    public var customFields: Int
    public var customLabel = 24
    public var customValue: Int
    public var customKinds: Set<CustomKind> = Set(CustomKind.allCases)
    /// Zero means the form never carries one.
    public var photoBytes: Int
    public var gpgKeyBytes: Int
    /// Container depth: the card map, the custom array, one field triple.
    public var nesting = 3

    public init(payloadBytes: Int, customFields: Int, customValue: Int, photoBytes: Int, gpgKeyBytes: Int) {
        self.payloadBytes = payloadBytes
        self.customFields = customFields
        self.customValue = customValue
        self.photoBytes = photoBytes
        self.gpgKeyBytes = gpgKeyBytes
    }

    /// A QR code. Version 40-L holds 2,953 bytes; real cards stay far below.
    public static let qr = Limits(payloadBytes: 2_953, customFields: 8, customValue: 128, photoBytes: 0, gpgKeyBytes: 0)

    /// A `.hatband` file or URL share: 32 KB in all, so every card fits a URL.
    public static let file = Limits(payloadBytes: 32_768, customFields: 32, customValue: 1024, photoBytes: 16_384, gpgKeyBytes: 24_576)
}
