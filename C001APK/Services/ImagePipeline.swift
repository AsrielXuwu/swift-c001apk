import CoolapkKit
import CryptoKit
import Foundation
import ImageIO
import UIKit

public struct LoadedImageResult: @unchecked Sendable {
    public let image: UIImage
    public let hasHDRGainMap: Bool
    public let pixelSize: CGSize
}

public actor ImagePipeline {
    public static let shared = ImagePipeline()

    private let memoryCache: NSCache<NSString, UIImage>
    private let hdrFlagCache = NSCache<NSString, NSNumber>()
    private let session: URLSession
    private let diskDirectory: URL
    private let maxDiskBytes: Int = 500 * 1024 * 1024
    private var inFlightTasks: [String: Task<LoadedImageResult?, Never>] = [:]
    private var userAgent: String = CoolapkToken.defaultUserAgent(
        deviceBrand: CoolapkToken.defaultDeviceBrand,
        deviceModel: CoolapkToken.defaultDeviceModel,
        appVersion: CoolapkToken.defaultAppVersion,
        appCode: CoolapkToken.defaultAppCode
    )

    private init() {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 450
        cache.totalCostLimit = 120 * 1024 * 1024
        self.memoryCache = cache

        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 8
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.diskDirectory = caches.appendingPathComponent("CoolapkImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    public func updateUserAgent(_ value: String) {
        if !value.isEmpty {
            userAgent = value
        }
    }

    public func purgeMemory() {
        memoryCache.removeAllObjects()
        hdrFlagCache.removeAllObjects()
    }

    public func loadImage(urlString: String, maxPixelSize: CGFloat? = nil) async -> LoadedImageResult? {
        guard let normalized = normalizedURL(urlString) else { return nil }
        let cacheKey = makeKey(url: normalized.absoluteString, maxPixelSize: maxPixelSize) as NSString

        if let cached = memoryCache.object(forKey: cacheKey) {
            let isHDR = hdrFlagCache.object(forKey: normalized.absoluteString as NSString)?.boolValue ?? false
            return LoadedImageResult(image: cached, hasHDRGainMap: isHDR, pixelSize: cached.size)
        }

        let keyStr = cacheKey as String
        if let existing = inFlightTasks[keyStr] {
            return await existing.value
        }

        let task = Task<LoadedImageResult?, Never> {
            await fetchAndDecode(url: normalized, cacheKey: keyStr, maxPixelSize: maxPixelSize)
        }
        inFlightTasks[keyStr] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: keyStr)
        return result
    }

    public func fetchRawData(urlString: String, maxBytes: Int = 32 * 1024 * 1024) async -> Data? {
        guard let url = normalizedURL(urlString) else { return nil }
        let diskFile = diskFileURL(for: url.absoluteString)
        if let existing = try? Data(contentsOf: diskFile), !existing.isEmpty, existing.count <= maxBytes {
            return existing
        }
        do {
            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  !data.isEmpty,
                  data.count <= maxBytes else {
                return nil
            }
            try? data.write(to: diskFile, options: .atomic)
            return data
        } catch {
            return nil
        }
    }

    public func downloadToTemporaryFile(urlString: String, defaultExtension: String) async -> URL? {
        guard let data = await fetchRawData(urlString: urlString, maxBytes: 64 * 1024 * 1024) else { return nil }
        let ext = URL(string: urlString)?.pathExtension.nonEmpty ?? defaultExtension
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        do {
            try data.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            return nil
        }
    }

    public func diskCacheByteCount() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: diskDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    public func clearAllCaches() {
        memoryCache.removeAllObjects()
        hdrFlagCache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskDirectory)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Decoding

    private func fetchAndDecode(url: URL, cacheKey: String, maxPixelSize: CGFloat?) async -> LoadedImageResult? {
        guard let data = await fetchRawData(urlString: url.absoluteString) else { return nil }
        return decode(data: data, urlString: url.absoluteString, cacheKey: cacheKey, maxPixelSize: maxPixelSize)
    }

    private func decode(data: Data, urlString: String, cacheKey: String, maxPixelSize: CGFloat?) -> LoadedImageResult? {
        let cfData = data as CFData
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(cfData, sourceOptions as CFDictionary) else {
            return nil
        }

        let hasGainMap = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            source,
            0,
            kCGImageAuxiliaryDataTypeHDRGainMap
        ) != nil
        hdrFlagCache.setObject(NSNumber(value: hasGainMap), forKey: urlString as NSString)

        let cgImage: CGImage?
        if let maxPixelSize, maxPixelSize > 0 {
            let thumbOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
        } else {
            let fullOptions: [CFString: Any] = [
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceShouldAllowFloat: true
            ]
            cgImage = CGImageSourceCreateImageAtIndex(source, 0, fullOptions as CFDictionary)
        }

        let uiImage: UIImage?
        if let cgImage {
            uiImage = UIImage(cgImage: cgImage)
        } else {
            uiImage = UIImage(data: data)
        }
        guard let finalImage = uiImage else { return nil }

        let cost = Int(finalImage.size.width * finalImage.size.height * finalImage.scale * finalImage.scale * 4)
        memoryCache.setObject(finalImage, forKey: cacheKey as NSString, cost: max(1024, cost))
        return LoadedImageResult(image: finalImage, hasHDRGainMap: hasGainMap, pixelSize: finalImage.size)
    }

    private func normalizedURL(_ raw: String) -> URL? {
        var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return nil }
        if str.hasPrefix("http://") { str = "https://" + str.dropFirst("http://".count) }
        if str.hasPrefix("//") { str = "https:" + str }
        return URL(string: str)
    }

    private func makeKey(url: String, maxPixelSize: CGFloat?) -> String {
        if let maxPixelSize {
            return "\(url)#w=\(Int(maxPixelSize))"
        }
        return url
    }

    private func diskFileURL(for urlString: String) -> URL {
        let digest = SHA256.hash(data: Data(urlString.utf8)).map { String(format: "%02x", $0) }.joined()
        return diskDirectory.appendingPathComponent(digest)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
