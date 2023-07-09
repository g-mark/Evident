//
//  URLRequest+Authorization.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation

extension URLRequest {
    
    public mutating func authorize(using provider: AuthorizationProvider) async throws {
        self = try await provider.authorize(self)
    }
    
    public var authorizationHeaderValue: String? {
        get { value(forHTTPHeaderField: "Authorization") }
        set { setValue(newValue, forHTTPHeaderField: "Authorization") }
    }
    
    public mutating func setAuthorization(token: any AuthorizationToken) {
        authorizationHeaderValue = token.authorizationHeaderValue
    }
    
    public func withAuthorization(token: any AuthorizationToken) -> URLRequest {
        withAuthorization(value: token.authorizationHeaderValue)
    }
    
    public func withAuthorization(value: String) -> URLRequest {
        var request = self
        request.authorizationHeaderValue = value
        return request
    }
}
