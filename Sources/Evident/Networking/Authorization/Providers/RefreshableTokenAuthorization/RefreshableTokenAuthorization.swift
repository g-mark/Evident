//
//  RefreshableTokenAuthorization.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation
import Combine

/// An `AuthorizationProvider` that manages a refreshable `AuthorizationToken`.
///
/// Features:
/// - Provides "Authorization" http header values from a valid token.
/// - Attempts to refresh a token if it has expired.
/// - Requests for auth header values while a refresh is in progress are held until the refresh is complete.
///   I.e., There will only ever be a single request to refresh a token.
///
/// Usage:
/// - create a `RefreshableTokenService` actor that knows how to work with your tokens
/// - instantiate a `RefreshableTokenAuthorization` using that service.
///   This instance should be long-lived, and re-used wherever the same authorization is needed.
///
/// E.g.:
/// ```swift
/// actor OidcTokensService: RefreshableTokenService {
///     fun refresh(_ token: OidcTokens) async throws -> OidcTokens {
///         ...
///     }
/// }
///
/// let sharedOidcService = OidcTokensService()
/// let sharedOidcAuth = RefreshableTokenAuthorization(
///     service: sharedOidcService
/// )
///
/// // "seed" the auth provider with a starting token - perhaps via login:
/// let token = try await sharedOidcService.login(username, password)
/// await sharedOidcAuth.setToken(token)
///
/// // use the auth provider when making network requests:
/// let request: URLRequest = ...
/// try await sharedOidcAuth.authorize(urlRequest)
/// ```
public actor RefreshableTokenAuthorization<Token, TokenService>: AuthorizationProvider
where TokenService: RefreshableTokenService, TokenService.Token == Token {
    
    public init(service: TokenService) {
        self.service = service
        self.state = .invalid(NotAuthorized())
    }
    
    // MARK: - Refresh flow
    
    /// Authorize  `URLRequest`.
    ///
    /// Sets a value for the "Authorization" http header.
    ///
    /// - Returns: An authorized `URLRequest`.
    /// - Throws: `NotAuthorized`, if the token is invalid/missing; or an `Error` thrown from a failed refresh.
    public func authorize(_ request: URLRequest) async throws -> URLRequest {
        switch state {
            
        case .invalid(let error):
            throw error
        
        case .valid(let token) where token.isExpired:
            return try await withCheckedThrowingContinuation { continuation in
                startRefreshing(token, using: { try await self.service.refresh(token) })
                addRefreshWaiter(continuation, for: request)
            }
        
        case .valid(let token):
            return request.withAuthorization(token: token)
            
        case .refreshing:
            return try await withCheckedThrowingContinuation { continuation in
                addRefreshWaiter(continuation, for: request)
            }
        }
    }
    
    /// Forces the next call to `authorize(_:)` to refresh the token,
    /// in response to a `401 Unauthorized` response from a network request.
    ///
    /// - Parameter request: The`URLRequest` from which a `401` status code was received.
    /// - Throws: `NotAuthorized` if authorization can not be refreshed
    public func setNeedsRefreshAfterUnauthorizedResponse(for request: URLRequest) async {
        guard case var .valid(token) = state else { return }
        if let authHeaderValue = request.authorizationHeaderValue,
           authHeaderValue != token.authorizationHeaderValue {
            return
        }
        token.setExpired()
        changeState(to: .valid(token))
    }
    
    /// Reset the provider by manually starting a new token refresh, using the supplied closure to provide a new token.
    ///
    /// - Any subsequent calls to `authorizationHeaderValue()` will wait for the new refresh to finish.
    /// - If a refresh is already in progress it will be replaced, maintaining any pending `authorizationHeaderValue()` calls.
    ///
    /// `refresh()` starts the refresh `work`, and immediately returns, without waiting for `work` to finish.
    ///
    /// This can be used, for example, to manually log a user in, or retrieve tokens from storage.
    /// ```swift
    /// let sharedOidcAuth = RefreshableTokenAuthorization(
    ///     service: sharedOidcService
    /// )
    ///
    /// // by logging in
    /// await sharedOidcAuth.refresh {
    ///     return sharedOidcService.login(username, password)
    /// }
    ///
    /// // or by retrieving from some kind of storage:
    /// await sharedOidcAuth.refresh {
    ///     return try await KeychainHelper.shared.retrieve(...)
    /// }
    /// ```
    ///
    /// - Parameter work: A closure that returns a new `Token`.
    public func refresh(using work: @escaping @Sendable () async throws -> Token) async {
        let token = state.token
        startRefreshing(token, using: work)
    }
    
    /// Set the current token to a known value.
    ///
    /// - Cancels any pending refresh tasks.
    /// - All pending and future calls to `authorizationHeaderValue()` will receive a value based on the new token.
    ///
    /// - Parameter token: The new `Token`.
    public func setToken(_ token: Token) async {
        changeState(to: .valid(token))
    }
    
    /// Reset the provider.
    ///
    /// - Cancels any pending refresh tasks.
    /// - All pending calls to `authorizationHeaderValue()` will throw an error.
    /// - Puts the provider into an invalid state, with no valid token.
    public func reset() async {
        changeState(to: .invalid(NotAuthorized()))
    }
    
    // MARK: - Notifications
    
    public enum TokenChangeMessage {
        case tokenInvalidated(Error)
        case tokenUpdated(Token)
    }
    
    public func onTokenChange(
        _ handler: @escaping MessageQueue<TokenChangeMessage>.Handler
    ) async -> AnyCancellable {
        await tokenChanges.observe(handler)
    }
    
    // MARK: - Implementation details
    
    private let service: TokenService
    private var state: State
    private let tokenChanges = MessageQueue<TokenChangeMessage>()
    
    private enum State {
        case invalid(Error)
        case valid(Token)
        case refreshing(Token?, Task<Void, Never>, Set<Waiter>)
        
        var token: Token? {
            switch self {
            case .invalid: return nil
            case .valid(let token): return token
            case .refreshing(let token, _, _): return token
            }
        }
        
        var isRefreshing: Bool {
            switch self {
            case .refreshing: return true
            case .invalid, .valid: return false
            }
        }
    }
    
    typealias Continuation = CheckedContinuation<URLRequest, Error>
    
    private struct InternalError: Error {
        let cause: String
        init(_ cause: String) { self.cause = cause }
    }
    
    /// Represents a call to `authorize(_:)` that is awaiting a token refresh.
    private struct Waiter: Hashable {
        let id: UUID = UUID()
        let resume: (Result<Token, Error>) -> Void
        
        init(_ continuation: Continuation, for request: URLRequest) {
            resume = { result in
                continuation.resume(with: result.map { request.withAuthorization(token: $0) })
            }
        }
        
        static func == (lhs: Waiter, rhs: Waiter) -> Bool {
            lhs.id == rhs.id
        }
        
        func hash(into hasher: inout Hasher) {
            id.hash(into: &hasher)
        }
    }
    
    /// Adds the `continuation` to the current `refreshing` list of waiters.
    private func addRefreshWaiter(_ continuation: Continuation, for request: URLRequest) {
        guard case let .refreshing(token, task, waiters) = self.state else {
            continuation.resume(throwing: InternalError("addRefreshWaiter while not refreshing"))
            return
        }
        let waiter = Waiter(continuation, for: request)
        changeState(to: .refreshing(token, task, waiters.inserting(waiter)))
    }
    
    /// Starts the process of refreshing a token.
    ///
    /// Changes `state` to `refreshing` with an empty set of waiters.
    private func startRefreshing(_ token: Token?, using work: @escaping @Sendable () async throws -> Token) {
        let task = Task {
            let result = await Result {
                try await work()
            }
            guard !Task.isCancelled, self.state.isRefreshing else {
                return
            }
            
            switch result {
            case .success(let token): self.changeState(to: .valid(token))
            case .failure(let error): self.changeState(to: .invalid(error))
            }
        }
        
        self.changeState(to: .refreshing(token, task, []))
    }
    
    /// Changes the current `state` to the specified value.
    ///
    /// All changes to `state` must go through here, to ensure proper cleanup of pending tasks and continuations.
    private func changeState(to newState: State) {
        switch (state, newState) {
            
        case (.invalid, _),
             (.valid, _):
            state = newState
            
        case (.refreshing(_, let oldTask, let oldWaiters), .invalid(let error)):
            oldTask.cancel()
            oldWaiters.forEach { $0.resume(.failure(error)) }
            state = newState
            
        case (.refreshing(_, let oldTask, let oldWaiters), .valid(let token)):
            oldTask.cancel()
            oldWaiters.forEach { $0.resume(.success(token)) }
            state = newState
            
        case (.refreshing(_, let oldTask, let oldWaiters), .refreshing(let token, let newTask, let newWaiters)):
            if oldTask != newTask {
                oldTask.cancel()
            }
            state = .refreshing(token, newTask, oldWaiters.union(newWaiters))
        }
        
        switch newState {
        case .invalid(let error):
            tokenChanges.dispatch(.tokenInvalidated(error))
        case .valid(let token):
            tokenChanges.dispatch(.tokenUpdated(token))
        case .refreshing:
            break
        }
    }
}
