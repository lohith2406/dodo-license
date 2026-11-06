import Testing
@testable import DodoLicense

@Suite("Cleaning pasted keys")
struct LicenseKeyTests {
    @Test(arguments: [
        ("ABCD-1234-EFGH", "ABCD-1234-EFGH"),
        ("  ABCD-1234\n", "ABCD-1234"),
        ("ABCD\u{2013}1234\u{2014}EFGH", "ABCD-1234-EFGH"),   // en and em dashes from a mail app
        ("ABCD\u{2010}1234\u{2212}EFGH", "ABCD-1234-EFGH"),   // hyphen and minus sign
        ("AB\u{200B}CD-12\u{00AD}34", "ABCD-1234"),           // zero-width space, soft hyphen
        ("2b1f8e2d-c41e-4e8f", "2b1f8e2d-c41e-4e8f"),         // lower case is kept
        ("\u{FEFF}ABCD-1234", "ABCD-1234"),                   // byte order mark
    ])
    func keysAreReturnedAsIssued(pasted: String, expected: String) {
        #expect(LicenseKey.clean(pasted) == expected)
    }
}
