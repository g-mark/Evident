//
//  UncachedManagedValueTests.swift
//  Evident
//
//  Created by Steven Grosmark on 10/14/23.
//

import XCTest
import Combine
import Evident

final class UncachedManagedValueTests: XCTestCase {
    
    private struct MyData: Equatable {
        var name: String
        var number: Int
    }
    
    private actor Observer<T> {
        var values: [T] = []
        func collect(_ value: T) async { values.append(value) }
        func reset() async { values = [] }
    }
    
    private var managedValue: ManagedValue<MyData>!
    private var setter: ManagedValue<MyData>.Setter!
    private var cancellables: [AnyCancellable] = []
    
    override func setUp() async throws {
        try await super.setUp()
        (managedValue, setter) = ManagedValue.create(defaultValue: MyData(name: "", number: 0))
    }
    
    override func tearDown() async throws {
        try await super.tearDown()
        managedValue = nil
        setter = nil
        cancellables = []
    }
    
    func test_manager() async throws {
        let observer = Observer<String>()
        
        // when
        await managedValue.observe(\.name) { name in
            await observer.collect(name)
        }.store(in: &cancellables)
        
        // then
        let name = try await eventually { await observer.values.first }
        XCTAssertEqual(name, "")
        
        // when
        await observer.reset()
        await setter.set(\.name, value: "pat")
        await setter.set(value: MyData(name: "pat", number: 1))
        await setter.set(value: MyData(name: "billie", number: 1))
        await setter.set(\.number, value: 2)
        
        // then
        try await eventually { await observer.values.count == 2 }
        let names = await observer.values
        XCTAssertEqual(names, ["pat", "billie"])
        
        let value = await managedValue.value
        XCTAssertEqual(value, MyData(name: "billie", number: 2))
    }
}
