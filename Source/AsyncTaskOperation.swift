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
    
    public init(task: @escaping Task, cancellation: @escaping Cancellation) {
        self.task = task
        self.cancellation = cancellation
    }
    
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
