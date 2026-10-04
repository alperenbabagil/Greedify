import Foundation
import Testing
@testable import GreedifyKit

struct URLSessionTransportTests {
    /// URLSession reports a cancelled task as `URLError.cancelled`; it must surface as cancellation, not as a
    /// transport failure ("Can't reach Spotify").
    @Test func cancelledRequestThrowsCancellationError() async {
        let transport = URLSessionTransport()
        // Not routable: the request is still connecting when it's cancelled.
        let request = URLRequest(url: URL(string: "http://10.255.255.1/")!, timeoutInterval: 30)
        let task = Task { try await transport.send(request) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
