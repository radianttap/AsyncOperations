//
//  AsyncTaskQueue.swift
//  AsyncOperations
//
//  Created by Jared Sinclair on 10/18/16.
//  Copyright © 2016 Nice Boy LLC. All rights reserved.
//

import Foundation

public class AsyncTaskQueue<TaskID: Hashable, Result> {
    
    // MARK: Public Typealiases
    
    public typealias Task = (@escaping Finish) -> Void
    public typealias Finish = (Result) -> Void
    public typealias Cancellation = () -> Void
    public typealias RequestToken = NSUUID
    public typealias ResultHandler = (Result) -> Void
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
    
    public init(maxConcurrentTasks: Int = OperationQueue.defaultMaxConcurrentOperationCount, defaultQualityOfService: QualityOfService = .background) {
        
        operationQueue = {
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = maxConcurrentTasks
            queue.qualityOfService = defaultQualityOfService
            return queue
        }()
        
    }
    
    // MARK: Public Methods
    
    public func enqueue(task: @escaping Task, taskId: TaskID, cancellation: @escaping Cancellation, priority: Operation.QueuePriority = .normal, tokenHandler: RequestTokenHandler, resultHandler: @escaping ResultHandler) {
        
        // We'll check this in a moment.
        var needToCreateNewOperation = true
        
        // Attempt to add this request to an existing operation, if any exists 
        // that is in a state to allow adding additional requests.
        taskOperations[taskId]?.addRequest(
            priority: priority,
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
                priority: priority,
                tokenHandler: tokenHandler,
                resultHandler: resultHandler
            )
            operationQueue.addOperation(operation)
        }
        
    }
    
    public func cancelRequest(with token: RequestToken) {
        // Calling `forEach` is just as efficient as searching for a task with
        // a matching request ID. This also covers the very remote possiblity
        // of a request ID collision across two tasks.
        taskOperations.forEach { $0.1.cancelRequest(with: token) }
    }
    
    public func adjustPriorityForRequest(with token: RequestToken, priority: Operation.QueuePriority) {
        // Calling `forEach` is just as efficient as searching for a task with
        // a matching request ID. This also covers the very remote possiblity
        // of a request ID collision across two tasks.
        taskOperations.forEach {
            $0.1.adjustPriorityForRequest(with: token, priority: priority)
        }
    }
    
}

private class AsyncTaskQueueOperation<TaskID: Hashable, Result>: AsyncTaskOperation<Result> {
    
    let taskID: TaskID
    
    init(taskID: TaskID, task: @escaping Task, cancellation: @escaping Cancellation) {
        self.taskID = taskID
        super.init(task: task, cancellation: cancellation)
    }
    
    init(taskID: TaskID, task: @escaping Task, cancellation: @escaping Cancellation, priority: Operation.QueuePriority, tokenHandler: (RequestToken) -> Void, resultHandler: @escaping ResultHandler) {
        
        self.taskID = taskID
        super.init(
            task: task,
            cancellation: cancellation,
            priority: priority,
            tokenHandler: tokenHandler,
            resultHandler: resultHandler
        )
        
    }
}
