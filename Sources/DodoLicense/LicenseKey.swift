/// License key text helpers.
public enum LicenseKey {
    /// A key as it was issued, from whatever the user pasted.
    ///
    /// Copying from a mail app can bring along invisible characters (zero-width spaces, soft
    /// hyphens) or turn the key's hyphens into en or em dashes. The store then answers "not
    /// found" for a key that's fine. This maps every kind of dash to `-` and keeps only ASCII
    /// letters, digits and `-`. `License.activate` already does this; use it yourself if you
    /// want to show the cleaned key in your text field.
    public static func clean(_ input: String) -> String {
        var key = ""
        for scalar in input.unicodeScalars {
            if isDash(scalar) {
                key.append("-")
            } else if scalar.isASCII, scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || scalar == "-" {
                key.unicodeScalars.append(scalar)
            }
        }
        return key
    }

    /// Hyphen, non-breaking hyphen, figure dash, en dash, em dash, horizontal bar (U+2010–2015)
    /// and the minus sign (U+2212).
    private static func isDash(_ scalar: Unicode.Scalar) -> Bool {
        (0x2010...0x2015).contains(scalar.value) || scalar.value == 0x2212
    }
}
