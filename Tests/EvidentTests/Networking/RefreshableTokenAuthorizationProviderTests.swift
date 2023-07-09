//
//  RefreshableTokenAuthorizationProviderTests.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import XCTest
@testable import Evident

final class RefreshableTokenAuthorizationProviderTests: XCTestCase {
    
    /// Mock token type
    private struct MyToken: AuthorizationToken {
        var authorizationHeaderValue: String
        var isExpired: Bool
        
        mutating func setExpired() { isExpired = true }
    }
    
    /// Mock token service, captures the continuation for a `refresh()` call to have control over the response.
    private actor MyTokenService: RefreshableTokenService {
        var continuation: CheckedContinuation<MyToken, Error>?
        
        func refresh(_ token: MyToken) async throws -> MyToken {
            try await withCheckedThrowingContinuation { continuation in
                guard self.continuation == nil else {
                    continuation.resume(throwing: MyError.alreadyRefreshing)
                    return
                }
                self.continuation = continuation
            }
        }
    }
    
    private typealias MyProvider = RefreshableTokenAuthorization<MyToken, MyTokenService>
    
    private enum MyError: Error {
        case alreadyRefreshing
        case mockError
    }
    
    private var service: MyTokenService!
    private var provider: MyProvider!
    private let mockRequest = URLRequest(url: URL(fileURLWithPath: ""))
    
    override func setUp() {
        super.setUp()
        
        service = MyTokenService()
        provider = RefreshableTokenAuthorization(service: service)
    }
    
    override func tearDown() {
        service = nil
        provider = nil
        
        super.tearDown()
    }
    
    /// The provider must throw an error if it is an invalid state.
    func test_invalidState() async throws {
        await XCTAssertThrowsErrorAsync(try await provider.authorize(mockRequest))
    }
    
    /// The provider must provide a valid header value when it has a valid, unexpired token.
    func test_validUnexpiredToken() async throws {
        // given (provider has a valid token)
        await provider.setToken(MyToken(authorizationHeaderValue: "TOK", isExpired: false))
        
        // when
        let authorizedRequest = try await provider.authorize(mockRequest)
        
        // then
        XCTAssertEqual("TOK", authorizedRequest.authorizationHeaderValue)
    }
    
    /// The provider must refresh the token after a call to `setNeedsRefresh()`.
    func test_validUnexpiredToken_needsRefresh() async throws {
        // given (start with valid token)
        await provider.setToken(MyToken(authorizationHeaderValue: "TOK", isExpired: false))
        let authorizedRequest = try await provider.authorize(mockRequest)
        XCTAssertEqual("TOK", authorizedRequest.authorizationHeaderValue)
        
        // when (mark the token as expired)
        await provider.setNeedsRefreshAfterUnauthorizedResponse(for: authorizedRequest)
        
        // (initiate refresh, but don't await it yet)
        async let newAuthorizedRequest = provider.authorize(mockRequest)
        
        // then (refresh should have started)
        let continuation = try await eventually { await service.continuation }
        
        // when (send refresh response of a valid token)
        continuation.resume(returning: MyToken(authorizationHeaderValue: "NEW", isExpired: false))
        
        // then (updated token should result in valid header value)
        let headerValue = try await newAuthorizedRequest.authorizationHeaderValue
        XCTAssertEqual(headerValue, "NEW")
    }
    
    /// When the provider has a valid expired token, it must refresh it.
    func test_validExpiredToken_refreshSuccess() async throws {
        // given (start with valid, expired token)
        await provider.setToken(MyToken(authorizationHeaderValue: "OLD", isExpired: true))
        
        // when (initiate refresh, but don't await it yet)
        async let authorizedRequest = provider.authorize(mockRequest)
        
        // then (refresh should have started)
        let continuation = try await eventually { await service.continuation }
        
        // when (send refresh response of a valid token)
        continuation.resume(returning: MyToken(authorizationHeaderValue: "TOK", isExpired: false))
        
        // then (updated token should result in valid header value)
        let headerValue = try await authorizedRequest.authorizationHeaderValue
        XCTAssertEqual(headerValue, "TOK")
    }
    
    /// The provider must ignore a call to `setNeedsRefresh()` when referencing an old token value.
    func test_needsRefresh_bailOut_alreadyChanged() async throws {
        // given (start with valid token)
        await provider.setToken(MyToken(authorizationHeaderValue: "TOK", isExpired: false))
        
        // when (use old token value)
        let oldRequest = mockRequest.withAuthorization(value: "OLD")
        await provider.setNeedsRefreshAfterUnauthorizedResponse(for: oldRequest)
        
        // then (original, valid token should be used)
        let value = try await provider.authorize(mockRequest).authorizationHeaderValue
        XCTAssertEqual("TOK", value)
    }
    
    /// The provider must throw an error when a token refresh fails.
    func test_validExpiredToken_refreshFailure() async throws {
        // given (start with expired token)
        await provider.setToken(MyToken(authorizationHeaderValue: "OLD", isExpired: true))
        
        // when
        async let authorizedRequest = provider.authorize(mockRequest)
        
        // then
        let continuation = try await eventually { await service.continuation }
        
        // when (fail the refresh)
        continuation.resume(throwing: MyError.mockError)
        
        // then (should throw)
        do {
            let _ = try await authorizedRequest
        }
        catch MyError.mockError { }
        catch {
            XCTFail("Unexpected \(error)")
        }
    }
    
