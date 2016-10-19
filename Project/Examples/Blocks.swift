//
//  Blocks.swift
//  Examples
//
//  Created by Jared Sinclair on 10/18/16.
//  Copyright © 2016 Nice Boy LLC. All rights reserved.
//

import Foundation
import AsyncOperations

/// A contrived example illustrating the use of AsyncBlockOperation.
///
/// Prints the following to the console:
/// 
///     One.
///     Two.
///     Three.
///
func doSomethingSlow(queue: OperationQueue, completion: @escaping () -> Void) {
    
    // `AsyncBlockOperation` allows you to run arbitrary blocks of code
    // asynchronously. The only obligation is that the block must invoke the
    // `finish` block argument when finished, or else the AsyncBlockOperation
    // will remain stuck in the isExecuting state indefinitely.
    
    // For example, even though the execution blocks for the `one`, `two`, and
    // `three` operations below exit scope before each of their `.asyncAfter()` 
    // calls fire, each operation will remain in its executing state until the 
    // `finish` handlers are invoked. This allows you to make each operation
    // depend upon the previous via `.addDependency()`.
    
    let one = AsyncBlockOperation { (finish) in
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            print("One.")
            finish()
        }
    }
    
    let two = AsyncBlockOperation { (finish) in
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            print("Two.")
            finish()
        }
    }
    
    let three = AsyncBlockOperation { (finish) in
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            print("Three.")
            finish()
        }
    }
    
    // In contrast, (NS)BlockOperation is marked finished as soon as the outer-
    // most scope of the execution block exits.
    
    let completionOp = BlockOperation {
        completion()
    }
    
    two.addDependency(one)
    three.addDependency(two)
    completionOp.addDependency(three)
    
    let ops = [one, two, three, completionOp]
    
    queue.addOperations(ops, waitUntilFinished: false)
    
}
