# AsyncOperations

A toolbox of NSOperation subclasses for a variety of asynchronous programming needs.

## Just Show Me The Source

- [AsyncOperation](https://github.com/jaredsinclair/AsyncOperations/blob/master/Source/AsyncOperation.swift) *is the abstract base class used throughout.*

- [AsyncBlockOperation](https://github.com/jaredsinclair/AsyncOperations/blob/master/Source/AsyncBlockOperation.swift) *offers simple asynchronous execution of a block.*

- [AsyncTaskOperation](https://github.com/jaredsinclair/AsyncOperations/blob/master/Source/AsyncTaskOperation.swift) *manages multiple requests, passing a shared generic result back to all callers.*

- [AsyncTaskQueue](https://github.com/jaredsinclair/AsyncOperations/blob/master/Source/AsyncTaskQueue.swift) *coalesces identical task operations so expensive work is only performed once.*

## Asynchronous NSOperations

Generally speaking, NSOperation makes it easy to chain together dependencies among multiple operations. Consider a sequence of NSBlockOperations:

```swift
let one = BlockOperation {
    print("One")
}

let two = BlockOperation {
    print("Two")
}

two.addDependency(one)

// Prints:
//    One
//    Two
```

But what happens if you have a block that must be executed asynchronously?

```swift
let one = BlockOperation {
  doSomethingSlowly(completion:{
    print("One")
  })
}

let two = BlockOperation {
  print("Two")
}

two.addDependency(one)

// Prints:
//  Two
//  One
```

There are at least two problems here. Of course our output is now printing in the wrong order, but notice also that there’s no way to cancel `one` after it has called `doSomethingSlowly()`. As far as NSOperationQueue is concerned, that operation has already finished, despite the fact that we haven’t yet received our result.

To solve both of these problems, we would need to change the behavior of NSBlockOperation so that it isn’t marked finished until we say so. Since we can’t change the behavior of that class, we’d have to write our own NSOperation subclass with that capability:

```swift
let one = MyAsynchrousOperation { finish in
  doSomethingSlowly(completion:{
    print(“One”)
    finish()
  }
}

let two = BlockOperation {
  print("Two")
}

two.addDependency(one)

// Prints:
//  One
//  Two
```

Writing NSOperation subclasses is something every Swift developer should know how to do, but it’s still a pain in the a**. It would be preferable to have an abstract base class that subclasses NSOperation, adding built-in support for asynchronous execution in a way that can be extended for any arbitrary purpose. That’s what `AsyncOperations` aims to provide.

## AsyncOperations

There are four classes in AsyncOperations:

- **AsyncOperation:** An abstract base class that subclasses NSOperation. This class handles all the annoying boilerplate of an NSOperation subclass (including the KVO notifications around execution and cancellation). This class is not meant to be used directly, but via concrete subclasses. You can write your own subclasses, but there are two subclasses provided for you which cover common use cases.

- **AsyncBlockOperation:** Similar to NSBLockOperation, except it only accepts a single execution block. The operation will not be marked finished until the execution block invokes its lone finish handler argument.

- **AsyncTaskOperation:** This generic class provides support for associating multiple requests for a given result with a single operation. The shared result of the operation (of the generic `<Result>` type) will be distributed among all the operation’s active requests. You can use AsyncTaskOperation directly in your own NSOperationQueues, or you can use it implicitly via `AsyncTaskQueue`.

- **AsyncTaskQueue:** This generic class acts as a convenient wrapper around an NSOperationQueue of AsyncTaskOperations. It coalesces requested tasks with matching identifiers into a single task operation, so that expensive work is only performed once, even if it requested concurrently from isolated callers. A classic use case for this class would be in the implementation details of an offline image cache.

## Examples

- [ImageCache.swift](https://github.com/jaredsinclair/AsyncOperations/blob/master/Project/Examples/ImageCache.swift). A simplified version of an image cache that uses a private AsyncTaskQueue to coalesce concurrent requests for the same image into a single task operation, passing the resulting image back to all callers.

- [HeadRequestOperation.swift](https://github.com/jaredsinclair/AsyncOperations/blob/master/Project/Examples/HeadRequest.swift).  A contrived example of a concrete AsyncOperation subclass, illustrating how a subclass must implement the required `execute(finish:)` method. This class makes a HEAD request for an arbitrary URL, returning the result via a completion block.

- [Blocks.swift](https://github.com/jaredsinclair/AsyncOperations/blob/master/Project/Examples/Blocks.swift). Simple example of how you would chain together AsyncBlockOperations using the standard NSOperation dependency API.
