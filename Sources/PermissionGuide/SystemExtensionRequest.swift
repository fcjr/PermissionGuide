import Foundation
import SystemExtensions

/// Wraps `OSSystemExtensionRequest` with a closure-based delegate. Keeps itself alive
/// until the request finishes.
package final class SystemExtensionRequest: NSObject, OSSystemExtensionRequestDelegate, @unchecked Sendable {
    // Only created and consumed on the main queue.
    package enum Event: @unchecked Sendable {
        case needsUserApproval
        case activated
        case properties([OSSystemExtensionProperties])
        case failed(any Error)
    }

    private let handler: @MainActor (Event) -> Void
    private var retainedSelf: SystemExtensionRequest?

    private init(handler: @escaping @MainActor (Event) -> Void) {
        self.handler = handler
    }

    @MainActor
    package static func activate(_ identifier: String, handler: @escaping @MainActor (Event) -> Void) {
        SystemExtensionRequest(handler: handler)
            .submit(.activationRequest(forExtensionWithIdentifier: identifier, queue: .main))
    }

    @MainActor
    package static func properties(_ identifier: String, handler: @escaping @MainActor (Event) -> Void) {
        SystemExtensionRequest(handler: handler)
            .submit(.propertiesRequest(forExtensionWithIdentifier: identifier, queue: .main))
    }

    private func submit(_ request: OSSystemExtensionRequest) {
        retainedSelf = self
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    // Callbacks arrive on the main queue passed to the request.
    private func send(_ event: Event, done: Bool) {
        MainActor.assumeIsolated { handler(event) }
        if done { retainedSelf = nil }
    }

    package func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    package func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        send(.needsUserApproval, done: false)
    }

    package func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        send(.activated, done: true)
    }

    package func request(_ request: OSSystemExtensionRequest, didFailWithError error: any Error) {
        send(.failed(error), done: true)
    }

    package func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        send(.properties(properties), done: true)
    }
}
