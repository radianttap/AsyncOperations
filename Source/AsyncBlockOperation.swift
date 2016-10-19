//
//  AsyncBlockOperation.swift
//  AsyncOperations
//
//  Created by Jared Sinclair on 10/18/16.
//  Copyright © 2016 Nice Boy LLC. All rights reserved.
//

import Foundation

@objc(JTSAsyncBlockOperation)
public class AsyncBlockOperation: AsyncOperation {
    
    public typealias Finish = () -> Void
    public typealias Execution = (@escaping Finish) -> Void
    
    private let execution: Execution
    
    public init(execution: @escaping Execution) {
        self.execution = execution
    }
    
    public override func execute(finish: @escaping () -> Void) {
        execution(finish)
    }
    
}
