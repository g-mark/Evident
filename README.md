# Evident

Thread-safe components for working with Swift Concurrency.

## Networking

### AuthorizationProvider

Use an [AuthorizationProvider](Docs/AuthorizationProvider.md) to manage the process of authorizing `URLRequest`s - specifically, working with a token refresh flow.

## Messaging

Publish & Subscribe using a simple one-to-many [MessageQueue](Sources/Evident/Messaging/MessageQueue.swift).

## Value Observation

Hold a value that can be observed for changes - in whole or in part - using an [ObserervableValue](Sources/Evident/Observation/ObservableValue.swift) - an alternative to `@Observable`.

### ManagedValue

Create composite "data manager" / repository actors using a [`ManagedValue`](Sources/Evident/Observation/ManagedValue.swift).  A `ManagedValue` is a read-only, optionally cached, `ObserervableValue`, with controlled mutability via special "setter" object.

### Data Manager

This is an example of the kind of use case `ManagedValue` was made for: a single-source of truth for some data in an app. [Read more about data managers](Docs/DataManager.md)