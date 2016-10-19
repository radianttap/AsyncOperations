//
//  AsyncTaskOperation.swift
//  AsyncOperations
//
//  Created by Jared Sinclair on 10/18/16.
//  Copyright © 2016 Nice Boy LLC. All rights reserved.
//

import Foundation

/// A generic subclass of AsyncOperation which manages a one-to-many 
/// relationship between itself and a dynamic number of requests. The result of 
/// the task execution is distributed among all active requests.
///
/// The generic `<Result>` parameter allows for domain-specific flexibility. For 
/// example, an image cache might only need something as simple as a `UIImage?`,
/// whereas a more complex task might use a custom enum with success and error
/// cases.
///
/// Requests can be cancelled individually. Each request has its own preferred
/// queue priority, but the priority of the task operation resolves to the
/// highest priority among the active requests. Adding or cancelling requests
/// will cause the resolved priority to be recomputed. If the last remaining
/// request is cancelled, the operation itself will be cancelled.
/// 
/// AsyncTaskOperation can be used by itself, or in combination with other
/// (NS)Operations in your own (NS)OperationQueue. 
/// 
/// If you need to also ensure that a given task is only performed once per some
/// arbitrary task identifier (again, an image cache is a good example) consider
/// using AsyncTaskQueue.
/// 
/// - seealso: AsyncTaskQueue
public class AsyncTaskOperation<Result>: AsyncOperation {
    
    // MARK: Typealiases
    
    public typealias Task = (@escaping Finish) -> Void
    public typealias Finish = (Result) -> Void
    public typealias Cancellation = () -> Void
    public typealias RequestToken = NSUUID
    public typealias ResultHandler = (Result) -> Void
    public typealias RequestTokenHandler = (RequestToken?) -> Void
    
    // MARK: Private Properties
    
    private let task: Task
    private let cancellation: Cancellation
    private let lock = NSLock()
    private var isCancelling = false
    private var isFinishing = false
    private var unsafe_requests = [RequestToken: Request<Result>]()
    
    // MARK: Init
    
    /// Simple initializer.
    /// 
    /// - parameter task: The closure in which the work should be executed. This
    /// will be invoked from a private dispatch queue. Implementations can use
    /// whatever asynchronous procedures they wish. The only obligation is to
    /// invoke the finish function passed to the task closure when the task is
    /// finished. If you fail to invoke the finish function, the task will 
    /// remain in its executing state indefinitely.
    /// 
    public init(task: @escaping Task, cancellation: @escaping Cancellation) {
        self.task = task
        self.cancellation = cancellation
    }
    
    /// Advanced initializer that adds the first request to the operation as
    /// soon as it is initialized. This is the only way to guarantee that the
    /// first request will be successfully added (see the documention for
    /// `addRequest(preferredPriority:tokenHandler:resultHandler)` for
    /// additional information about this issue).
    public init(task: @escaping Task, cancellation: @escaping Cancellation, preferredPriority: Operation.QueuePriority, tokenHandler: (RequestToken) -> Void, resultHandler: @escaping ResultHandler) {
        
        self.task = task
        self.cancellation = cancellation
        
        super.init()
        
        addRequest(
            preferredPriority: preferredPriority,
            tokenHandler: { token in
                tokenHandler(token!)
            },
            resultHandler: resultHandler
        )
        
    }
    
    // MARK: Public Methods
    
