//
//  SingleValueFileCache.swift
//  Evident
//
//  Created by Steven Grosmark on 10/14/23.
//

import Foundation

public actor SingleValueFileCache<Value: Codable>: SingleValueCache {
    
    enum State {
        case uninitialized
        case empty
        case full(Value, Date)
    }
    
    private let key: String
    private let ttlInSeconds: TimeInterval
    private let work: DebouncedWork
    
    private var state: State
    
    public init(key: String, ttlInSeconds: TimeInterval) {
        self.key = key
        self.ttlInSeconds = ttlInSeconds
        work = DebouncedWork(threshold: 1.0)
        state = .uninitialized
    }
    
    public func retrieve() async -> (value: Value, isStale: Bool)? {
        if case .uninitialized = state {
            state = initialize()
        }
        
        switch state {
        case .uninitialized, .empty: return nil
        case .full(let value, let lastSaveTime):
            return (value, lastSaveTime.addingTimeInterval(ttlInSeconds) >= Date())
        }
    }
    
    public func store(_ value: Value) async {
        let now = Date()
        self.state = .full(value, now)
        await work.enqueue {
            await self.persist(value, now)
        }
    }
    
    public func flushPendingWork() async {
        await work.flushPendingWork()
    }
    
    public func clear() async {
        await work.cancel()
    }
    
    private func initialize() -> State {
        let fileManager = FileManager.default
        let url = try? fileManager.url(for: .cachesDirectory, in: .localDomainMask, appropriateFor: nil, create: true)
        
        guard let fileUrl = url?.appending(components: "\(Value.self)", key),
              fileManager.fileExists(atPath: fileUrl.absoluteString) else {
            return .empty
        }
        guard let data = try? Data(contentsOf: fileUrl),
              let persistedValue = try? JSONDecoder().decode(PersistedValue.self, from: data) else {
            try? fileManager.removeItem(at: fileUrl)
            return .empty
        }
        
        return .full(persistedValue.value, persistedValue.lastSaveTime)
    }
    
    private func persist(_ value: Value, _ saveTime: Date) async {
        let fileManager = FileManager.default
        let url = try? fileManager.url(for: .cachesDirectory, in: .localDomainMask, appropriateFor: nil, create: true)
        
        guard let fileUrl = url?.appending(components: "\(Value.self)", key) else {
            return
        }
        
        if let data = try? JSONEncoder().encode(PersistedValue(value: value, lastSaveTime: saveTime)) {
            try? data.write(to: fileUrl)
        }
    }
    
    struct PersistedValue: Codable {
        let value: Value
        let lastSaveTime: Date
    }
}

