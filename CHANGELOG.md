# Changelog

## 0.1.0

First version.

- `License`: activate, deactivate, daily rechecks, offline use, revocation callback.
- `DodoProvider` for Dodo Payments' public license endpoints, test and live.
- `MockProvider` for building license screens without a key.
- `Trial`: an optional free trial that survives reinstalls and clock changes.
- `LicenseKey.clean(_:)` for keys pasted from emails.
- Accepts keys for several products (`productIDs:`).
- A 403 HTML page from Dodo's edge (a firewall block) is an error, not "key inactive" or
  "already deactivated".
- A Keychain that can't be read is no longer treated as "no license".
