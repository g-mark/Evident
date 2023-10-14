//
//  UncachedDataManagerTests.swift
//  Evident
//
//  Created by Steven Grosmark on 10/14/23.
//

import XCTest
import Combine
import Evident

private struct MyData: Equatable {
    var name: String
    var number: Int
}

/// Sample "data manager" using a `ManagedValue`.
///
/// A "data manager" is an abstraction layer that can be thought of as a "repository" pattern,
/// It provides read access to some data, which can be observerd for changes.
/// It provides write access through dedicated methods, where there is some extra
/// business logic and/or communication with a [back end] service.
///
/// - minimal boilerplate around setting up the managed value
/// - external read-only access to the value
/// - internal only write access
/// - optional caching
private actor MyDataManager {
    
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
    
    // MARK: - Implementation details
    
    private let setter: ManagedValue<MyData>.Setter
    
    init() {
        (myData, setter) = ManagedValue.create(
            defaultValue: MyData(name: "", number: 0)
        )
    }
}

final class UncachedDataManagerTests: XCTestCase {
    
    private actor Observer<T> {
        var values: [T] = []
        func collect(_ value: T) async { values.append(value) }
        func reset() async { values = [] }
    }
    
    private var manager: MyDataManager!
    private var cancellables: [AnyCancellable] = []
    
    override func setUp() async throws {
        try await super.setUp()
        
        manager = MyDataManager()
    }
    
    override func tearDown() async throws {
        manager = nil
        cancellables = []
        try await super.tearDown()
    }
    
    func test_myDataManager() async throws {
        let observer = Observer<String>()
        
        // when
        await manager.myData.observe(\.name) { name in
            await observer.collect(name)
        }.store(in: &cancellables)
        
        // then
        var name = try await eventually { await observer.values.first }
        XCTAssertEqual(name, "")
        
        // when
        await observer.reset()
        try await manager.updateName(value: "pat")
        
        // then
        name = try await eventually { await observer.values.first }
        XCTAssertEqual(name, "pat")
        
        let myData = await manager.myData.value
        XCTAssertEqual(myData, MyData(name: "pat", number: 0))
    }
}
