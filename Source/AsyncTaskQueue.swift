//
//  AsyncTaskQueue.swift
//  AsyncOperations
//
//  Created by Jared Sinclair on 10/18/16.
//  Copyright © 2016 Nice Boy LLC. All rights reserved.
//

import Foundation

/// AsyncTaskQueue manages an operation queue of AsyncTaskOperations, ensuring
/// that long-running work is only performed once per a unique user-provided
/// task identifier.
/// 
/// You might choose an AsyncTaskQueue when there is an expensive unit of work
/// which is repeatedly requested from multiple callers. Rather than performing
/// that work multiple times for each caller, AsyncTaskQueue coalesces those
/// requests into a single AsyncTaskOperation, distributing the shared result 
/// among all callers.
/// 
/// A unit of work is identified by a user-provided task identifer (the `TaskID`
/// generic type). Two tasks using the same task identifer are assumed to 
/// produce an identical result (given the same environmental conditions). Task
/// blocks submitted to AsyncTaskQueue should be aware therefore that they are
/// not guaranteed to each be executed. If an existing task operation exists for
/// a given task id, subsequent task blocks for that same id will be quietly
/// ignored.
/// 
/// The generic `<Result>` parameter allows for domain-specific flexibility. For
/// example, an image cache might only need something as simple as a `UIImage?`,
/// whereas a more complex task might use a custom enum with success and error
/// cases.
///
/// AsyncTaskQueue does not cache results. Non-concurrent requests for the same 
/// task identifier may result in duplicate task operations if the earlier task 
/// operation finishes before the next task request arrives. It is the caller's
/// responsiblity to cache results if needed and to ensure that subsequent tasks 
/// aren't needlessly requested.
///
/// Requests can be cancelled individually. Each request has its own preferred
/// queue priority, but the priority of the underlying task operation resolves 
/// to the highest priority among the active requests. Adding or cancelling 
/// requests will cause the resolved priority to be recomputed. If the last 
/// remaining request is cancelled, the whole task operation will be cancelled.
public class AsyncTaskQueue<TaskID: Hashable, Result> {
    
    // MARK: Public Typealiases
    
    /// The type of a task block.
    public typealias Task = (@escaping Finish) -> Void
    
    /// The type of a finish handler passed to a task block.
    public typealias Finish = (Result) -> Void
    
    /// The type of a cancellation handler.
    public typealias Cancellation = () -> Void
    
    /// The tokens returned from each request.
    public typealias RequestToken = AsyncTaskOperation<Result>.RequestToken
    
    /// The type of a result handler.
    public typealias ResultHandler = (Result) -> Void
    
    /// The type of a request token handler.
    public typealias RequestTokenHandler = (RequestToken) -> Void
    
    // MARK: Private Typealiases
    
    private typealias TaskOperation = AsyncTaskQueueOperation<TaskID, Result>
    
    // MARK: Private Properties
    
    private let operationQueue: OperationQueue
    
    private var taskOperations: [TaskID: TaskOperation] {
        let ops = operationQueue.operations as! [TaskOperation]
        var dictionary = [TaskID: TaskOperation]()
        ops.forEach { dictionary[$0.taskID] = $0 }
        return dictionary
    }
    
    // MARK: Init
    
    /// Designated initializer. The optional parameters roughly correspond to
    /// the similarly-named properties of (NS)OperationQueue.
    public init(maxConcurrentTasks: Int = OperationQueue.defaultMaxConcurrentOperationCount, defaultQualityOfService: QualityOfService = .background) {
        
        operationQueue = {
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = maxConcurrentTasks
            queue.qualityOfService = defaultQualityOfService
            return queue
        }()
        
    }
    
    // MARK: Public Methods

