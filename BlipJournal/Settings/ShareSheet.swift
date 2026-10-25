import SwiftUI
import UIKit

extension View {
    /// Presents the system share sheet for `url` while it is non-nil and clears it when
    /// the sheet ends. `onEnd` gets whether the person completed an action such as saving;
    /// it can run more than once for one sheet, so it must be idempotent.
    func shareSheet(url: Binding<URL?>, onEnd: @escaping (_ completed: Bool) -> Void) -> some View {
        sheet(isPresented: Binding(get: { url.wrappedValue != nil }, set: { if !$0 { url.wrappedValue = nil; onEnd(false) } })) {
            if let shared = url.wrappedValue { ActivityView(url: shared) { onEnd($0); url.wrappedValue = nil } }
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let url: URL; let completion: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIActivityViewController { let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil); controller.completionWithItemsHandler = { _, completed, _, _ in context.coordinator.finish(completed) }; return controller }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: UIActivityViewController, coordinator: Coordinator) { coordinator.finish(false); controller.completionWithItemsHandler = nil }

    final class Coordinator {
        private let completion: (Bool) -> Void
        private var didFinish = false
        init(completion: @escaping (Bool) -> Void) { self.completion = completion }
        func finish(_ completed: Bool) { guard !didFinish else { return }; didFinish = true; completion(completed) }
    }
}
