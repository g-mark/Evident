//
//  BearerTokenAuthorization.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation

public actor BearerTokenAuthorization: AuthorizationProvider {
    
    private let token: String
    
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
}
