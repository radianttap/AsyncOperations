//
//  ImageCache.swift
//  Project
//
//  Created by Jared Sinclair on 10/18/16.
//  Copyright © 2016 Nice Boy LLC. All rights reserved.
//

import UIKit
import AsyncOperations

/// A simple example of an image cache built around AsyncTaskQueue. It coalesces
/// multiple requests for the same image to a single task, ensuring that work is
/// only performed once per image url. The same image result will be distributed
/// to all concurrent requests.
class ImageCache {
    
    // MARK: Typealiases
    
    typealias ImageTaskQueue = AsyncTaskQueue<URL, UIImage?>
    typealias RequestToken = ImageTaskQueue.RequestToken
    
    // MARK: Enums
    
    enum CallbackMode {
        case sync
        case async(RequestToken)
    }
    
    // MARK: Private Properties
    
    private let directory: URL
    private let queue = ImageTaskQueue()
    private let memoryCache = MemoryCache<URL, UIImage>()
    
    // MARK: Init
    
    init(directory: URL) {
        self.directory = directory
    }
    
    // MARK: Public Methods
    
    func getImage(url: URL, preferredPriority: Operation.QueuePriority = .normal, completion: @escaping (UIImage?) -> Void) -> CallbackMode {
        
        assert(Thread.current.isMainThread)
        
        // Check if the image exists in the in-memory cache.
        
        if let image = memoryCache.value(for: url) {
            completion(image)
            return .sync
        }
        
        // It wasn't in the memory cache already, so spawn a new task and add
        // it to the task queue. Note that if there's an existing task for this
        // image url, the user's request will be appended to the active requests
        // for the existing task. AsyncTaskQueue handles that logic automatically.
        
        var asyncToken: ImageTaskQueue.RequestToken!
        let operationQueue = OperationQueue()
        let internals = ImageTaskInternals(url: url, directory: directory)
        
        // Again, please note that if there's already an existing task operation
        // for this image url, the `task` and `cancellation` block arguments
        // below will be quietly ignored. This is by design; that work should
        // only be performed once.
        
        queue.enqueue(
            task: { (finish) in
                let check = CheckForCachedFileOperation(internals: internals)
                let download = DownloadOperation(internals: internals)
                let crop = CropOperation(internals: internals)
                download.addDependency(check)
                crop.addDependency(download)
                let ops = [check, download, crop]
                operationQueue.addOperations(ops)
            },
            taskId: url,
            cancellation: {
                operationQueue.cancelAllOperations()
            },
            preferredPriority: preferredPriority,
            tokenHandler: { token in
                asyncToken = token
            },
            resultHandler: { [weak self] (image) in
                // The result handlers for all the requests will be invoked using
                // the same `image` result, even though the image was only
                // downloaded and cropped once.
                if let image = image {
                    self?.memoryCache.set(image, for: url)
                }
                completion(image)
            }
        )
        
        return .async(asyncToken)
    }
    
    func cancelRequest(with token: RequestToken) {
        queue.cancelRequest(with: token)
    }
    
    func adjustPriorityForRequest(with token: RequestToken, preferredPriority: Operation.QueuePriority) {
        queue.adjustPriorityForRequest(
            with: token,
            preferredPriority: preferredPriority
        )
    }
    
}








///-----------------------------------------------------------------------------
/// Stubbed Implementation Details
///-----------------------------------------------------------------------------

/// Stub wrapper around an NSCache-like creature.
private class MemoryCache<Key: Hashable, Value> {
    func value(for key: Key) -> Value? {
        // todo
        return nil
    }
    func set(_ value: Value?, for key: Key) {
        // todo
    }
}

/// Reference type for internal values shared among the various steps of the
/// image cache task procedure (checking local directory, downloading, cropping).
private class ImageTaskInternals {
    let url: URL
    let directory: URL
    var fileUrl: URL?
    var image: UIImage?
    
    init(url: URL, directory: URL) {
        self.url = url
        self.directory = directory
    }
}

/// Checks the local directory for an existing cached image file. If present,
/// it sets that file URL as the value of `internals.fileUrl` and finishes.
private class CheckForCachedFileOperation: AsyncOperation {
    let internals: ImageTaskInternals
    
    init(internals: ImageTaskInternals) {
        self.internals = internals
    }
}

/// Checks that `internals.fileUrl` is nil and, if so, downloads the original
/// image, moving the downloaded file to the local directory, setting the
/// value of `internals.fileUrl` to the resulting file url.
/// 
/// If `internals.fileUrl` is already non-nil, this operation bails out early
/// since there's no need to download anything.
private class DownloadOperation: AsyncOperation {
    let internals: ImageTaskInternals
    
    init(internals: ImageTaskInternals) {
        self.internals = internals
    }
}

/// Reads the image data from the file at `internals.fileUrl`, converts it to a
/// UIImage, decompresses and crops it, and saves the result to `internals.image`.
private class CropOperation: AsyncOperation {
    let internals: ImageTaskInternals
    
    init(internals: ImageTaskInternals) {
        self.internals = internals
    }
}

private extension OperationQueue {
    func addOperations(_ ops: [Operation]) {
        addOperations(ops, waitUntilFinished: false)
    }
}