    /// `RefreshableTokenAuthorization` only calls the refresh service once
    /// when multiple requests for an auth header value are made.
    /// All requests are satisfied using a refreshed value.
    func test_validExpiredToken_refreshMultipleSuccess() async throws {
        // given (start with expired token)
        await provider.setToken(MyToken(authorizationHeaderValue: "OLD", isExpired: true))
        
        // when (start a bunch of asks for a header value)
        let iterations = 100
        async let result = withThrowingTaskGroup(of: String?.self, returning: [String?].self) { group in
            try await runMultipleCapturingValues(iterations, in: &group, using: provider)
        }
        
        // then
        let continuation = try await eventually { await service.continuation }
        
        // when (refresh succeeds)
        continuation.resume(returning: MyToken(authorizationHeaderValue: "TOK", isExpired: false))
        
        // then (all pending requests should have the new value)
        let values = try await result
        XCTAssertTrue(values.allSatisfy { $0 == "TOK" })
        XCTAssertEqual(values.count, iterations)
    }
    
    /// `RefreshableTokenAuthorization` only calls the refresh service once
    /// when multiple requests for an auth header value are made.
    /// All requests throw the same error.
    func test_validExpiredToken_refreshMultipleFailure() async throws {
        // given (start with expired token)
        await provider.setToken(MyToken(authorizationHeaderValue: "OLD", isExpired: true))
        
        // when (start a bunch of asks for a header value)
        let iterations = 100
        async let result = withThrowingTaskGroup(of: String?.self, returning: [Result<String?, Error>].self) { group in
            await runMultipleCapturingResults(iterations, in: &group, using: provider)
        }
        
        // then
        let continuation = try await eventually { await service.continuation }
        
        // when (fail the refresh)
        continuation.resume(throwing: MyError.mockError)
        
        // then (all pending requests should have thrown an error)
        let values = await result
        XCTAssertTrue(values.allSatisfy { $0.error as? MyError == MyError.mockError })
        XCTAssertEqual(values.count, iterations)
    }
    
    /// The provider must use new `setToken()` values to resolve a pending refresh task.
    func test_validExpiredToken_interruptedWithValidToken() async throws {
        // given (start with expired token)
        await provider.setToken(MyToken(authorizationHeaderValue: "OLD", isExpired: true))
        
        // when (start a bunch of asks for a header value)
        let iterations = 100
        async let result = withThrowingTaskGroup(of: String?.self, returning: [String?].self) { group in
            try await runMultipleCapturingValues(iterations, in: &group, using: provider)
        }
        
        // then (wait for refresh to start)
        let _ = try await eventually { await service.continuation }
        
        // when (manually apply a new token)
        await provider.setToken(MyToken(authorizationHeaderValue: "TOK", isExpired: false))
        
        // then (manually applied token should be used for all pending requests)
        let values = try await result
        XCTAssertTrue(values.allSatisfy { $0 == "TOK" })
        XCTAssertEqual(values.count, iterations)
    }
    
    /// The provider must immediately abort a token refresh when `reset()` is called.
    func test_validExpiredToken_interruptedByReset() async throws {
        // given (start with expired token)
        await provider.setToken(MyToken(authorizationHeaderValue: "OLD", isExpired: true))
        
        // when (start a bunch of asks for a header value)
        let iterations = 100
        async let result = withThrowingTaskGroup(of: String?.self, returning: [Result<String?, Error>].self) { group in
            await runMultipleCapturingResults(iterations, in: &group, using: provider)
        }
        
        // then (wait for refresh to start)
        let _ = try await eventually { await service.continuation }
        
        // when
        await provider.reset()
        
        // then (all pending requests should have thrown an error)
        let values = await result
        XCTAssertTrue(values.allSatisfy { $0.error is NotAuthorized })
        XCTAssertEqual(values.count, iterations)
    }
    
    /// The provider must cancel an in-progress refresh when a new refresh is manually started.
    func test_validExpiredToken_interruptedWithAlternateRefresh() async throws {
        await provider.setToken(MyToken(authorizationHeaderValue: "OLD", isExpired: true))
        
        // when
        let iterations = 100
        async let result = withThrowingTaskGroup(of: String?.self, returning: [String?].self) { group in
            try await runMultipleCapturingValues(iterations, in: &group, using: provider)
        }
        
        // then (wait for the refresh to start)
        let continuation = try await eventually { await service.continuation }
        
        // when (manually refresh the token using an alternate method)
        await provider.refresh {
            MyToken(authorizationHeaderValue: "ALT", isExpired: false)
        }
        // (send response to original refresh request)
        continuation.resume(returning: MyToken(authorizationHeaderValue: "TOK", isExpired: false))
        
        // then (newer refresh value should be used by all pending header requests)
        let values = try await result
        XCTAssertTrue(values.allSatisfy { $0 == "ALT" })
        XCTAssertEqual(values.count, iterations)
    }
    
    private func runMultipleCapturingValues(
        _ iterations: Int,
        in group: inout ThrowingTaskGroup<String?, Error>,
        using provider: MyProvider
    ) async throws -> [String?] {
        for _ in 0..<iterations {
            group.addTask { [mockRequest] in
                try await provider.authorize(mockRequest).authorizationHeaderValue
            }
        }
        
        var values = [String?]()
        while let value = try await group.next() {
            values.append(value)
        }
        return values
    }
    
    private func runMultipleCapturingResults(
        _ iterations: Int,
        in group: inout ThrowingTaskGroup<String?, Error>,
        using provider: MyProvider
    ) async -> [Result<String?, Error>] {
        for _ in 0..<iterations {
            group.addTask { [mockRequest] in
                try await provider.authorize(mockRequest).authorizationHeaderValue
            }
        }
        
        var values = [Result<String?, Error>]()
        while true {
            do {
                let value = try await group.next()
                guard let value else { break }
                values.append(.success(value))
            }
            catch {
                values.append(.failure(error))
            }
        }
        return values
    }
    
}
