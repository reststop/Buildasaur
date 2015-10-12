//
//  Persistence.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 07/03/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils

public class PersistenceFactory {
    
    public class func createStandardPersistence() -> Persistence {
        
        //            let folderName = "Buildasaur"
        let folderName = "Buildasaur-Debug"
        
        let fileManager = NSFileManager.defaultManager()
        guard let applicationSupport = fileManager
            .URLsForDirectory(.ApplicationSupportDirectory, inDomains:.UserDomainMask)
            .first else {
                preconditionFailure("Couldn't access Builda's persistence folder, aborting")
        }
        let buildaRoot = applicationSupport
            .URLByAppendingPathComponent(folderName, isDirectory: true)
        
        let persistence = Persistence(readingFolder: buildaRoot, writingFolder: buildaRoot, fileManager: fileManager)
        return persistence
    }
}

public class Persistence {
    
    private let readingFolder: NSURL
    private let writingFolder: NSURL
    private let fileManager: NSFileManager
    
    public init(readingFolder: NSURL, writingFolder: NSURL, fileManager: NSFileManager) {
        
        self.readingFolder = readingFolder
        self.writingFolder = writingFolder
        self.fileManager = fileManager
        self.ensureFoldersExist()
    }
    
    private func ensureFoldersExist() {
        
        self.createFolderIfNotExists(self.readingFolder)
        self.createFolderIfNotExists(self.writingFolder)
    }
    
    func deleteFile(name: String) {
        let itemUrl = self.fileURLWithName(name, intention: .Writing, isDirectory: false)
        self.delete(itemUrl)
    }
    
    func deleteFolder(name: String) {
        let itemUrl = self.fileURLWithName(name, intention: .Writing, isDirectory: true)
        self.delete(itemUrl)
    }
    
    private func delete(url: NSURL) {
        do {
            try self.fileManager.removeItemAtURL(url)
        } catch {
            Log.error(error)
        }
    }
    
    func saveData(name: String, item: AnyObject) {
        
        let itemUrl = self.fileURLWithName(name, intention: .Writing, isDirectory: false)
        let json = item
        do {
            try self.saveJSONToUrl(json, url: itemUrl)
        } catch {
            assert(false, "Failed to save \(name), \(error)")
        }
    }
    
    func saveDictionary(name: String, item: NSDictionary) {
        self.saveData(name, item: item)
    }
    
    //crashes when I use [JSONWritable] instead of NSArray :(
    func saveArray(name: String, items: NSArray) {
        self.saveData(name, item: items)
    }
    
    func saveArrayIntoFolder<T: JSONWritable>(folderName: String, items: [T], itemFileName: (item: T) -> String) {
        
        let folderUrl = self.fileURLWithName(folderName, intention: .Writing, isDirectory: true)
        items.forEach { (item: T) -> () in
            
            let json = item.jsonify()
            let name = itemFileName(item: item)
            let url = folderUrl.URLByAppendingPathComponent("\(name).json")
            do {
                try self.saveJSONToUrl(json, url: url)
            } catch {
                assert(false, "Failed to save a \(folderName), \(error)")
            }
        }
    }
    
    func loadDictionaryFromFile<T>(name: String) -> T? {
        return self.loadDataFromFile(name, process: { (json) -> T? in
            
            guard let contents = json as? T else { return nil }
            return contents
        })
    }
    
    func loadArrayFromFile<T>(name: String, convert: (json: NSDictionary) throws -> T?) -> [T]? {
        
        return self.loadDataFromFile(name, process: { (json) -> [T]? in
            
            guard let json = json as? [NSDictionary] else { return nil }
            
            let allItems = json.map { (item) -> T? in
                do { return try convert(json: item) } catch { return nil }
            }
            let parsedItems = allItems.filter { $0 != nil }.map { $0! }
            if parsedItems.count != allItems.count {
                Log.error("Some \(name) failed to parse, will be ignored.")
                //maybe show a popup?
            }
            return parsedItems
        })
    }
    
