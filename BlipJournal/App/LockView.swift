import LocalAuthentication
import SwiftUI

/// The whole app while `AppModel.isLocked`: `BlipJournalApp` shows this instead of
/// `RootView`, not over it. Offers device owner authentication (Face ID with passcode
/// fallback) on appear, and a retry button when that fails.
struct LockView: View {
    @Environment(AppModel.self) private var appModel
    @State private var phase: Phase = .idle

    private enum Phase: Equatable {
        case idle
        case authenticating
        case failed
        case noPasscode
    }

    /// The outcome of one authentication attempt, safe to hand back to the main actor.
    private enum Outcome: Sendable {
        case unlocked
        case failed
        case noPasscode
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Blip Journal")
                .font(.largeTitle.bold())
            content
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task { await authenticate() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .authenticating:
            ProgressView()
                .accessibilityLabel("Unlocking")
        case .failed:
            Text("Your journal is locked.")
                .foregroundStyle(.secondary)
            Button("Unlock") {
                Task { await authenticate() }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Unlock with Face ID or passcode")
        case .noPasscode:
            Text("Your device has no passcode. Blip Journal cannot protect your journal until you set one.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Continue anyway") {
                appModel.unlock()
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Continue without a passcode")
        }
    }

    private func authenticate() async {
        guard phase != .authenticating else { return }
        phase = .authenticating
        switch await Self.evaluateDeviceOwner() {
        case .unlocked:
            appModel.unlock()
        case .failed:
            phase = .failed
        case .noPasscode:
            phase = .noPasscode
        }
    }

    /// Runs the whole `LAContext` lifecycle off the main actor so the non-Sendable
    /// context never crosses an isolation boundary.
    private nonisolated static func evaluateDeviceOwner() async -> Outcome {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return DeviceAuthentication.hasNoPasscode(error) ? .noPasscode : .failed
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your journal.")
            return success ? .unlocked : .failed
        } catch {
            return .failed
        }
    }
}
