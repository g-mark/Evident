//
//  AuthorizationToken.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation

/// A token that provides authorization credentials for HTTP requests.
///
/// Conforming types represent an authorization token (e.g. OAuth/OIDC tokens)
/// that can expire and be refreshed.
public protocol AuthorizationToken: Sendable {

    /// The value to use for the `Authorization` HTTP header (e.g. `"Bearer <token>"`).
    var authorizationHeaderValue: String { get }

    /// Whether the token has expired and needs to be refreshed.
    var isExpired: Bool { get }

    /// Marks the token as expired, forcing a refresh on the next authorization attempt.
    mutating func setExpired()
}
