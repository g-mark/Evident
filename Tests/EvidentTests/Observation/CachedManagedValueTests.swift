//
//  CachedManagedValueTests.swift
//  Evident
//
//  Created by Steven Grosmark on 10/14/23.
//

import XCTest
import Combine
@testable import Evident

private actor MemoryCache<Value>: SingleValueCache {
    var value: Value?
    init(_ value: Value? = nil) {
        self.value = value
    }
    func retrieve() async -> (value: Value, isStale: Bool)? { value.flatMap { ($0, false) } }
    func store(_ value: Value) async { self.value = value }
    func flushPendingWork() async { }
    func clear() async { value = nil }
}

private struct Thing: Codable, Equatable {
    var name: String
    var number: Int
}

private actor Observer<T> {
    var values: [T] = []
    func collect(_ value: T) async { values.append(value) }
    func reset() async { values = [] }
}

private let defaultVaue = Thing(name: "", number: 0)
private let initialCacheVaue = Thing(name: "Pat", number: 42)

final class CachedManagedValueTests: XCTestCase {
    
    private var cache: MemoryCache<Thing>!
    private var managedValue: ManagedValue<Thing>!
    private var setter: ManagedValue<Thing>.Setter!
    private var cancellables: [AnyCancellable] = []
    
    override func setUp() async throws {
        try await super.setUp()
        cache = MemoryCache<Thing>(nil)
        (managedValue, setter) = ManagedValue.create(
            cache: cache,
            defaultValue: defaultVaue
        )
    }
    
    override func tearDown() async throws {
        try await super.tearDown()
        managedValue = nil
        setter = nil
        cancellables = []
        cache = nil
    }
    
    func test_manager_usesDefaultValue() async throws {
        let observer = Observer<Thing>()
        
        // when
        managedValue.observe { thing in
            await observer.collect(thing)
        }
        .store(in: &cancellables)
        
        // then
        let thing = try await eventually { await observer.values.first }
        XCTAssertEqual(thing, defaultVaue)
    }
    
    func test_manager_readsFromCache() async throws {
        let observer = Observer<Thing>()
        
        // when
        await cache.store(initialCacheVaue)
        managedValue.observe { thing in
            await observer.collect(thing)
        }
        .store(in: &cancellables)
        
        // then
        let thing = try await eventually { await observer.values.first }
        XCTAssertEqual(thing, initialCacheVaue)
    }
    
    func test_manager_writesToCache() async throws {
        let observer = Observer<String>()
        
        // when
        managedValue.observe(\.name) { name in
            await observer.collect(name)
        }
        .store(in: &cancellables)
        
        // then
        let name = try await eventually { await observer.values.first }
        XCTAssertEqual(name, "")
        
        // when
        await setter.set(\.name, value: "pat")
        
        // then
        let cachedValue = try await eventually { await cache.value }
        XCTAssertEqual(cachedValue, Thing(name: "pat", number: defaultVaue.number))
    }
}