    func loadArrayOfDictionariesFromFile(name: String) -> [NSDictionary]? {
        return self.loadArrayFromFile(name, convert: { $0 })
    }
    
    func loadArrayFromFile<T: JSONReadable>(name: String) -> [T]? {
        
        return self.loadArrayFromFile(name) { try T(json: $0) }
    }
    
    func loadArrayFromFolder<T: JSONReadable>(folderName: String) -> [T]? {
        let folderUrl = self.fileURLWithName(folderName, intention: .Reading, isDirectory: true)
        return self.filesInFolder(folderUrl)?.map { (url: NSURL) -> T? in
            
            do {
                let json = try self.loadJSONFromUrl(url)
                if let json = json as? NSDictionary {
                    let template = try T(json: json)
                    return template
                }
            } catch {
                Log.error("Couldn't parse \(folderName) at url \(url), error \(error)")
            }
            return nil
            }.filter { $0 != nil }.map { $0! }
    }
    
    func loadDataFromFile<T>(name: String, process: (json: AnyObject?) -> T?) -> T? {
        let url = self.fileURLWithName(name, intention: .Reading, isDirectory: false)
        do {
            let json = try self.loadJSONFromUrl(url)
            guard let contents = process(json: json) else { return nil }
            return contents
        } catch {
            //file not found
            if (error as NSError).code != 260 {
                Log.error("Failed to read \(name), error \(error). Will be ignored. Please don't play with the persistence :(")
            }
            return nil
        }
    }
    
    public func loadJSONFromUrl(url: NSURL) throws -> AnyObject? {
        
        let data = try NSData(contentsOfURL: url, options: NSDataReadingOptions())
        let json: AnyObject = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.AllowFragments)
        return json
    }
    
    public func saveJSONToUrl(json: AnyObject, url: NSURL) throws {
        
        let data = try NSJSONSerialization.dataWithJSONObject(json, options: NSJSONWritingOptions.PrettyPrinted)
        try data.writeToURL(url, options: NSDataWritingOptions.DataWritingAtomic)
    }
    
    public func fileURLWithName(name: String, intention: PersistenceIntention, isDirectory: Bool) -> NSURL {
        
        let root = self.folderForIntention(intention)
        let url = root.URLByAppendingPathComponent(name, isDirectory: isDirectory)
        if isDirectory && intention == .Writing {
            self.createFolderIfNotExists(url)
        }
        return url
    }
    
    public func copyFileToWriteLocation(name: String, isDirectory: Bool) {
        
        let url = self.fileURLWithName(name, intention: .Reading, isDirectory: isDirectory)
        let writeUrl = self.fileURLWithName(name, intention: .WritingNoCreateFolder, isDirectory: isDirectory)
        
        try! self.fileManager.copyItemAtURL(url, toURL: writeUrl)
    }
    
    public func createFolderIfNotExists(url: NSURL) {
        
        let fm = self.fileManager
        do {
            try fm.createDirectoryAtURL(url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            fatalError("Failed to create a folder in Builda's Application Support folder \(url), error \(error)")
        }
    }
    
    public enum PersistenceIntention {
        case Reading
        case Writing
        case WritingNoCreateFolder
    }
    
    private func folderForIntention(intention: PersistenceIntention) -> NSURL {
        switch intention {
        case .Reading:
            return self.readingFolder
        case .Writing, .WritingNoCreateFolder:
            return self.writingFolder
        }
    }
    
    public func filesInFolder(folderUrl: NSURL) -> [NSURL]? {
        
        do {
            let contents = try self.fileManager.contentsOfDirectoryAtURL(folderUrl, includingPropertiesForKeys: nil, options: [.SkipsHiddenFiles, .SkipsSubdirectoryDescendants])
            return contents
        } catch {
            Log.error("Couldn't read folder \(folderUrl), error \(error)")
            return nil
        }
    }
    
}
