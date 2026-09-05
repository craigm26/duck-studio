import Foundation

/// `statistics.mean`, which is not the same arithmetic as adding Doubles up.
///
/// WHY THIS EXISTS AT ALL. inspect-robots reduces a scene's epochs and
/// aggregates a scorer over scenes with Python's `statistics.mean`
/// (`scorer.py` `reduce_mean`, `eval.py`'s metrics block). That function does
/// not add floats. It converts every value to an exact rational, adds them with
/// no rounding whatsoever, divides by the count, and rounds ONCE at the end. A
/// running sum in Double rounds after every addition, and the two answers
/// disagree in the last unit in the last place often enough to be visible in a
/// published file: twelve scenes that each measured exactly 0.6405 summed and
/// divided in Double give 0.6405000000000001, and their library gives 0.6405.
///
/// A LAST PLACE DIGIT IS NOT A ROUNDING NICETY HERE. Both HTML reports round
/// for display, so the only place the difference survives is the JSON, which is
/// the artefact that goes to Hugging Face and gets diffed against a rerun. A
/// file that differs from the library's own arithmetic in its last digit is a
/// file somebody has to decide about, and `EvalEpochs` claims the five reducers
/// are theirs. This is what makes that claim true rather than nearly true.
///
/// HOW IT IS EXACT WITHOUT A RATIONAL TYPE. Every finite Double is already a
/// dyadic rational, `significand * 2^exponent` with a 53 bit integer
/// significand. Line them all up on the smallest exponent in the list and the
/// sum is one integer, exactly, however long that integer has to be. The
/// integer is divided by the count once, with the remainder kept as the sticky
/// bit, and the quotient is rounded to 53 bits the way the hardware would:
/// round to nearest, ties to even. One rounding, in the same place theirs is.
enum ExactMean {

    /// The mean of a list, rounded once. Nil for an empty list, which is what
    /// an all errored scene has.
    ///
    /// A NON FINITE VALUE FALLS BACK TO THE ORDINARY SUM, and that is a
    /// deliberate difference. `Fraction(float('inf'))` raises upstream, so
    /// there is no answer of theirs to match; a phone does not get to raise, and
    /// the writer already nulls a non finite metric and names the scorer
    /// (`EvalRun.nonFiniteScores`), so the honest thing is to carry the
    /// infinity or the nan through to the place that already handles it.
    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        guard values.allSatisfy({ $0.isFinite }) else {
            return values.reduce(0, +) / Double(values.count)
        }

        // The smallest exponent in the list is the common denominator: shifting
        // every significand up to it turns the whole sum into integer addition.
        var minExponent = Int.max
        for value in values where value != 0 {
            minExponent = Swift.min(minExponent, parts(value).exponent)
        }
        // Every value was a zero. Their `Fraction(-0.0)` is 0, so the mean of a
        // list of negative zeros is a positive zero there, and here.
        guard minExponent != Int.max else { return 0 }

        var positive = Big()
        var negative = Big()
        for value in values where value != 0 {
            let part = parts(value)
            let term = Big(part.significand).shiftedLeft(by: part.exponent - minExponent)
            if part.negative { negative.add(term) } else { positive.add(term) }
        }

        let isNegative = positive.compare(negative) < 0
        let magnitude = isNegative ? negative.subtracting(positive)
                                   : positive.subtracting(negative)
        // Exact cancellation. `Fraction` has no signed zero, so neither has
        // this: their float(Fraction(0)) is +0.0.
        guard !magnitude.isZero else { return 0 }

        let count = UInt64(values.count)
        // Shift before dividing so the quotient always carries more than the
        // 53 bits a Double keeps, whatever the list was: 128 bits of headroom
        // against a count that cannot be wider than 64.
        let shift = 128
        let (quotient, remainder) = magnitude.shiftedLeft(by: shift).dividing(by: count)

        // value = quotient * 2^scale, plus remainder/count of the last unit,
        // which is the sticky bit and nothing more.
        var scale = minExponent - shift
        let width = quotient.bitWidth
        var keep: UInt64
        if width > 53 {
            let drop = width - 53
            keep = quotient.bits(from: drop, count: 53)
            let roundBit = quotient.bit(at: drop - 1)
            let sticky = quotient.anyBit(below: drop - 1) || remainder != 0
            if roundBit, sticky || keep & 1 == 1 { keep += 1 }
            scale += drop
        } else {
            // Unreachable with the shift above, and written out anyway because
            // a rounding path that exists only in someone's head is the one
            // that is wrong when the shift changes. Nothing was dropped, so the
            // only thing to round on is the leftover fraction, compared with a
            // half as `remainder` against `count - remainder` so that doubling
            // it cannot overflow.
            keep = quotient.bits(from: 0, count: 53)
            let rest = count - remainder
            if remainder > rest { keep += 1 }
            else if remainder == rest, remainder != 0, keep & 1 == 1 { keep += 1 }
        }
        // Rounding up out of 53 bits lands on a power of two, which is one bit
        // wider and exactly representable one place along.
        if keep == 1 << 53 {
            keep >>= 1
            scale += 1
        }
        let value = Double(sign: .plus, exponent: scale, significand: Double(keep))
        return isNegative ? -value : value
    }

    /// A finite Double taken apart exactly: `significand * 2^exponent`, with
    /// the hidden bit put back for a normal number and left off for a
    /// subnormal one.
    static func parts(_ value: Double) -> (negative: Bool, significand: UInt64, exponent: Int) {
        let bits = value.bitPattern
        let negative = bits >> 63 == 1
        let rawExponent = Int((bits >> 52) & 0x7FF)
        let mantissa = bits & 0x000F_FFFF_FFFF_FFFF
        if rawExponent == 0 { return (negative, mantissa, -1074) }
        return (negative, mantissa | (1 << 52), rawExponent - 1075)
    }
}

