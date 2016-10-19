//
//  AsyncTaskOperationTests.swift
//  AsyncOperationsTests
//
//  Created by Jared Sinclair on 10/19/16.
//  Copyright © 2016 Nice Boy LLC. All rights reserved.
//

import XCTest
@testable import AsyncOperations

class AsyncTaskOperationTests: XCTestCase {
    
    // MARK: Task Execution
    
    func test_itExecutesASimpleTask() {
        
        let exp = expectation(description: #function)
        
        let task = AsyncTaskOperation<[String]>(
            task: { finish in
                let accumulator = TestAccumulator()
                accumulator.strings.append("One")
                finish(accumulator.strings)
            },
            cancellation: {
                // no op
            },
            preferredPriority: .normal,
            tokenHandler: { token in
                // no op
            },
            resultHandler: { result in
                XCTAssertEqual(result, ["One"])
                exp.fulfill()
            }
        )
        
        task.start()
        waitForExpectations(timeout: 5)
    }
    
    func test_itExecutesAMultiStepTask() {
        
        let exp = expectation(description: #function)
        let utilityQueue = OperationQueue()
        
        let task = AsyncTaskOperation<[String]>(
            task: { finish in
                let accumulator = TestAccumulator()
                let one = BlockOperation {
                    accumulator.strings.append("One")
                }
                let two = BlockOperation {
                    accumulator.strings.append("Two")
                }
                let three = BlockOperation {
                    accumulator.strings.append("Three")
                }
                let finish = BlockOperation {
                    finish(accumulator.strings)
                }
                two.addDependency(one)
                three.addDependency(two)
                finish.addDependency(three)
                utilityQueue.addOperations([one, two, three, finish], waitUntilFinished: false)
            },
            cancellation: {
                utilityQueue.cancelAllOperations()
            },
            preferredPriority: .normal,
            tokenHandler: { token in
                // no op
            },
            resultHandler: { result in
                XCTAssertEqual(result, ["One", "Two", "Three"])
                exp.fulfill()
            }
        )
        
        task.start()
        waitForExpectations(timeout: 5)
    }
    
    // MARK: Result Handlers
    
    func test_itInvokesAllResultHandlers() {
        
        let exp = expectation(description: #function)
        
        let task = AsyncTaskOperation<[String]>(
            task: { finish in
                let accumulator = TestAccumulator()
                accumulator.strings.append("One")
                finish(accumulator.strings)
            },
            cancellation: {
                // no op
            }
        )
        
        var resultCount = 0
        
        for _ in 0...10 {
            task.addRequest(
                preferredPriority: .normal,
                tokenHandler: { token in
                    // no op
                },
                resultHandler: { result in
                    XCTAssertEqual(result, ["One"])
                    resultCount += 1
                    if resultCount == 10 {
                        exp.fulfill()
                    }
                }
            )
        }
        
        task.start()
        waitForExpectations(timeout: 5)
        
    }
    
    // MARK: Cancellation
    
    func test_itCancelsAfterRemovingAllRequests() {
        
        let exp = expectation(description: #function)
        
        // Create a task that takes several seconds to finish.
        
        let task = AsyncTaskOperation<[String]>(
            task: { finish in
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    let accumulator = TestAccumulator()
                    accumulator.strings.append("One")
                    finish(accumulator.strings)
                }
            },
            cancellation: {
                // The cancellation handler should be invoked after the
                // last remaining request is removed.
                exp.fulfill()
            }
        )
        
        // Add 10 requests, collecting their tokens.
        
        typealias TokenType = AsyncTaskOperation<[String]>.RequestToken
        var tokens = [TokenType]()
        for _ in 0...10 {
            task.addRequest(
                preferredPriority: .normal,
                tokenHandler: { token in
                    if let token = token {
                        tokens.append(token)
                    }
                },
                resultHandler: { result in
                    XCTFail()
                }
            )
        }
        XCTAssert(tokens.count > 0)
        
        // Start the task. Remember it takes 5 seconds to finish.
        
        task.start()
        
        // Immediately cancel all requests.
        
        tokens.forEach {
            task.cancelRequest(with: $0)
        }
        
        // Wait 10 seconds to be sure there's plenty of time to test for the
        // cancellation.
        
        waitForExpectations(timeout: 10)
        
    }
    
    // MARK: Request Tokens
    
    func test_itReturnsATokenFromTheAdvancedInitializer() {
        
        let task = AsyncTaskOperation<[String]>(
            task: { finish in
                let accumulator = TestAccumulator()
                accumulator.strings.append("One")
                finish(accumulator.strings)
            },
            cancellation: {
                // no op
            },
            preferredPriority: .normal,
            tokenHandler: { token in
                XCTAssertNotNil(token)
            },
            resultHandler: { result in
                // no op
            }
        )
        
        task.start()
    }
    
    func test_itReturnsATokenWhenAddingTheFirstRequest() {
        
        let task = AsyncTaskOperation<[String]>(
            task: { finish in
                let accumulator = TestAccumulator()
                accumulator.strings.append("One")
                finish(accumulator.strings)
            },
            cancellation: {
                // no op
            }
        )
        
        task.addRequest(
            preferredPriority: .normal,
            tokenHandler: { (token) in
                XCTAssertNotNil(token)
            },
            resultHandler: { (result) in
                // no op
            }
        )
        
        task.start()
    }
    
    func test_itReturnsTokensWhenAddingAdditionalRequests() {
        
        let task = AsyncTaskOperation<[String]>(
            task: { finish in
                let accumulator = TestAccumulator()
                accumulator.strings.append("One")
                finish(accumulator.strings)
            },
            cancellation: {
                // no op
            }
        )
        
        for _ in 0...10 {
            task.addRequest(
                preferredPriority: .normal,
                tokenHandler: { (token) in
                    XCTAssertNotNil(token)
                },
                resultHandler: { (result) in
                    // no op
                }
            )
        }
        
        task.start()
    }
    
    func test_itReturnsNoTokenWhenTheTaskIsCancelled() {
        
        let task = AsyncTaskOperation<[String]>(
            task: { finish in
                let accumulator = TestAccumulator()
                accumulator.strings.append("One")
                finish(accumulator.strings)
            },
            cancellation: {
                // no op
            }
        )
        
        task.cancel()
        
        task.addRequest(
            preferredPriority: .normal,
            tokenHandler: { (token) in
                XCTAssertNil(token)
            },
            resultHandler: { (result) in
                XCTFail("The result handler should not be invoked.")
            }
        )
    }
    
    func test_itReturnsNoTokenWhenTheTaskIsFinished() {
        
        let exp = expectation(description: #function)

        let task = AsyncTaskOperation<[String]>(
            task: { finish in
                let accumulator = TestAccumulator()
                accumulator.strings.append("One")
                finish(accumulator.strings)
            },
            cancellation: {
                // no op
            }
        )
        
        task.addRequest(
            preferredPriority: .normal,
            tokenHandler: { (token) in
                XCTAssertNotNil(token)
            },
            resultHandler: { (result) in
                task.addRequest(
                    preferredPriority: .normal,
                    tokenHandler: { (token) in
                        XCTAssertNil(token)
                        exp.fulfill()
                    },
                    resultHandler: { (result) in
                        XCTFail("The result handler should not be invoked.")
                    }
                )
            }
        )
        
        task.start()
        waitForExpectations(timeout: 5)
    }
    
    func test_itReturnsATokenSynchronously_simpleInit() {
        
        var token: AsyncTaskOperation<[String]>.RequestToken? = nil
        
        let task = AsyncTaskOperation<[String]>(
            task: { finish in
                let accumulator = TestAccumulator()
                accumulator.strings.append("One")
                finish(accumulator.strings)
            },
            cancellation: {
                // no op
            }
        )
        
        task.addRequest(
            preferredPriority: .normal,
            tokenHandler: { t in
                token = t
            },
            resultHandler: { (result) in
                // no op
            }
        )
        
        XCTAssertNotNil(token)
    }
    
    func test_itReturnsATokenSynchronously_advancedInit() {
        
        var token: AsyncTaskOperation<[String]>.RequestToken? = nil
        
        _ = AsyncTaskOperation<[String]>(
            task: { finish in
                let accumulator = TestAccumulator()
                accumulator.strings.append("One")
                finish(accumulator.strings)
            },
            cancellation: {
                // no op
            },
            preferredPriority: .normal,
            tokenHandler: { t in
                token = t
            },
            resultHandler: { result in
                // no op
            }
        )
        
        XCTAssertNotNil(token)
    }
    
}

private class TestAccumulator {
    var strings = [String]()
}
