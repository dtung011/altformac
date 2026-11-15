import CoreGraphics

/// Physical (ANSI) key codes. KeyTips match keys, not typed characters, so keyboard layouts do not matter.
public enum KeyCodes {
    public static let escape: Int64 = 53
    public static let delete: Int64 = 51      // Backspace
    public static let optionLeft: Int64 = 58
    public static let optionRight: Int64 = 61

    private static let table: [(Character, Int64)] = [
        ("A", 0), ("S", 1), ("D", 2), ("F", 3), ("H", 4), ("G", 5), ("Z", 6), ("X", 7), ("C", 8), ("V", 9),
        ("B", 11), ("Q", 12), ("W", 13), ("E", 14), ("R", 15), ("Y", 16), ("T", 17),
        ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("9", 25), ("7", 26), ("8", 28), ("0", 29),
        ("O", 31), ("U", 32), ("I", 34), ("P", 35), ("L", 37), ("J", 38), ("K", 40), ("N", 45), ("M", 46)
    ]

    private static let byCode: [Int64: Character] = Dictionary(uniqueKeysWithValues: table.map { ($0.1, $0.0) })
    private static let byChar: [Character: Int64] = Dictionary(uniqueKeysWithValues: table)

    /// Letter or digit for a physical key code, or nil for any other key.
    public static func character(forKeyCode code: Int64) -> Character? { byCode[code] }

    public static func keyCode(for character: Character) -> Int64? {
        byChar[Character(String(character).uppercased())]
    }
}
