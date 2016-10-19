//
//  AsyncBlockOperationTests.swift
//  AsyncOperationsTests
//
//  Created by Jared Sinclair on 10/19/16.
//  Copyright © 2016 Nice Boy LLC. All rights reserved.
//

import XCTest
@testable import AsyncOperations

class AsyncBlockOperationTests: XCTestCase {

    func test_itExecutesABlock() {
        let exp = expectation(description: #function)
        let op = AsyncBlockOperation { finish in
            exp.fulfill()
            finish()
        }
        op.start()
        waitForExpectations(timeout: 5)
    }
    
    func test_itExecutesACompletionBlock() {
        let exp = expectation(description: #function)
        let op = AsyncBlockOperation { finish in
            finish()
        }
        op.addCompletionHandler {
            exp.fulfill()
        }
        op.start()
        waitForExpectations(timeout: 5)
    }
    
    func test_itRemainsExecutingUntilFinished() {
        let exp = expectation(description: #function)
        var results: [String] = ["idle"]
        let asyncOp = AsyncBlockOperation { finish in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                results.append("async")
                finish()
            }
        }
        let syncOp = BlockOperation {
            results.append("sync")
            XCTAssertEqual(["idle", "async", "sync"], results)
            exp.fulfill()
        }
        syncOp.addDependency(asyncOp)
        let queue = OperationQueue()
        queue.addOperations([asyncOp, syncOp], waitUntilFinished: false)
        waitForExpectations(timeout: 5)
    }

}
