//
//  CachedManagedValueTests.swift
//  Evident
//
//  Created by Steven Grosmark on 10/14/23.
//

import Testing
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

@Suite(.serialized)
struct CachedManagedValueTests {

    private let cache: MemoryCache<Thing>
    private let managedValue: ManagedValue<Thing>
    private let setter: ManagedValue<Thing>.Setter

    init() {
        cache = MemoryCache<Thing>(nil)
        (managedValue, setter) = ManagedValue.create(
            cache: cache,
            defaultValue: defaultVaue
        )
    }

    @Test func managerUsesDefaultValue() async throws {
        let observer = Observer<Thing>()
        var cancellables: [AnyCancellableAsync] = []

        // when
        managedValue.observe { thing in
            await observer.collect(thing)
        }
        .store(in: &cancellables)

        // then
        let thing = try await eventually { await observer.values.first }
        #expect(thing == defaultVaue)
        _ = cancellables
    }

    @Test func managerReadsFromCache() async throws {
        let observer = Observer<Thing>()
        var cancellables: [AnyCancellableAsync] = []

        // when
        await cache.store(initialCacheVaue)
        managedValue.observe { thing in
            await observer.collect(thing)
        }
        .store(in: &cancellables)

        // then
        let thing = try await eventually { await observer.values.first }
        #expect(thing == initialCacheVaue)
        _ = cancellables
    }

    @Test func managerWritesToCache() async throws {
        let observer = Observer<String>()
        var cancellables: [AnyCancellableAsync] = []

        // when
        managedValue.observe(\.name) { name in
            await observer.collect(name)
        }
        .store(in: &cancellables)

        // then
        let name = try await eventually { await observer.values.first }
        #expect(name == "")

        // when
        await setter.set(\.name, value: "pat")

        // then
        try await eventually {
            await cache.value == Thing(name: "pat", number: defaultVaue.number)
        }
        _ = cancellables
    }
}