    /// Enqueues a request for a task block.
    /// 
    /// If an existing task already exists for the task id, this request will be
    /// appended to the existing task operation's requests. Otherwise, a new
    /// task operation will be created with this request as the initial request.
    /// 
    /// - note: It is also possible that there is an existing task operation 
    /// but the request could not be added to it because the operation was 
    /// cancelled (or cancelling) or finished (or finishing). This is not likely
    /// to occur often. If it occurs, a new task operation will be created and 
    /// the request will be added to it.
    /// 
    /// - parameter task: The task block. This block will be quietly ignored if
    /// an existing task operation already exists for `taskId`.
    /// 
    /// - parameter taskId: The unique, user-provided identifier for the task.
    /// Two task blocks with equal task identifiers, assuming the same 
    /// environmental conditions, should produce identical results. For example,
    /// an image cache using a task queue might use image URLs for task ids.
    /// 
    /// - parameter cancellation: The block which will be invoked if the task
    /// later becomes cancelled. This should stop any child procedures spawned
    /// by the task block. This block will be quietly ignored if an existing
    /// task operation already exists for `taskId`.
    /// 
    /// - parameter preferredPriority: The priority at which the task operation
    /// is preferred to run. The actual priority of a task operation resolves to
    /// the highest requested priority among its active requests. Callers are
    /// thus guaranteed that the task will be performed at or above their
    /// requested priority level.
    /// 
    /// - parameter tokenHandler: A non-escaping closure which passes the 
    /// request token back to the caller. See the documentation for 
    /// `AsyncTaskOperation` for details on why this is a non-escaping closure
    /// rather than a return value.
    /// 
    /// - parameter resultHandler: A handler via which the caller will recieve
    /// the result of the task. A task is only performed once, but the result
    /// will be distributed among all requests by invoking each one's result
    /// handler. This block will not be called if the task is cancelled before
    /// it finishes.
    public func enqueue(task: @escaping Task, taskId: TaskID, cancellation: @escaping Cancellation, preferredPriority: Operation.QueuePriority = .normal, tokenHandler: RequestTokenHandler, resultHandler: @escaping ResultHandler) {
        
        // We'll check this in a moment.
        var needToCreateNewOperation = true
        
        // Attempt to add this request to an existing operation, if any exists 
        // that is in a state to allow adding additional requests.
        taskOperations[taskId]?.addRequest(
            preferredPriority: preferredPriority,
            tokenHandler: { token in
                if let token = token {
                    needToCreateNewOperation = false
                    tokenHandler(token)
                }
            },
            resultHandler: resultHandler
        )
        
        // If adding a request failed, create a new operation and add this
        // request as its first request.
        if needToCreateNewOperation {
            let operation = TaskOperation(
                taskID: taskId,
                task: task,
                cancellation: cancellation,
                preferredPriority: preferredPriority,
                tokenHandler: tokenHandler,
                resultHandler: resultHandler
            )
            operationQueue.addOperation(operation)
        }
        
    }
    
    /// Cancels the request for `token`. If this was the last remaining request
    /// for the associated task operation, the operation will be cancelled.
    public func cancelRequest(with token: RequestToken) {
        // Calling `forEach` is just as efficient as searching for a task with
        // a matching request ID. This also covers the very remote possiblity
        // of a request ID collision across two tasks, as well as the less 
        // remote possibility that two tasks with the same id will be in the
        // operation queue, however briefly.
        taskOperations.forEach { $0.1.cancelRequest(with: token) }
    }
    
    /// Adjusts the requested priority for the request with `token`. The task
    /// operation's actual priority will resolve to the highest requested
    /// priority among all its active requests.
    public func adjustPriorityForRequest(with token: RequestToken, preferredPriority: Operation.QueuePriority) {
        // Calling `forEach` is just as efficient as searching for a task with
        // a matching request ID. This also covers the very remote possiblity
        // of a request ID collision across two tasks, as well as the less
        // remote possibility that two tasks with the same id will be in the
        // operation queue, however briefly.
        taskOperations.forEach {
            $0.1.adjustPriorityForRequest(
                with: token,
                preferredPriority: preferredPriority
            )
        }
    }
    
}

private class AsyncTaskQueueOperation<TaskID: Hashable, Result>: AsyncTaskOperation<Result> {
    
    let taskID: TaskID
    
    init(taskID: TaskID, task: @escaping Task, cancellation: @escaping Cancellation) {
        self.taskID = taskID
        super.init(task: task, cancellation: cancellation)
    }
    
    init(taskID: TaskID, task: @escaping Task, cancellation: @escaping Cancellation, preferredPriority: Operation.QueuePriority, tokenHandler: (RequestToken) -> Void, resultHandler: @escaping ResultHandler) {
        
        self.taskID = taskID
        super.init(
            task: task,
            cancellation: cancellation,
            preferredPriority: preferredPriority,
            tokenHandler: tokenHandler,
            resultHandler: resultHandler
        )
        
    }
}
