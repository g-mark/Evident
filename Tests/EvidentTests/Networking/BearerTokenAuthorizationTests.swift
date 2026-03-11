//
//  BearerTokenAuthorizationTests.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation
import Evident
import Testing

struct BearerTokenAuthorizationTests {

    @Test func bearerAuthorization() async throws {
        // given
        let url = try #require(URL(string: "https://test.net"))
        let request = URLRequest(url: url)
        let authProvider = BearerTokenAuthorization(token: "TOK")

        // when
        let workRequest = try await authProvider.authorize(request)

        // then
        #expect(workRequest != request)
        #expect("Bearer TOK" == workRequest.authorizationHeaderValue)
    }
}