    /// Adds an additional request to the task.
    /// 
    /// - parameter preferredPriority: The task operation's actual priority will
    /// resolve to the highest preferred priority among its active requests.
    /// 
    /// - parameter tokenHandler: A non-escaping closure via which the request 
    /// token for this request is passed back to the caller. If the token is 
    /// nil, the request could not be added (see notes below).
    /// 
    /// - parameter resultHandler: A closure which will be called when the 
    /// task operation finishes and produces a result. The same result will be
    /// distributed to the result handlers of all active requests. This closure
    /// will be invoked on the main queue.
    /// 
    /// ### Avoiding Race Conditions
    /// 
    /// Adding requests to a task operation is a highly race-dependent feature.
    /// Therefore a request cannot be guaranteed to be added. If the operation
    /// is cancelled (or about to be cancelled) or finished (or about to be
    /// finished), it cannot accept additional requests.
    /// 
    /// Rather than silently failing to add a request, `addRequest()` will
    /// communicate to the caller whether or not the request was successfully
    /// added via the `tokenHandler` closure argument. This closure receives an
    /// optional RequestToken argument. If this argument is `nil`, the request
    /// failed to be added. If this argument is not nil, the caller can assume
    /// that the `resultHandler` will be called at some point in the future
    /// (unless, of course, the operation is later cancelled, in which case the
    /// result handlers are not called by design).
    ///
    /// It is critical to notice that the token handler is non-escaping. This is
    /// because otherwise `addRequest()` could not guarantee that the calling
    /// thread has a chance to capture the token value **before the result 
    /// handler could possibly be called**. If, for example, the request token 
    /// was a returned value, and if the calling thread was part of a concurrent
    /// queue, it would be possible for the result handler to be called (on the
    /// main queue) at the same time as or before the calling thread can store 
    /// the token value. It is conceivable that an implementation might need to
    /// use the request token as part of updating some other internal state in a
    /// manner that is guaranteed to occur before the result handler fires (for 
    /// example, showing/hiding an indeterminate activity indicator).
    public func addRequest(preferredPriority: Operation.QueuePriority = .normal, tokenHandler: RequestTokenHandler = {_ in}, resultHandler: @escaping ResultHandler) {
        
        doLocked {
            let canContinue: Bool = {
                return !isCancelled
                    && !isCancelling
                    && !isFinishing
                    && !isFinished
            }()
            if canContinue {
                let request = Request(
                    preferredPriority: preferredPriority,
                    resultHandler: resultHandler
                )
                let token = request.token
                tokenHandler(token)
                unsafe_requests[request.token] = request
                self.queuePriority = unsafe_highestPriorityAmongRequests()
            } else {
                tokenHandler(nil)
            }
        }
        
    }
    
    /// Cancels the request for `token`, if it still exists.
    ///
    /// - parameter token: The request token received when adding the request.
    public func cancelRequest(with token: RequestToken) {
        
        var shouldCancelOperation = false

        doLocked {
            let canContinue: Bool = {
                return !isCancelled
                    && !isCancelling
                    && !isFinishing
                    && !isFinished
            }()
            if canContinue {
                if unsafe_requests[token] != nil {
                    unsafe_requests[token] = nil
                    queuePriority = unsafe_highestPriorityAmongRequests()
                    shouldCancelOperation = unsafe_requests.isEmpty
                }
            }
            if shouldCancelOperation {
                isCancelling = true
            }
        }
        
        if shouldCancelOperation {
            cancel()
        }
    }
    
    /// Adjusts the preferred priority of the request for `token`.
    ///
    /// - parameter token: The request token received when adding the request.
    ///
    /// - parameter preferredPriority: The task operation's actual priority will
    /// resolve to the highest preferred priority among its active requests.
    public func adjustPriorityForRequest(with token: RequestToken, preferredPriority: Operation.QueuePriority) {
        doLocked {
            unsafe_requests[token]?.preferredPriority = preferredPriority
            queuePriority = unsafe_highestPriorityAmongRequests()
        }
    }
    
    // MARK: AsyncOperation
    
    public override func execute(finish: @escaping () -> Void) {
        task { [weak self] (result) in
            DispatchQueue.main.async {
                guard let this = self else {return}
                var handlers: [ResultHandler]!
                this.doLocked {
                    this.isFinishing = true
                    handlers = this.unsafe_requests.map { $0.1.resultHandler }
                }
                handlers.forEach { $0(result) }
                finish()
            }
        }
    }
    
    // MARK: Operation
    
    public override func cancel() {
        var canContinue: Bool!
        doLocked {
            canContinue = {
                return !isCancelled
                    && !isCancelling
                    && !isFinishing
                    && !isFinished
            }()
        }
        guard canContinue! else {return}
        cancellation()
        super.cancel()
    }
    
    // MARK: Private Methods
    
    private func unsafe_highestPriorityAmongRequests() -> Operation.QueuePriority {
        let priorities = unsafe_requests.flatMap({$0.1.preferredPriority.rawValue})
        if let max = priorities.max() {
            return Operation.QueuePriority(rawValue: max) ?? queuePriority
        } else {
            return queuePriority
        }
    }
    
    private func doLocked(block: () -> Void) {
        lock.lock()
        block()
        lock.unlock()
    }
    
}

private class Request<Result> {
    
    typealias ResultHandler = (Result) -> Void

    let token = NSUUID()
    let resultHandler: ResultHandler
    var preferredPriority: Operation.QueuePriority
    
    init(preferredPriority: Operation.QueuePriority, resultHandler: @escaping ResultHandler) {
        self.preferredPriority = preferredPriority
        self.resultHandler = resultHandler
    }
    
}
