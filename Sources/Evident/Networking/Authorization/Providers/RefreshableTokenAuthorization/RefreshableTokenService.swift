//
//  RefreshableTokenService.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation

/// A service that knows how to refresh an expired ``AuthorizationToken``.
///
/// Implement this protocol to provide token refresh logic for use with
/// ``RefreshableTokenAuthorization``:
/// ```swift
/// actor MyTokenService: RefreshableTokenService {
///     func refresh(_ token: MyToken) async throws -> MyToken {
///         // call your auth server to get a new token
///     }
/// }
/// ```
public protocol RefreshableTokenService: Actor {

    /// The type of token this service manages.
    associatedtype Token: AuthorizationToken

    /// Refreshes the given expired token and returns a new valid token.
    ///
    /// - Parameter token: The expired token to refresh.
    /// - Returns: A new, valid token.
    /// - Throws: An error if the token cannot be refreshed.
    func refresh(_ token: Token) async throws -> Token
}
