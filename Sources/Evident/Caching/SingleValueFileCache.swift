//
//  SingleValueFileCache.swift
//  Evident
//
//  Created by Steven Grosmark on 10/14/23.
//

import Foundation

/// A ``SingleValueCache`` that persists a `Codable` value to disk as JSON.
///
/// Writes are debounced to avoid excessive I/O. The cached file is stored in the
/// system caches directory, keyed by value type and a caller-provided key.
///
/// ```swift
/// let cache = SingleValueFileCache<UserSettings>(key: "settings", ttlInSeconds: 3600)
/// await cache.store(settings)
/// ```
///
/// > Note: when a `SingleValueFileCache` is released, any pending writes will still happen.
/// > Call `flushPendingWork()` before releasing an instance to immediately write any pending
/// > data to the backing file.
public actor SingleValueFileCache<Value: Codable & Sendable>: SingleValueCache {
    
    enum State {
        case uninitialized
        case empty
        case full(Value, Date)
    }
    
    private let key: String
    private let ttlInSeconds: TimeInterval
    private let work: DebouncedWork
    
    private var state: State
    
    /// Creates a file-backed single value cache.
    ///
    /// - Parameters:
    ///   - key: A unique key used as the filename for the cached value.
    ///   - ttlInSeconds: The time-to-live in seconds; values older than this are considered stale.
    public init(key: String, ttlInSeconds: TimeInterval) {
        self.key = key
        self.ttlInSeconds = ttlInSeconds
        work = DebouncedWork(threshold: 1.0)
        state = .uninitialized
    }
    
    deinit {
        
    }
    
    /// Retrieves the cached value, if available.
    ///
    /// - Returns: A tuple of the cached value and whether it is stale, or `nil` if no value is cached.
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
    
    /// Stores a value in the cache.
    ///
    /// - Parameter value: The value to cache.
    public func store(_ value: Value) async {
        let now = Date()
        self.state = .full(value, now)
        await work.enqueue {
            await self.persist(value, now)
        }
    }
    
    /// Immediately persists any pending write operations.
    public func flushPendingWork() async {
        await work.flushPendingWork()
    }
    
    /// Clears the cache, removing any stored value and cancelling pending writes.
    public func clear() async {
        await work.cancel()
    }
    
    // MARK: Implementation details
    
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

