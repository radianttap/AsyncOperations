//
//  AsyncBlockOperation.swift
//  AsyncOperations
//
//  Created by Jared Sinclair on 10/18/16.
//  Copyright © 2016 Nice Boy LLC. All rights reserved.
//

import Foundation

/// A concrete subclass of AsyncOperation for executing an arbitrary block of
/// asynchronous code. 
/// 
/// AsyncBlockOperation is similar to (NS)BlockOperation, except for two important differences:
///
/// - AsyncBlockOperation only supports a single execution block.
///
/// - AsyncBlockOperation will remain in its executing state until the
/// execution block invokes its finish handler argument. This makes it easier to
/// establish dependencies with other (NS)Operations. It is up to the caller to
/// ensure that the finish handler is invoked when the block is done.
@objc(JTSAsyncBlockOperation)
public class AsyncBlockOperation: AsyncOperation {
    
    // MARK: Typealiases
    
    /// The type of the finish handler argument passed to an execution block.
    public typealias Finish = () -> Void
    
    /// The type of an execution block.
    public typealias Execution = (@escaping Finish) -> Void
    
    // MARK: Private Properties
    
    private let execution: Execution
    
    // MARK: Init
    
    /// Designated initializer.
    ///
    /// - parameter execution: The execution block. This will be invoked from a
    /// private dispatch queue. Implementations **must** invoke the finish
    /// handler argument when done or else the AsyncBlockOperation will remain
    /// executing indefinitely.
    public init(execution: @escaping Execution) {
        self.execution = execution
    }
    
    // MARK: AsyncOperation
    
    public override func execute(finish: @escaping () -> Void) {
        execution(finish)
    }
    
}
