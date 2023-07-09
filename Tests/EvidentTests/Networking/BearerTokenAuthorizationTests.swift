//
//  BearerTokenAuthorizationTests.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation
import Evident
import XCTest

final class BearerTokenAuthorizationTests: XCTestCase {
    
    func test_bearerAuthorization() async throws {
        // given
        let url = try XCTUnwrap(URL(string: "https://test.net"))
        let request = URLRequest(url: url)
        let authProvider = BearerTokenAuthorization(token: "TOK")
        
        // when
        let workRequest = try await authProvider.authorize(request)
        
        // then
        XCTAssertNotEqual(workRequest, request)
        
        XCTAssertEqual("Bearer TOK", workRequest.authorizationHeaderValue)
    }
}
