/// The id of a commit no `id:` names, as Pele makes it up: the commit's place in the graph, a hyphen and seven
/// hexadecimal digits (`3-1c6f6a1`). Mermaid takes the digits at random; Pele derives them from the place, so that the
/// same text always gives the same ids, and so does this.
enum GitGraphCommitIdentifier {
    /// The multiplier of Knuth's multiplicative hash, 2³² divided by the golden ratio, which spreads the places' bits.
    static let hashMultiplier: UInt32 = 0x9E37_79B1
    /// The digits a 32-bit hash is written in, and those an id keeps.
    static let hashDigitCount = 8
    static let digitCount = 7

    /// The id of the commit at `sequenceNumber` (0 for the first commit), the first of Pele's candidates that `isTaken`
    /// does not refuse: each next candidate adds the multiplier to the hashed number, in 32-bit arithmetic.
    static func generated(sequenceNumber: Int, isTaken: (String) -> Bool) -> String {
        var salt = UInt32(truncatingIfNeeded: sequenceNumber + 1)
        while true {
            let hexadecimal = String(salt &* hashMultiplier, radix: 16)
            let padded = String(repeating: "0", count: hashDigitCount - hexadecimal.count) + hexadecimal
            let identifier = "\(sequenceNumber)-\(padded.prefix(digitCount))"
            if !isTaken(identifier) { return identifier }
            salt &+= hashMultiplier
        }
    }
}
