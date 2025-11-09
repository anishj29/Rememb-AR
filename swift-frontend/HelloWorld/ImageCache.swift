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
    
    func ensureMinimumCache(count threshold: Int = 2) {
        let cachedFiles = (try? fileManager.contentsOfDirectory(at: cacheFolder, includingPropertiesForKeys: nil)) ?? []
        if cachedFiles.count <= threshold {
            print("🌿 Only \(cachedFiles.count) cached images left — fetching 5 new ones.")
            preloadRandomImages(batchSize: 5)
        }
    }

    func preloadRandomImages(batchSize: Int = 5) {
        APIService.shared.fetchRandomMemories { items in
            let cachedFiles = (try? self.fileManager.contentsOfDirectory(at: self.cacheFolder, includingPropertiesForKeys: nil)) ?? []
            let cachedIDs = cachedFiles.map { $0.deletingPathExtension().lastPathComponent }

            // Filter out already-cached images
            let newItems = items.filter { !cachedIDs.contains($0.id) }
            let toCache = Array(newItems.prefix(batchSize))

            for item in toCache {
                guard let url = URL(string: item.url) else { continue }
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    if let data = data, let image = UIImage(data: data) {
                        self.saveImage(image, for: item.id)
                        print("✅ Cached image for:", item.caption)
                    }
                }.resume()
            }
        }
    }
    
    func cachedCount() -> Int {
        let files = (try? fileManager.contentsOfDirectory(at: cacheFolder, includingPropertiesForKeys: nil)) ?? []
        return files.count
    }
    
}
