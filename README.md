# DodoLicense

[![CI](https://github.com/lohith2406/dodo-license/actions/workflows/ci.yml/badge.svg)](https://github.com/lohith2406/dodo-license/actions/workflows/ci.yml)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
[![MIT License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Follow @xLohith on X](https://img.shields.io/badge/follow-%40xLohith-000000?logo=x&logoColor=white)](https://x.com/xLohith)

License keys for Mac apps sold through [Dodo Payments](https://dodopayments.com). For indie
developers who want a paid Mac app without writing the licensing part themselves.

Dodo's license endpoints are three small HTTP calls. A Mac app needs more than the calls, and
this package is that part.

**Unofficial.** Not made by or affiliated with Dodo Payments.

- Activate a key on this Mac, and free it to move to another one
- Works offline for as long as needed, with no grace period that locks people out
- Rechecks daily; only a clear answer from Dodo (a refund, a disabled key) turns it off
- Keeps the key in the Keychain, with test and live keys apart
- Errors come with a sentence you can show the user as is
- An optional free trial that survives reinstalls and clock changes
- `MockProvider` to build your license screens before you have a key
- No dependencies, and no secret API key in your app

Requirements: macOS 14+, Swift 6.2 (Xcode 26).

## Install

In Xcode: **File → Add Package Dependencies…** and paste
`https://github.com/lohith2406/dodo-license`.

Or in `Package.swift`:

```swift
.package(url: "https://github.com/lohith2406/dodo-license", from: "0.1.0")
```

## Quickstart

Start with the mock store, which needs no Dodo account and no network:

```swift
import DodoLicense

let license = License(provider: MockProvider())
license.start()

try await license.activate("VALID-1234")
license.isActive   // true
```

When your screens work, switch to your Dodo product. Nothing else changes:

```swift
let license = License(productID: "pdt_…", environment: .test)   // .live in release builds
```

See [Mock keys](#mock-keys) for keys that act out each failure.

## Set up Dodo

1. In the Dodo dashboard, create a **License Key** entitlement and attach it to your product.
   The activation limit is how many Macs a key can be on at once; 1 means one Mac per purchase
   (see [When a user gets stuck](#when-a-user-gets-stuck) before choosing 1). Dodo then emails a key with every
   purchase.
2. Copy the product's ID (`pdt_…`).
3. While developing, use a test-mode product and `environment: .test`. Test keys only work
   against the test server.

The license endpoints are public and need no API key, so nothing secret ships in your app.

## Use

```swift
@MainActor
final class AppModel {
    let license = License(productID: "pdt_…", environment: .live)

    func launch() {
        license.onRevoke = {
            // Refunded, expired or deactivated on the web. Tell the user.
        }
        license.start()   // asks Dodo once a day has passed since the last good check
    }
}
```

`License` is `@Observable`, so SwiftUI views update on their own:

```swift
struct ActivateView: View {
    let license: License
    @State private var key = ""
    @State private var error: LicenseError?

    var body: some View {
        Form {
            TextField("License key", text: $key)
            Button("Activate") {
                Task {
                    do throws(LicenseError) { try await license.activate(key) }
                    catch { self.error = error }
                }
            }
            .disabled(license.isWorking)
            if let error { Text(error.localizedDescription).foregroundStyle(.red) }
        }
    }
}
```

Every `LicenseError` has a sentence you can show as is, such as "That key is already in use
on another Mac. Deactivate it there, then try again."

To move to another Mac, call `try await license.deactivate()` on the old one.

Sell the same app as more than one product (say, lifetime and a discounted plan, both with
the license key entitlement)? Pass all of them:
`License(productIDs: ["pdt_lifetime", "pdt_discount"], environment: .live)`.

## Ship checklist

The steps that are easy to miss when adding this to an app:

1. Use a test-mode product with `environment: .test` while developing, and the live product
   with `.live` in release builds (for example with `#if DEBUG`).
2. Call `license.start()` once at launch, so rechecks happen.
3. Gate the app on `license.isActive` (or `license.isActive || !trial.hasEnded` with a trial).
4. Set `license.onRevoke` to tell the user why the app locked.
5. Put a **Deactivate** button in Settings, so users can move to a new Mac on their own.
6. Show a way to contact you. "In use on another Mac" for a Mac they no longer have can only
   be fixed by you, in the Dodo dashboard (see below).
7. Link to your Dodo checkout from the locked state.

## How it behaves

- **Offline:** stays licensed, for as long as needed. There's no grace period that locks out
  someone on a plane.
- **Rechecks:** it looks every hour and asks Dodo once a day has passed since the last good
  check. Only a clear answer from Dodo turns the license off: the key was refunded, expired,
  or deactivated on the web. A server error, a rate limit, a firewall page or no connection
  change nothing.
- **A locked Keychain** (or a denied access prompt) isn't treated as "no license". Nothing is
  deleted, and the license comes back once the Keychain can be read.
- **Keys for other products** are refused, and the activation they used is given back.
- **If the Keychain won't save the key,** the activation is given back too, so the key isn't
  left used up with nothing on the Mac to free it.
- **Pasted keys are cleaned:** invisible characters removed, every kind of dash turned into
  `-`. `LicenseKey.clean(_:)` is public if you want it for your text field.
- **Test and live keys are kept apart** in the Keychain, so a test key from a debug build
  never shows up in a release build.
- **A clock set ahead** doesn't postpone rechecks.

## When a user gets stuck

These come up with real buyers; plan for them before you ship.

- **"Already in use on another Mac", but they don't have it any more.** The old Mac died, was
  wiped, or an activation's answer got lost on a bad connection. Your app can't list or free
  activations (that needs your secret API key), so you free it: in the Dodo dashboard, open the
  customer's license key and remove the old activation. The error message tells the user to
  contact support, so make sure your app shows a way to reach you. Setting the activation limit
  to 2 instead of 1 makes this rarer.
- **The key "wasn't found" right after buying.** Usually a copying problem. Pasted keys are
  already cleaned, so check that they used the key from the purchase email, and the live build
  rather than a test one.
- **Keychain access was denied.** macOS ties Keychain items to the app's code signature, so an
  app re-signed differently (an unsigned or ad-hoc build) may be asked for access. Ship builds
  signed the same way each release.

## Free trial (optional)

```swift
let trial = Trial()   // 7 days from first launch

var canUseApp: Bool { license.isActive || !trial.hasEnded }

if trial.isEndingSoon { /* remind once */ }
Text("\(trial.daysLeft) days left")
```

The start date lives in the Keychain, so reinstalling doesn't restart the trial, and setting
the clock back doesn't add days. It stops casual restarts, not determined people: deleting the
Keychain item resets it.

## Mock keys

`MockProvider` pretends to be the store. What a key does depends on how it starts:

| Key starts with | What happens |
|---|---|
| `VALID-` | activates and stays valid |
| `REFUNDED-` | activates, then the next recheck revokes it |
| `USED-` | "already in use on another Mac" |
| `INACTIVE-` | "no longer active" |
| `OTHER-` | "for a different app" |
| anything else | "wasn't found" |

`MockProvider(isOffline: true)` shows your offline states. `Examples/LicenseDemo` is a small
app that uses it: `cd Examples/LicenseDemo && swift run`.

## What it doesn't do

- Take payments. Link to your Dodo checkout for that.
- Subscriptions, seats or copy protection.
- iOS. On the App Store, StoreKit handles purchases.

---

<sub>[MIT License](LICENSE) · Built by [@xLohith](https://x.com/xLohith)</sub>
