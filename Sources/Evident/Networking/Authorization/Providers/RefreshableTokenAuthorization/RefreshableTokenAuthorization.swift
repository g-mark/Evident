//
//  RefreshableTokenAuthorization.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation

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
    
    /// Creates a refreshable token authorization provider.
    ///
    /// The provider starts in an invalid state with no token.
    /// Use ``setToken(_:)`` or ``refresh(using:)`` to provide an initial token.
    ///
    /// - Parameter service: The service used to refresh expired tokens.
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
            let id = UUID()
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    startRefreshing(.opportunistic, token: token, using: { try await self.service.refresh(token) })
                    addRefreshWaiter(continuation, id: id, for: request)
                }
            } onCancel: {
                Task {
                    if let waiter = await removeWaiter(id: id) {
                        waiter.resume(.failure(CancellationError()))
                    }
                }
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
    /// - If a refresh is already in progress it will be replaced, maintaining any pending `authorizationHeaderValue()` calls
    ///   (i.e., any calls waiting on an expired token refresh will receive the result of the new `refresh()` work).
    /// - If another `refresh()` call replaces this one, the awaiting caller will receive the replacing refresh's result,
    ///   not their own work's result.
    ///
    /// `refresh()` waits for `work` to finish.
    ///
    /// This can be used, for example, to manually log a user in, or retrieve tokens from storage.
    /// ```swift
    /// let sharedOidcAuth = RefreshableTokenAuthorization(
    ///     service: sharedOidcService
    /// )
    ///
    /// // by logging in
    /// try await sharedOidcAuth.refresh {
    ///     return sharedOidcService.login(username, password)
    /// }
    ///
    /// // or by retrieving from some kind of storage:
    /// try await sharedOidcAuth.refresh {
    ///     return try await KeychainHelper.shared.retrieve(...)
    /// }
    /// ```
    ///
    /// - Parameter work: A closure that returns a new `Token`.
    public func refresh(using work: @escaping @Sendable () async throws -> Token) async throws {
        let token = state.token
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                startRefreshing(.exclusive, token: token, using: work)
                addRefreshWaiter(continuation, id: id) { _ in }
            }
        } onCancel: {
            Task {
                if let waiter = await removeWaiter(id: id) {
                    waiter.resume(.failure(CancellationError()))
                }
            }
        }
    }
    
    /// Set the current token to a known value.
    ///
    /// - Cancels any pending refresh tasks - either manual calls to `refresh()` or background token refreshes.
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
    
    /// Messages dispatched when the token state changes.
    public enum TokenChangeMessage: Sendable {
        /// The token has been invalidated, with the associated error describing why.
        case tokenInvalidated(Error)
        /// The token has been updated to a new valid value.
        case tokenUpdated(Token)
    }

    /// Subscribes to token change notifications.
    ///
    /// The handler is called whenever the token is updated or invalidated.
    ///
    /// - Parameter handler: An async closure called with each ``TokenChangeMessage``.
    /// - Returns: An ``AnyCancellableAsync`` to manage the observation lifetime.
    public func onTokenChange(
        _ handler: @escaping MessageQueue<TokenChangeMessage>.Handler
    ) async -> AnyCancellableAsync {
        await tokenChanges.observe(handler)
    }
    
    // MARK: - Implementation details
    
    private let service: TokenService
    private var state: State
    private let tokenChanges = MessageQueue<TokenChangeMessage>()
    
    private enum State {
        case invalid(Error)
        case valid(Token)
        case refreshing(Token?, Task<Void, Never>, Set<Waiter>, Priority)

        var token: Token? {
            switch self {
            case .invalid: return nil
            case .valid(let token): return token
            case .refreshing(let token, _, _, _): return token
            }
        }
        
        var isRefreshing: Bool {
            switch self {
            case .refreshing: return true
            case .invalid, .valid: return false
            }
        }
    }

    private enum Priority {
        // Newest refresh request wins, existing in-flight refreshes are cancelled
        case opportunistic

        // New refresh requests await an in-flight exclusive refresh
        // These are "milestone" refreshes, like an initial login.
        case exclusive
    }

    typealias Continuation = CheckedContinuation<URLRequest, Error>
    
    private struct InternalError: Error {
        let cause: String
        init(_ cause: String) { self.cause = cause }
    }
    
    /// Represents a call to `authorize(_:)` that is awaiting a token refresh.
    private struct Waiter: Hashable, Sendable {
        let id: UUID
        let resume: @Sendable (Result<Token, Error>) -> Void

        init<T: Sendable>(
            _ continuation: CheckedContinuation<T, Error>,
            id: UUID = UUID(),
            mapping: @Sendable @escaping (Token) -> T
        ) {
            self.id = id
            resume = { result in
                continuation.resume(with: result.map(mapping))
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
    private func addRefreshWaiter(
        _ continuation: Continuation,
        id: UUID = UUID(),
        for request: URLRequest
    ) {
        addRefreshWaiter(continuation, id: id) {
            request.withAuthorization(token: $0)
        }
    }

    /// Adds the `continuation` to the current `refreshing` list of waiters.
    private func addRefreshWaiter<T: Sendable>(
        _ continuation: CheckedContinuation<T, Error>,
        id: UUID = UUID(),
        mapping: @Sendable @escaping (Token) -> T
    ) {
        guard case let .refreshing(token, task, waiters, priority) = self.state else {
            continuation.resume(throwing: InternalError("addRefreshWaiter while not refreshing"))
            return
        }
        let waiter = Waiter(continuation, id: id, mapping: mapping)
        changeState(to: .refreshing(token, task, waiters.inserting(waiter), priority))
    }

    private func removeWaiter(id: UUID) -> Waiter? {
        guard case let .refreshing(token, task, waiters, priority) = self.state,
              let index = waiters.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        var updated = waiters
        let waiter = updated.remove(at: index)
        changeState(to: .refreshing(token, task, updated, priority))
        return waiter
    }

    /// Starts the process of refreshing a token.
    ///
    /// Changes `state` to `refreshing` with an empty set of waiters.
    private func startRefreshing(
        _ atPriority: Priority,
        token: Token?,
        using work: @escaping @Sendable () async throws -> Token
    ) {
        var waiters: Set<Waiter> = []
        if case let .refreshing(_, _, inFlightWaiters, _) = state {
            waiters = inFlightWaiters
        }

        // An in-flight exclusive refresh is not preempted by an incoming opportunistic refresh.
        if atPriority == .opportunistic,
           case let .refreshing(_, _, _, priority) = state,
           priority == .exclusive {
            return
        }
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
        
        self.changeState(to: .refreshing(token, task, waiters, atPriority))
    }
    
    /// Changes the current `state` to the specified value.
    ///
    /// All changes to `state` must go through here, to ensure proper cleanup of pending tasks and continuations.
    private func changeState(to newState: State) {
        switch (state, newState) {
            
        case (.invalid, _),
             (.valid, _):
            state = newState
            
        case (.refreshing(_, let oldTask, let oldWaiters, _), .invalid(let error)):
            oldTask.cancel()
            oldWaiters.forEach { $0.resume(.failure(error)) }
            state = newState
            
        case (.refreshing(_, let oldTask, let oldWaiters, _), .valid(let token)):
            oldTask.cancel()
            oldWaiters.forEach { $0.resume(.success(token)) }
            state = newState
            
        case (let .refreshing(_, oldTask, _, _),
              let .refreshing(token, newTask, newWaiters, newPriority)):
            // Note: blocking an `exclusive` -> `opportunistic` change is handled in `startRefreshing`.
            if oldTask != newTask {
                oldTask.cancel()
            }
            state = .refreshing(token, newTask, newWaiters, newPriority)
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
