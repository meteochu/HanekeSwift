//
//  DiskCache.swift
//  Haneke
//
//  Created by Hermes Pique on 8/10/14.
//  Copyright (c) 2014 Haneke. All rights reserved.
//

import Foundation

public class DiskCache {
    
    public class func basePath() -> String {
        let cachesPath = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.CachesDirectory, NSSearchPathDomainMask.UserDomainMask, true)[0] as String
        let hanekePathComponent = HanekeGlobals.Domain
        let basePath = cachesPath.stringByAppendingPathComponent(hanekePathComponent)
        // TODO: Do not recaculate basePath value
        return basePath
    }
    
    public let path : String

    public var size : UInt64 = 0

    public var capacity : UInt64 = 0 {
        didSet {
            dispatch_async(self.cacheQueue, {
                self.controlCapacity()
            })
        }
    }

    public lazy var cacheQueue : dispatch_queue_t = {
        let queueName = HanekeGlobals.Domain + "." + self.path.lastPathComponent
        let cacheQueue = dispatch_queue_create(queueName, nil)
        return cacheQueue
    }()
    
    public init(path : String, capacity : UInt64 = UINT64_MAX) {
        self.path = path
        self.capacity = capacity
        dispatch_async(self.cacheQueue, {
            self.calculateSize()
            self.controlCapacity()
        })
    }
    
    public func setData(@autoclosure(escaping) getData : () -> NSData?, key : String) {
        dispatch_async(cacheQueue, {
            self.setDataSync(getData(), key: key)
        })
    }
    
    public func fetchData(key : String, failure fail : ((NSError?) -> ())? = nil, success succeed : (NSData) -> ()) {
        dispatch_async(cacheQueue, {
            let path = self.pathForKey(key)
            var error: NSError? = nil
            do {
                let data = try NSData(contentsOfFile: path, options: NSDataReadingOptions())
                dispatch_async(dispatch_get_main_queue(), {
                   succeed(data)
                })
                self.updateDiskAccessDateAtPath(path)
            } catch let error1 as NSError {
                error = error1
                if let block = fail {
                    dispatch_async(dispatch_get_main_queue(), {
                        block(error)
                    })
                }
            } catch {
                fatalError()
            }
        })
    }

    public func removeData(key : String) {
        dispatch_async(cacheQueue, {
            let fileManager = NSFileManager.defaultManager()
            let path = self.pathForKey(key)
            let attributesOpt : NSDictionary?
            do {
                attributesOpt = try fileManager.attributesOfItemAtPath(path)
            } catch _ {
                attributesOpt = nil
            }
            var error : NSError?
            let success: Bool
            do {
                try fileManager.removeItemAtPath(path)
                success = true
            } catch let error1 as NSError {
                error = error1
                success = false
            } catch {
                fatalError()
            }
            if (success) {
                if let attributes = attributesOpt {
                    self.size -= attributes.fileSize()
                }
            } else {
                print("Failed to remove key \(key) with error \(error!)")
            }
        })
    }
    
    public func removeAllData() {
        let fileManager = NSFileManager.defaultManager()
        let cachePath = self.path
        dispatch_async(cacheQueue, {
            do
            {
                if let contents = try fileManager.contentsOfDirectoryAtPath(cachePath) as? [String] {
                    for pathComponent in contents {
                        let path = cachePath.stringByAppendingPathComponent(pathComponent)
                        do {
                            try fileManager.removeItemAtPath(path)
                        } catch let error1 as NSError {
                            Log.error("Failed to remove path \(path)", error1)
                        } catch {
                            fatalError()
                        }
                    }
                    self.calculateSize()
                }
            }
            catch let error2 as NSError {
                Log.error("Failed to list directory", error2)
            }
            catch {
                
            }
        })
    }

    public func updateAccessDate(@autoclosure(escaping) getData : () -> NSData?, key : String) {
        dispatch_async(cacheQueue, {
            let path = self.pathForKey(key)
            let fileManager = NSFileManager.defaultManager()
            if (!self.updateDiskAccessDateAtPath(path) && !fileManager.fileExistsAtPath(path)){
                let data = getData()
                self.setDataSync(data, key: key)
            }
        })
    }

    public func pathForKey(key : String) -> String {
        let escapedFilename = key.escapedFilename()
        let filename = escapedFilename.characters.count < Int(NAME_MAX) ? escapedFilename : key.MD5Filename()
        let keyPath = self.path.stringByAppendingPathComponent(filename)
        return keyPath
    }
    
    // MARK: Private
    
    private func calculateSize() {
        let fileManager = NSFileManager.defaultManager()
        size = 0
        let cachePath = self.path
        do {
            if let contents = try fileManager.contentsOfDirectoryAtPath(cachePath) as? [String] {
                for pathComponent in contents {
                    let path = cachePath.stringByAppendingPathComponent(pathComponent)
                    do {
                        let attributes : NSDictionary = try fileManager.attributesOfItemAtPath(path)
                        size += attributes.fileSize()
                    } catch let error1 as NSError {
                        Log.error("Failed to read file size of \(path)", error1)
                    }
                }
            }
        }
        catch let error2 as NSError {
            Log.error("Failed to list directory", error2)
        }
        catch {
            
        }
    }
    
    private func controlCapacity() {
        if self.size <= self.capacity { return }
        
        let fileManager = NSFileManager.defaultManager()
        let cachePath = self.path
        fileManager.enumerateContentsOfDirectoryAtPath(cachePath, orderedByProperty: NSURLContentModificationDateKey, ascending: true) { (URL : NSURL, _, inout stop : Bool) -> Void in
            
            if let path = URL.path {
                self.removeFileAtPath(path)

                stop = self.size <= self.capacity
            }
        }
    }
    
    private func setDataSync(data: NSData?, key : String) {
        let path = self.pathForKey(key)
        var error: NSError?
        if let data = data {
            let fileManager = NSFileManager.defaultManager()
            let previousAttributes : NSDictionary?
            do {
                previousAttributes = try fileManager.attributesOfItemAtPath(path)
            } catch _ {
                previousAttributes = nil
            }
            let success: Bool
            do {
                try data.writeToFile(path, options: NSDataWritingOptions.AtomicWrite)
                success = true
            } catch let error1 as NSError {
                error = error1
                success = false
            }
            if (!success) {
                Log.error("Failed to write key \(key)", error)
            }
            if let attributes = previousAttributes {
                self.size -= attributes.fileSize()
            }
            self.size += UInt64(data.length)
            self.controlCapacity()
        } else {
            Log.error("Failed to get data for key \(key)")
        }
    }
    
    private func updateDiskAccessDateAtPath(path : String) -> Bool {
        let fileManager = NSFileManager.defaultManager()
        let now = NSDate()
        var error : NSError?
        let success: Bool
        do {
            try fileManager.setAttributes([NSFileModificationDate : now], ofItemAtPath: path)
            success = true
        } catch let error1 as NSError {
            error = error1
            success = false
        }
        if !success {
            Log.error("Failed to update access date", error)
        }
        return success
    }
    
    private func removeFileAtPath(path:String) {
        let fileManager = NSFileManager.defaultManager()
        do {
            let attributes : NSDictionary = try fileManager.attributesOfItemAtPath(path)
            let modificationDate = attributes.fileModificationDate()
            let fileSize = attributes.fileSize()
            do {
                try fileManager.removeItemAtPath(path)
                self.size -= fileSize
            }
        } catch let error as NSError {
            Log.error("Failed to remove file", error)
        }
    }
}
