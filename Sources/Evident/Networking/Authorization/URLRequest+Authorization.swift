//
//  URLRequest+Authorization.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation

extension URLRequest {
    
    /// Authorizes this request using the given provider.
    ///
    /// - Parameter provider: The ``AuthorizationProvider`` to use for authorization.
    /// - Throws: An error if authorization fails.
    public mutating func authorize(using provider: AuthorizationProvider) async throws {
        self = try await provider.authorize(self)
    }
    
    /// The value of the `Authorization` HTTP header, if set.
    public var authorizationHeaderValue: String? {
        get { value(forHTTPHeaderField: "Authorization") }
        set { setValue(newValue, forHTTPHeaderField: "Authorization") }
    }
    
    /// Sets the `Authorization` header using the given token's ``AuthorizationToken/authorizationHeaderValue``.
    ///
    /// - Parameter token: The token providing the authorization header value.
    public mutating func setAuthorization(token: any AuthorizationToken) {
        authorizationHeaderValue = token.authorizationHeaderValue
    }
    
    /// Returns a copy of this request with the `Authorization` header set from the given token.
    ///
    /// - Parameter token: The token providing the authorization header value.
    /// - Returns: A new `URLRequest` with the `Authorization` header set.
    public func withAuthorization(token: any AuthorizationToken) -> URLRequest {
        withAuthorization(value: token.authorizationHeaderValue)
    }
    
    /// Returns a copy of this request with the `Authorization` header set to the given value.
    ///
    /// - Parameter value: The raw authorization header value (e.g. `"Bearer <token>"`).
    /// - Returns: A new `URLRequest` with the `Authorization` header set.
    public func withAuthorization(value: String) -> URLRequest {
        var request = self
        request.authorizationHeaderValue = value
        return request
    }
}
