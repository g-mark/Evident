//
//  RefreshableTokenAuthorizationProviderTests.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation
import Testing
@testable import Evident

@Suite(.serialized)
struct RefreshableTokenAuthorizationProviderTests {

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

    private let service: MyTokenService
    private let provider: MyProvider
    private let mockRequest = URLRequest(url: URL(fileURLWithPath: ""))

    init() {
        service = MyTokenService()
        provider = RefreshableTokenAuthorization(service: service)
    }

    /// The provider must throw an error if it is an invalid state.
    @Test func invalidState() async throws {
        await #expect(throws: (any Error).self) {
            try await provider.authorize(mockRequest)
        }
    }

    /// The provider must provide a valid header value when it has a valid, unexpired token.
    @Test func validUnexpiredToken() async throws {
        // given (provider has a valid token)
        await provider.setToken(MyToken(authorizationHeaderValue: "TOK", isExpired: false))

        // when
        let authorizedRequest = try await provider.authorize(mockRequest)

        // then
        #expect("TOK" == authorizedRequest.authorizationHeaderValue)
    }

    /// The provider must refresh the token after a call to `setNeedsRefresh()`.
    @Test func validUnexpiredTokenNeedsRefresh() async throws {
        // given (start with valid token)
        await provider.setToken(MyToken(authorizationHeaderValue: "TOK", isExpired: false))
        let authorizedRequest = try await provider.authorize(mockRequest)
        #expect("TOK" == authorizedRequest.authorizationHeaderValue)

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
        #expect(headerValue == "NEW")
    }

    /// When the provider has a valid expired token, it must refresh it.
    @Test func validExpiredTokenRefreshSuccess() async throws {
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
        #expect(headerValue == "TOK")
    }

    /// The provider must ignore a call to `setNeedsRefresh()` when referencing an old token value.
    @Test func needsRefreshBailOutAlreadyChanged() async throws {
        // given (start with valid token)
        await provider.setToken(MyToken(authorizationHeaderValue: "TOK", isExpired: false))

        // when (use old token value)
        let oldRequest = mockRequest.withAuthorization(value: "OLD")
        await provider.setNeedsRefreshAfterUnauthorizedResponse(for: oldRequest)

        // then (original, valid token should be used)
        let value = try await provider.authorize(mockRequest).authorizationHeaderValue
        #expect("TOK" == value)
    }

    /// The provider must throw an error when a token refresh fails.
    @Test func validExpiredTokenRefreshFailure() async throws {
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
        catch is MyError { }
        catch {
            Issue.record("Unexpected \(error)")
        }
    }

    /// `RefreshableTokenAuthorization` only calls the refresh service once
    /// when multiple requests for an auth header value are made.
    /// All requests are satisfied using a refreshed value.
    @Test func validExpiredTokenRefreshMultipleSuccess() async throws {
        // given (start with expired token)
        await provider.setToken(MyToken(authorizationHeaderValue: "OLD", isExpired: true))

        // when (start a bunch of asks for a header value)
        let iterations = 100
        async let result = withThrowingTaskGroup(of: String?.self, returning: [String?].self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    try await provider.authorize(mockRequest).authorizationHeaderValue
                }
            }

            var values = [String?]()
            while let value = try await group.next() {
                values.append(value)
            }
            return values
        }

        // then
        let continuation = try await eventually { await service.continuation }

        // when (refresh succeeds)
        continuation.resume(returning: MyToken(authorizationHeaderValue: "TOK", isExpired: false))

        // then (all pending requests should have the new value)
        let values = try await result
        #expect(values.allSatisfy { $0 == "TOK" })
        #expect(values.count == iterations)
    }

    /// `RefreshableTokenAuthorization` only calls the refresh service once
    /// when multiple requests for an auth header value are made.
    /// All requests throw the same error.
    @Test func validExpiredTokenRefreshMultipleFailure() async throws {
        // given (start with expired token)
        await provider.setToken(MyToken(authorizationHeaderValue: "OLD", isExpired: true))

        // when (start a bunch of asks for a header value)
        let iterations = 100
        async let result = withThrowingTaskGroup(of: String?.self, returning: [Result<String?, Error>].self) { group in
            for _ in 0..<iterations {
                group.addTask {
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

        // then
        let continuation = try await eventually { await service.continuation }

        // when (fail the refresh)
        continuation.resume(throwing: MyError.mockError)

        // then (all pending requests should have thrown an error)
        let values = await result
        #expect(values.allSatisfy { $0.error as? MyError == MyError.mockError })
        #expect(values.count == iterations)
    }

    /// The provider must use new `setToken()` values to resolve a pending refresh task.
    @Test func validExpiredTokenInterruptedWithValidToken() async throws {
        // given (start with expired token)
        await provider.setToken(MyToken(authorizationHeaderValue: "OLD", isExpired: true))

        // when (start a bunch of asks for a header value)
        let iterations = 100
        async let result = withThrowingTaskGroup(of: String?.self, returning: [String?].self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    try await provider.authorize(mockRequest).authorizationHeaderValue
                }
            }

            var values = [String?]()
            while let value = try await group.next() {
                values.append(value)
            }
            return values
        }

        // then (wait for refresh to start)
        let _ = try await eventually { await service.continuation }

        // when (manually apply a new token)
        await provider.setToken(MyToken(authorizationHeaderValue: "TOK", isExpired: false))

        // then (manually applied token should be used for all pending requests)
        let values = try await result
        #expect(values.allSatisfy { $0 == "TOK" })
        #expect(values.count == iterations)
    }

    /// The provider must immediately abort a token refresh when `reset()` is called.
    @Test func validExpiredTokenInterruptedByReset() async throws {
        // given (start with expired token)
        await provider.setToken(MyToken(authorizationHeaderValue: "OLD", isExpired: true))

        // when (start a bunch of asks for a header value)
        let iterations = 100
        async let result = withThrowingTaskGroup(of: String?.self, returning: [Result<String?, Error>].self) { group in
            for _ in 0..<iterations {
                group.addTask {
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

        // then (wait for refresh to start)
        let _ = try await eventually { await service.continuation }

        // when
        await provider.reset()

        // then (all pending requests should have thrown an error)
        let values = await result
        #expect(values.allSatisfy { $0.error is NotAuthorized })
        #expect(values.count == iterations)
    }

    /// The provider must cancel an in-progress refresh when a new refresh is manually started.
    @Test func validExpiredTokenInterruptedWithAlternateRefresh() async throws {
        await provider.setToken(MyToken(authorizationHeaderValue: "OLD", isExpired: true))

        // when
        let iterations = 100
        async let result = withThrowingTaskGroup(of: String?.self, returning: [String?].self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    try await provider.authorize(mockRequest).authorizationHeaderValue
                }
            }

            var values = [String?]()
            while let value = try await group.next() {
                values.append(value)
            }
            return values
        }

        // then (wait for the refresh to start)
        let continuation = try await eventually { await service.continuation }

        // when (manually refresh the token using an alternate method)
        try await provider.refresh {
            MyToken(authorizationHeaderValue: "ALT", isExpired: false)
        }
        // (send response to original refresh request)
        continuation.resume(returning: MyToken(authorizationHeaderValue: "TOK", isExpired: false))

        // then (newer refresh value should be used by all pending header requests)
        let values = try await result
        #expect(values.allSatisfy { $0 == "ALT" })
        #expect(values.count == iterations)
    }

    /// A manual `refresh()` whose work throws must propagate the error to the caller.
    @Test func refreshThrowsWhenWorkThrows() async throws {
        // when / then
        await #expect(throws: MyError.mockError) {
            try await provider.refresh {
                throw MyError.mockError
            }
        }

        // then (provider is left in an invalid state)
        await #expect(throws: (any Error).self) {
            try await provider.authorize(mockRequest)
        }
    }

    /// While an exclusive `refresh()` is in flight, concurrent `authorize()` calls for an
    /// expired token must NOT start their own refresh — they must queue as waiters and
    /// receive the exclusive refresh's result.
    @Test func exclusiveRefreshAbsorbsConcurrentAuthorize() async throws {
        // given (seed with an expired token — the would-be opportunistic refresh path)
        await provider.setToken(MyToken(authorizationHeaderValue: "OLD", isExpired: true))

        // when (start an exclusive refresh, held pending via the service continuation)
        let placeholder = MyToken(authorizationHeaderValue: "OLD", isExpired: true)
        async let refreshResult: Void = provider.refresh {
            try await self.service.refresh(placeholder)
        }

        // then (refresh is in flight)
        let continuation = try await eventually { await service.continuation }

        // when (many concurrent authorize() calls pile up while exclusive refresh is in flight)
        let iterations = 50
        async let authResults = withThrowingTaskGroup(of: String?.self, returning: [String?].self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    try await provider.authorize(mockRequest).authorizationHeaderValue
                }
            }
            var values = [String?]()
            while let value = try await group.next() {
                values.append(value)
            }
            return values
        }

        // (give time for authorize calls to land on the actor and queue as waiters)
        try await Task.sleep(for: .milliseconds(50))

        // when (exclusive refresh completes successfully)
        continuation.resume(returning: MyToken(authorizationHeaderValue: "NEW", isExpired: false))

        // then (the exclusive refresh caller resolves)
        try await refreshResult

        // then (all queued authorize calls resolved with the exclusive refresh's token —
        // if any had started their own refresh, MyTokenService would have thrown `alreadyRefreshing`)
        let values = try await authResults
        #expect(values.count == iterations)
        #expect(values.allSatisfy { $0 == "NEW" })
    }

    /// A second exclusive `refresh()` must replace an in-flight exclusive refresh,
    /// cancel its task, and resolve the first caller using the second refresh's result.
    @Test func exclusiveRefreshReplacesExclusiveAndMergesWaiters() async throws {
        // given (a first exclusive refresh, held pending via the service continuation)
        let placeholder = MyToken(authorizationHeaderValue: "OLD", isExpired: true)
        async let firstResult: Void = provider.refresh {
            try await self.service.refresh(placeholder)
        }
        let firstContinuation = try await eventually { await service.continuation }

        // when (a second exclusive refresh replaces the first with an immediate result)
        try await provider.refresh {
            MyToken(authorizationHeaderValue: "SECOND", isExpired: false)
        }

        // then (the first caller resolves successfully — it was merged into the second's waiter set)
        try await firstResult

        // then (the actor state reflects the second refresh)
        let value = try await provider.authorize(mockRequest).authorizationHeaderValue
        #expect(value == "SECOND")

        // when (the first refresh's underlying work belatedly completes)
        firstContinuation.resume(returning: MyToken(authorizationHeaderValue: "FIRST", isExpired: false))

        // then (the late result is discarded; state remains the second refresh's token)
        let afterValue = try await provider.authorize(mockRequest).authorizationHeaderValue
        #expect(afterValue == "SECOND")
    }

}
