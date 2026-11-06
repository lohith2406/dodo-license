import DodoLicense
import SwiftUI

/// Try every screen with MockProvider: VALID-1 activates, REFUNDED-1 activates and is revoked
/// on the next recheck, USED-1 is in use elsewhere, anything else isn't found.
///
/// To try a real Dodo test-mode key instead, swap the provider for
/// `License(productID: "pdt_…", environment: .test)`.
@main
struct LicenseDemoApp: App {
    @State private var license = License(provider: MockProvider(), keychainService: "LicenseDemo.license")
    @State private var trial = Trial(keychainService: "LicenseDemo.trial")

    init() {
        // `swift run` starts a bare executable, not an .app bundle, and macOS won't give its
        // window the keyboard unless it's made a regular app.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup("DodoLicense demo") {
            LicenseView(license: license, trial: trial)
                .task {
                    license.onRevoke = { print("The license was revoked. Tell the user here.") }
                    license.start()
                }
        }
        .windowResizability(.contentSize)
    }
}

struct LicenseView: View {
    let license: License
    let trial: Trial

    @State private var key = ""
    @State private var error: LicenseError?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch license.state {
            case .active(let key):
                Label("Licensed", systemImage: "checkmark.seal.fill").font(.title2.bold())
                Text(key).font(.body.monospaced()).foregroundStyle(.secondary)
                Button("Deactivate on this Mac", action: deactivate)
            case .unlicensed:
                Text(trial.hasEnded ? "Your trial has ended" : "\(trial.daysLeft) days left in your trial")
                    .font(.title2.bold())
                TextField("License key", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onSubmit(activate)
                Button("Activate", action: activate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.isEmpty)
            }
            if let error {
                Text(error.localizedDescription)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)   // wrap in full, never "…"
            }
            if license.isWorking {
                ProgressView().controlSize(.small)
            }
        }
        .disabled(license.isWorking)
        .padding(28)
        .frame(width: 420)
    }

    private func activate() {
        error = nil
        Task {
            do throws(LicenseError) { try await license.activate(key) } catch { self.error = error }
        }
    }

    private func deactivate() {
        error = nil
        Task {
            do throws(LicenseError) { try await license.deactivate() } catch { self.error = error }
        }
    }
}
