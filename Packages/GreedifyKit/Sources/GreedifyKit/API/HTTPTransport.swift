import Foundation

/// The single seam between Greedify and the network. Tests swap in `StubTransport`.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SpotifyError.transport("Not an HTTP response")
            }
            return (data, http)
        } catch let error as SpotifyError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            // The calling task was cancelled (a poll replaced or stopped): not a network failure.
            throw CancellationError()
        } catch {
            throw SpotifyError.transport(error.localizedDescription)
        }
    }
}
