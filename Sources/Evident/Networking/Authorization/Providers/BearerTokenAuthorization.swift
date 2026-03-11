//
//  BearerTokenAuthorization.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation

/// A simple ``AuthorizationProvider`` that applies a static bearer token to requests.
///
/// Use this when the token does not expire or is managed externally:
/// ```swift
/// let auth = BearerTokenAuthorization(token: "my-api-key")
/// let request = try await auth.authorize(urlRequest)
/// ```
public actor BearerTokenAuthorization: AuthorizationProvider {

    /// Creates a bearer token authorization provider.
    ///
    /// - Parameter token: The bearer token string to include in the `Authorization` header.
    public init(token: String) {
        self.token = token
    }
    
    /// Authorize  `URLRequest`.
    ///
    /// Sets a value for the "Authorization" http header.
    ///
    /// - Returns: An authorized `URLRequest`.
    public func authorize(_ request: URLRequest) async throws -> URLRequest {
        request.withAuthorization(value: "Bearer \(token)")
    }
    
    // MARK: - Implementation details
    
    private let token: String
}
