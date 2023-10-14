# Evident

Thread-safe components for working with Swift Concurrency.

## Networking

### AuthorizationProvider

Use an [AuthorizationProvider](Docs/AuthorizationProvider.md) to manage the process of authorizing `URLRequest`s - specifically, working with a token refresh flow.

## Messaging

Publish & Subscribe using a simple [MessageQueue](Sources/Evident/Messaging/MessageQueue.swift).

## Value Observation

Hold a value that can be observed for changes - in whole or in part - using an [ObserervableValue](Sources/Evident/Observation/ObservableValue.swift) - an alternative to `@Observable`.

### ManagedValue

Create composite "data manager" / repository actors using a [`ManagedValue`](Sources/Evident/Observation/ManagedValue.swift).  A `ManagedValue` is a read-only, optionally cached, `ObserervableValue`, with controlled mutability via special "setter" object.

A "data manager" is an abstraction layer that can be thought of as a "repository". It provides read access to some data, which can be observerd for changes.  It provides write access through dedicated methods, where there is an opportunity for extra business logic and/or communication with a [back end] service.

E.g.:
```swift
actor MyDataManager {
    
    // MARK: - Public API
    
    /// Observable `MyData` value
    let myData: ManagedValue<MyData>
    
    func updateName(value: String) async throws {
        // 1. (todo) apply extra business logic (validation, etc.)
        // 2. (todo) call some back end service to update a remote value
        
        // 3. update the managed value:
        await setter.set(\.name, value: value)
    }
    
    func updateNumber(value: Int) async throws {
        // 1. (todo) apply extra business logic (validation, etc.)
        // 2. (todo) call some back end service to update a remote value
        
        // 3. update the managed value:
        await setter.set(\.number, value: value)
    }
    
    // MARK: - Private implementation details
    
    private let setter: ManagedValue<MyData>.Setter
    
    init() {
        (myData, setter) = ManagedValue.create(
            defaultValue: MyData(name: "", number: 0)
        )
    }
}

//  Usage:
extension MyDataManager {
    static let shared = MyDataManager()
}

let cancellable = await MyDataManager.shared.myData.observe(\.name) { name in
    print("Name is now: \(name)")
}

try await MyDataManager.shared.updateName(value: "Jo")
```
