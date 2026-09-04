/// The outcome of a check on scanned input. A warning keeps the value and
/// tells the user why it looks off; a rejection drops it before any UI
/// touches it. Nothing is ever silently repaired.
public enum Verdict: Equatable, Sendable {
    case ok
    case warning(String)
    case reject(String)

    /// Kept, with or without a warning.
    public var isAccepted: Bool {
        if case .reject = self { return false }
        return true
    }

    /// The more severe of the two; two warnings keep both messages.
    public func merged(with other: Verdict) -> Verdict {
        switch (self, other) {
        case (.reject, _): return self
        case (_, .reject): return other
        case (.warning(let a), .warning(let b)): return .warning(a + "; " + b)
        case (.warning, .ok): return self
        case (.ok, _): return other
        }
    }
}
