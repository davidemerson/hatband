/// A civil date reduced to days since 2020-01-01, the unit of `issuedDay`.
/// Proleptic Gregorian, no Foundation.
public enum Day {
    public static let epochYear = 2020

    /// Days from 2020-01-01 to the given date; negative before it.
    public static func number(year: Int, month: Int, day: Int) -> Int {
        daysFromCivil(year, month, day) - daysFromCivil(epochYear, 1, 1)
    }

    /// The date for a day number.
    public static func civil(_ number: Int) -> (year: Int, month: Int, day: Int) {
        civilFromDays(number + daysFromCivil(epochYear, 1, 1))
    }

    // Howard Hinnant's algorithms, days relative to 1970-01-01.
    private static func daysFromCivil(_ y: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y - 1 : y
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    private static func civilFromDays(_ z: Int) -> (Int, Int, Int) {
        let z = z + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
}
