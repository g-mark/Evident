# Evident

Thread-safe components for working with Swift Concurrency.

## Networking

### AuthorizationProvider

Use an [AuthorizationProvider](Docs/AuthorizationProvider.md) to manage the process of authorizing `URLRequest`s - specifically, working with a token refresh flow.

## Messaging

Publish & Subscribe using a simple [MessageQueue](Sources/Evident/Messaging/MessageQueue.swift).

## Value Observation

Hold a value that can be observed for changes - in whole or in part - using an [ObserervableValue](Sources/Evident/Observation/ObservableValue.swift) - an alternative to `@Observable`.