/// The smallest unsigned big integer that does this job: add, subtract, shift
/// left, divide by one word, and read bits out.
///
/// NO GENERAL PURPOSE ARITHMETIC LIVES HERE. There is no multiplication and no
/// long division, because the sum of a list of Doubles needs neither, and every
/// operation that is here is the one `ExactMean` calls. A big integer type with
/// more surface than its caller uses is a type with untested corners in it.
struct Big {

    /// Little endian, and never with a zero on the top: the width of a number
    /// is read off the top word, so a trailing zero would make the same value
    /// answer two different widths.
    private(set) var words: [UInt64] = []

    var isZero: Bool { words.isEmpty }

    init() {}

    init(_ value: UInt64) {
        if value != 0 { words = [value] }
    }

    var bitWidth: Int {
        guard let top = words.last else { return 0 }
        return (words.count - 1) * 64 + (64 - top.leadingZeroBitCount)
    }

    private mutating func trim() {
        while let last = words.last, last == 0 { words.removeLast() }
    }

    mutating func add(_ other: Big) {
        let width = Swift.max(words.count, other.words.count)
        words.reserveCapacity(width + 1)
        while words.count < width { words.append(0) }
        var carry: UInt64 = 0
        for index in 0..<width {
            let rhs = index < other.words.count ? other.words[index] : 0
            let (once, firstOverflow) = words[index].addingReportingOverflow(rhs)
            let (twice, secondOverflow) = once.addingReportingOverflow(carry)
            words[index] = twice
            carry = (firstOverflow ? 1 : 0) + (secondOverflow ? 1 : 0)
        }
        if carry != 0 { words.append(carry) }
    }

    /// Only ever called with `self` the larger of the two, which is what the
    /// comparison above it is for.
    func subtracting(_ other: Big) -> Big {
        var out = self
        var borrow: UInt64 = 0
        for index in 0..<out.words.count {
            let rhs = index < other.words.count ? other.words[index] : 0
            let (once, firstUnderflow) = out.words[index].subtractingReportingOverflow(rhs)
            let (twice, secondUnderflow) = once.subtractingReportingOverflow(borrow)
            out.words[index] = twice
            borrow = (firstUnderflow ? 1 : 0) + (secondUnderflow ? 1 : 0)
        }
        out.trim()
        return out
    }

    /// -1, 0 or 1, the way a comparator reads.
    func compare(_ other: Big) -> Int {
        if words.count != other.words.count {
            return words.count < other.words.count ? -1 : 1
        }
        var index = words.count - 1
        while index >= 0 {
            if words[index] != other.words[index] {
                return words[index] < other.words[index] ? -1 : 1
            }
            index -= 1
        }
        return 0
    }

    func shiftedLeft(by bits: Int) -> Big {
        guard !isZero, bits > 0 else { return self }
        let wholeWords = bits / 64
        let offset = bits % 64
        var out = [UInt64](repeating: 0, count: wholeWords)
        out.reserveCapacity(wholeWords + words.count + 1)
        if offset == 0 {
            out.append(contentsOf: words)
        } else {
            var carry: UInt64 = 0
            for word in words {
                out.append((word << offset) | carry)
                carry = word >> (64 - offset)
            }
            if carry != 0 { out.append(carry) }
        }
        var big = Big()
        big.words = out
        big.trim()
        return big
    }

    /// Divide by one word, top down. `dividingFullWidth` is exactly this step,
    /// and its precondition holds by construction: the remainder carried into
    /// the next word is always smaller than the divisor.
    func dividing(by divisor: UInt64) -> (quotient: Big, remainder: UInt64) {
        var quotient = [UInt64](repeating: 0, count: words.count)
        var remainder: UInt64 = 0
        var index = words.count - 1
        while index >= 0 {
            let (part, left) = divisor.dividingFullWidth((high: remainder, low: words[index]))
            quotient[index] = part
            remainder = left
            index -= 1
        }
        var big = Big()
        big.words = quotient
        big.trim()
        return (big, remainder)
    }

    func bit(at index: Int) -> Bool {
        guard index >= 0 else { return false }
        let word = index / 64
        guard word < words.count else { return false }
        return (words[word] >> UInt64(index % 64)) & 1 == 1
    }

    /// Whether anything at all is set below a bit, which is the sticky bit of
    /// a rounding.
    func anyBit(below index: Int) -> Bool {
        guard index > 0 else { return false }
        let wholeWords = index / 64
        let offset = index % 64
        for position in 0..<Swift.min(wholeWords, words.count) where words[position] != 0 {
            return true
        }
        if offset > 0, wholeWords < words.count {
            let mask = (UInt64(1) << UInt64(offset)) - 1
            if words[wholeWords] & mask != 0 { return true }
        }
        return false
    }

    /// A window of bits as one word. Never asked for more than the 53 a Double
    /// keeps, so the bit at a time loop costs nothing worth optimising.
    func bits(from index: Int, count: Int) -> UInt64 {
        var out: UInt64 = 0
        for offset in 0..<count where bit(at: index + offset) {
            out |= UInt64(1) << UInt64(offset)
        }
        return out
    }
}
