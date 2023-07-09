//
//  AuthorizationProvider.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation

/// Something that can provide an "Authorization" http header value..
///
/// Use:
/// ```swift
/// let provider: AuthorizationProvider = ...
/// var urlRequest: URLRequest = ...
///
/// try await provider.authorize(urlRequest)
/// ```
public protocol AuthorizationProvider: Actor {
    
    /// Get a value for an `Authorization` http header.
    ///
    /// If the provider is "refreshable", this may result in extra http requests.
    ///
    /// - Returns: An `Authorization` http header value string (e.g. "Bearer ABC").
    func authorize(_ request: URLRequest) async throws -> URLRequest
    
    /// Forces the next call to `authorize(_:)` to refresh itself,
    /// in response to a `401 Unauthorized` response from a network request.
    ///
    /// - Parameter request: The`URLRequest` from which a `401` status code was received.
    /// - Throws: `NotAuthorized` if authorization can not be refreshed
    func setNeedsRefreshAfterUnauthorizedResponse(for request: URLRequest) async throws
}

extension AuthorizationProvider {
    
    public func setNeedsRefreshAfterUnauthorizedResponse(for request: URLRequest) async throws {
        throw NotAuthorized()
    }
}

public struct NotAuthorized: Error { }
