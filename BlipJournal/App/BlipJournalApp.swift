import SwiftUI

@main
struct OpenBlipApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var launch: Launch

    /// Either a working model or the reason there is none. Store errors at launch are
    /// fatal in v0: there is no recovery path, and hiding them would be worse.
    private enum Launch {
        case ready(AppModel)
        case failed(String)
    }

    init() {
        do {
            _launch = State(initialValue: .ready(try AppModel.live()))
        } catch {
            _launch = State(initialValue: .failed(String(describing: error)))
        }
    }

    var body: some Scene {
        WindowGroup {
            switch launch {
            case .ready(let appModel):
                // The lock replaces the content rather than covering it. A sheet or
                // dialog presented from inside RootView is presented above the whole
                // root view, so an overlay lock would leave it on screen and usable;
                // removing RootView tears its presentations down with it.
                Group {
                    if appModel.isLocked {
                        LockView()
                    } else {
                        RootView()
                    }
                }
                .environment(appModel)
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background:
                        appModel.didEnterBackground(at: Date())
                    case .active:
                        appModel.willEnterForeground(at: Date())
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
            case .failed(let message):
                LaunchFailureView(message: message)
                    .preferredColorScheme(.light)
            }
        }
    }
}

/// Full-screen report of a store error at launch.
struct LaunchFailureView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Blip Journal could not open its database")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
