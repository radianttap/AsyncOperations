//
//  AsyncTaskQueueTests.swift
//  AsyncOperationsTests
//
//  Created by Jared Sinclair on 10/19/16.
//  Copyright © 2016 Nice Boy LLC. All rights reserved.
//

import XCTest
@testable import AsyncOperations

class AsyncTaskQueueTests: XCTestCase {

    func test_itExecutesATask() {
        let exp = expectation(description: #function)
        let queue = AsyncTaskQueue<String, [String]>()
        queue.enqueue(
            task: { (finish) in
                finish(["One"])
            },
            taskId: "abc",
            cancellation: {
                // no op
            },
            preferredPriority: .normal,
            tokenHandler: { (token) in
                // no op
            },
            resultHandler: { (results) in
                XCTAssertEqual(["One"], results)
                exp.fulfill()
            }
        )
        waitForExpectations(timeout: 5)
    }
    
    func test_itExecutesATaskOnlyOncePerTaskId() {
        
        let exp = expectation(description: #function)
        let queue = AsyncTaskQueue<String, [String]>()
        var taskAccumulator = [String]()
        var resultAccumulator = 0
        
        for _ in 0...9 {
            queue.enqueue(
                task: { (finish) in
                    taskAccumulator.append("One")
                    finish(taskAccumulator)
                },
                taskId: "abc",
                cancellation: {
                    // no op
                },
                preferredPriority: .normal,
                tokenHandler: { (token) in
                    // no op
                },
                resultHandler: { (results) in
                    XCTAssertEqual(["One"], results)
                    resultAccumulator += 1
                    if resultAccumulator == 10 {
                        exp.fulfill()
                    }
                }
            )
        }
        
        waitForExpectations(timeout: 5)
    }
    
}
