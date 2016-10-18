//
//  AsyncOperation.swift
//  AsyncOperations
//
//  Created by Jared Sinclair on 10/18/16.
//  Copyright © 2016 Nice Boy LLC. All rights reserved.
//

import Foundation

/// An abstract subclass of (NS)Operation which allows for the asynchronous 
/// execution of arbitrary code. Unlike most (NS)Operations, an AsyncOperation
/// will remain in its executing state until the asynchronous execution signals
/// that it has finished. This makes it possible to compose complex behaviours
/// out of a mixture of asynchronous and synchronous operations, and with all
/// the benefits of using an (NS)OperationQueue (dependency chaining, 
/// cancellation, priorities, etc).
/// 
/// AsyncOperation is not meant to be used directly, but only via concrete 
/// subclasses. Subclasses must override `execute(finish:)` (see below).
@objc(JTSAsyncOperation)
open class AsyncOperation: Operation {
    
    // MARK: Private Properties
    
    /// The dispatch queue on which the execution method will be invoked.
    private let executionQueue: DispatchQueue
    
    /// The completion blocks which will be invoked when the operation finishes.
    private var completionHandlers = [() -> Void]()
    
    /// A lock used to synchronize access to `completionHandlers`.
    private var lock = NSLock()

    // MARK: Init / Deinit
    
    /// Designated initializer.
    ///
    /// - parameter completion: Will be invoked when the operation finishes.
    public override init() {
        self.executionQueue = DispatchQueue(
            label: "com.niceboy.AsyncOperation.executionQueue",
            qos: .background
        )
        super.init()
    }
    
    // MARK: Public Methods
    
    /// Adds a completion handler to be invoked when the operation is finished.
    /// All completion handlers will be called on the main queue. The operation
    /// will not be marked as finished until all completion handlers have been
    /// called.
    public func addCompletionHandler(_ handler: @escaping () -> Void) {
        guard !isCancelled && !isFinished else {return}
        lock.lock()
        completionHandlers.append(handler)
        lock.unlock()
    }
    
    // MARK: Required Methods for Subclasses
    
    /// Begins execution of the asynchronous work. This method will *not* be
    /// called from the AsyncOperation's operation queue, but rather from a
    /// private dispatch queue (the reasons why should be obvious).
    /// 
    /// - Warning: Subclass implementations must invoke `finish` when done. If
    /// you do not invoke `finish`, the operation will remain in its executing
    /// state indefinitely.
    open func execute(finish: @escaping () -> Void) {
        assertionFailure("Subclasses must override without calling super.")
    }
    
    // MARK: NSOperation
    
    override open func start() {
        guard !isCancelled else {return}
        markAsExecuting()
        executionQueue.async { [weak self] in
            guard let this = self else {return}
            this.execute { [weak this] (result) in
                DispatchQueue.main.async {
                    guard let this = this else {return}
                    guard !this.isCancelled else {return}
                    this.lock.lock()
                    let handlers = this.completionHandlers
                    this.lock.unlock()
                    handlers.forEach{$0()}
                    this.markAsFinished()
                }
            }
        }
    }
    
    override open var isAsynchronous: Bool {
        return true
    }
    
    fileprivate var _finished: Bool = false
    override open var isFinished: Bool {
        get { return _finished }
        set { _finished = newValue }
    }
    
    fileprivate var _executing: Bool = false
    override open var isExecuting: Bool {
        get { return _executing }
        set { _executing = newValue }
    }
    
}

fileprivate extension AsyncOperation {
    
    // MARK: Fileprivate
    
    func markAsExecuting() {
        willChangeValue(for: .isExecuting)
        _executing = true
        didChangeValue(for: .isExecuting)
    }
    
    func markAsFinished() {
        willChangeValue(for: .isExecuting)
        willChangeValue(for: .isFinished)
        _executing = false
        _finished = true
        didChangeValue(for: .isExecuting)
        didChangeValue(for: .isFinished)
    }
    
    // MARK: Private
    
    private func willChangeValue(for key: OperationChangeKey) {
        self.willChangeValue(forKey: key.rawValue)
    }
    
    private func didChangeValue(for key: OperationChangeKey) {
        self.didChangeValue(forKey: key.rawValue)
    }
    
    private enum OperationChangeKey: String {
        case isFinished
        case isExecuting
    }
    
}
