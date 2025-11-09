//
//  ImageCache.swift
//  HelloWorld
//
//  Created by Sankeerth Bharadwaj on 11/8/25.
//


import UIKit

class ImageCache {
    static let shared = ImageCache()
    private let fileManager = FileManager.default
    private let cacheFolder: URL

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheFolder = caches.appendingPathComponent("FlowerImageCache", isDirectory: true)

        // Create folder if it doesn't exist
        if !fileManager.fileExists(atPath: cacheFolder.path) {
            try? fileManager.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        }
    }

    func localURL(for id: String) -> URL {
        return cacheFolder.appendingPathComponent("\(id).jpg")
    }

    func image(for id: String) -> UIImage? {
        let url = localURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
    }

    func saveImage(_ image: UIImage, for id: String) {
        let url = localURL(for: id)
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: url)
        }
    }

    func isCached(_ id: String) -> Bool {
        return fileManager.fileExists(atPath: localURL(for: id).path)
    }
}