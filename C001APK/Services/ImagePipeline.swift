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

private final class SyncImageMemoryStore: @unchecked Sendable {
    let images: NSCache<NSString, UIImage>
    let hdrFlags = NSCache<NSString, NSNumber>()
    let liveFlags = NSCache<NSString, NSNumber>()

    init() {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 450
        cache.totalCostLimit = 120 * 1024 * 1024
        self.images = cache
    }
}

public actor ImagePipeline {
    public static let shared = ImagePipeline()
    private static let memoryStore = SyncImageMemoryStore()

    private var memoryCache: NSCache<NSString, UIImage> { Self.memoryStore.images }
    private var hdrFlagCache: NSCache<NSString, NSNumber> { Self.memoryStore.hdrFlags }
    private var liveFlagCache: NSCache<NSString, NSNumber> { Self.memoryStore.liveFlags }
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

    public nonisolated static func cachedImageSync(
        urlString: String,
        maxPixelSize: CGFloat? = nil,
        preferHDR: Bool = false
    ) -> LoadedImageResult? {
        guard let normalized = normalizedURLStatic(urlString) else { return nil }
        let cacheKey = makeKeyStatic(url: normalized.absoluteString, maxPixelSize: maxPixelSize, preferHDR: preferHDR) as NSString
        guard let cached = memoryStore.images.object(forKey: cacheKey) else { return nil }
        let isHDR = memoryStore.hdrFlags.object(forKey: normalized.absoluteString as NSString)?.boolValue ?? cached.isHighDynamicRange
        return LoadedImageResult(image: cached, hasHDRGainMap: isHDR, pixelSize: cached.size)
    }

    public nonisolated static func cachedHDRFlagSync(urlString: String) -> Bool {
        guard let normalized = normalizedURLStatic(urlString) else { return false }
        return memoryStore.hdrFlags.object(forKey: normalized.absoluteString as NSString)?.boolValue ?? false
    }

    public nonisolated static func cachedLiveFlagSync(urlString: String) -> Bool {
        guard let normalized = normalizedURLStatic(urlString) else { return false }
        return memoryStore.liveFlags.object(forKey: normalized.absoluteString as NSString)?.boolValue ?? false
    }

    public func updateUserAgent(_ value: String) {
        if !value.isEmpty {
            userAgent = value
        }
    }

    public func purgeMemory() {
        memoryCache.removeAllObjects()
        hdrFlagCache.removeAllObjects()
        liveFlagCache.removeAllObjects()
    }

    public func loadImage(
        urlString: String,
        maxPixelSize: CGFloat? = nil,
        preferHDR: Bool = false
    ) async -> LoadedImageResult? {
        guard let normalized = normalizedURL(urlString) else { return nil }
        let cacheKey = makeKey(url: normalized.absoluteString, maxPixelSize: maxPixelSize, preferHDR: preferHDR) as NSString

        if let cached = memoryCache.object(forKey: cacheKey) {
            let isHDR = hdrFlagCache.object(forKey: normalized.absoluteString as NSString)?.boolValue ?? cached.isHighDynamicRange
            return LoadedImageResult(image: cached, hasHDRGainMap: isHDR, pixelSize: cached.size)
        }

        let keyStr = cacheKey as String
        if let existing = inFlightTasks[keyStr] {
            return await existing.value
        }

        let task = Task<LoadedImageResult?, Never> {
            await fetchAndDecode(url: normalized, cacheKey: keyStr, maxPixelSize: maxPixelSize, preferHDR: preferHDR)
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
        liveFlagCache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskDirectory)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    /// Extracts an embedded MotionPhoto MP4 video from JPEG XMP/tail data when present.
    public func extractEmbeddedMotionVideo(fromImageURL imageURL: String) async -> URL? {
        guard let data = await fetchRawData(urlString: imageURL, maxBytes: 64 * 1024 * 1024),
              data.count > 64 else {
            return nil
        }
        let headerSlice = data.prefix(min(data.count, 512 * 1024))
        let xmpText = String(data: Data(headerSlice), encoding: .isoLatin1)
            ?? String(decoding: headerSlice, as: UTF8.self)
        let declaresMotion = Self.xmpDeclaresMotionPhoto(xmpText)
        guard declaresMotion else { return nil }

        let declaredLen = Self.extractMotionVideoLength(from: xmpText)
        let ftypMarker = Data([0x66, 0x74, 0x79, 0x70]) // "ftyp"
        var videoData: Data?
        if let len = declaredLen, len > 16, len < data.count {
            let start = data.count - len
            if data.count - start >= 8, data.subdata(in: (start + 4)..<(start + 8)) == ftypMarker {
                videoData = data.subdata(in: start..<data.count)
            }
        }
        if videoData == nil {
            let scanStart = max(0, data.count - min(data.count, 32 * 1024 * 1024))
            if let range = data.range(of: ftypMarker, options: [.backwards], in: scanStart..<data.count),
               range.lowerBound >= 4 {
                let mp4Start = range.lowerBound - 4
                videoData = data.subdata(in: mp4Start..<data.count)
            }
        }
        guard let extracted = videoData, !extracted.isEmpty else { return nil }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        do {
            try extracted.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            return nil
        }
    }

    // MARK: - Decoding

    private func fetchAndDecode(url: URL, cacheKey: String, maxPixelSize: CGFloat?, preferHDR: Bool) async -> LoadedImageResult? {
        guard let data = await fetchRawData(urlString: url.absoluteString) else { return nil }
        return decode(data: data, urlString: url.absoluteString, cacheKey: cacheKey, maxPixelSize: maxPixelSize, preferHDR: preferHDR)
    }

    private func decode(data: Data, urlString: String, cacheKey: String, maxPixelSize: CGFloat?, preferHDR: Bool) -> LoadedImageResult? {
        let cfData = data as CFData
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(cfData, sourceOptions as CFDictionary) else {
            return nil
        }

        let prefixBytes = data.prefix(min(data.count, 256 * 1024))
        let xmpPrefix = String(data: Data(prefixBytes), encoding: .isoLatin1)
            ?? String(decoding: prefixBytes, as: UTF8.self)
        let hasGainMap = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            source,
            0,
            kCGImageAuxiliaryDataTypeHDRGainMap
        ) != nil || xmpPrefix.range(of: "hdrgm:Version", options: .caseInsensitive) != nil
        let isMotion = Self.xmpDeclaresMotionPhoto(xmpPrefix)
        liveFlagCache.setObject(NSNumber(value: isMotion), forKey: urlString as NSString)

        var uiImage: UIImage?
        var resolvedHDR = hasGainMap

        if preferHDR {
            var config = UIImageReader.Configuration()
            config.prefersHighDynamicRange = true
            if let maxPixelSize, maxPixelSize > 0 {
                config.preferredThumbnailSize = CGSize(width: maxPixelSize, height: maxPixelSize)
            }
            let reader = UIImageReader(configuration: config)
            if let decoded = reader.image(data: data) {
                uiImage = decoded
                if decoded.isHighDynamicRange {
                    resolvedHDR = true
                }
            }
        }

        hdrFlagCache.setObject(NSNumber(value: resolvedHDR), forKey: urlString as NSString)

        if uiImage == nil {
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

            if let cgImage {
                uiImage = UIImage(cgImage: cgImage)
            } else {
                uiImage = UIImage(data: data)
            }
        }

        guard let finalImage = uiImage else { return nil }
        if finalImage.isHighDynamicRange {
            resolvedHDR = true
            hdrFlagCache.setObject(NSNumber(value: true), forKey: urlString as NSString)
        }

        let cost = Int(finalImage.size.width * finalImage.size.height * finalImage.scale * finalImage.scale * 4)
        memoryCache.setObject(finalImage, forKey: cacheKey as NSString, cost: max(1024, cost))
        return LoadedImageResult(image: finalImage, hasHDRGainMap: resolvedHDR, pixelSize: finalImage.size)
    }

    private nonisolated static func xmpDeclaresMotionPhoto(_ xmp: String) -> Bool {
        xmp.contains("GCamera:MotionPhoto=\"1\"")
            || xmp.contains("GCamera:MicroVideo=\"1\"")
            || xmp.contains("OpCamera:OLivePhotoVersion=\"")
    }

    private nonisolated static func extractMotionVideoLength(from xmp: String) -> Int? {
        let patterns = [
            #"Item:Mime="video/mp4"[^>]*Item:Length="(\d+)""#,
            #"Item:Length="(\d+)"[^>]*Item:Mime="video/mp4""#,
            #"GCamera:MicroVideoOffset="(\d+)""#,
            #"OpCamera:VideoLength="(\d+)""#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: xmp, range: NSRange(xmp.startIndex..<xmp.endIndex, in: xmp)),
               let range = Range(match.range(at: 1), in: xmp),
               let val = Int(xmp[range]) {
                return val
            }
        }
        return nil
    }

    private nonisolated static func normalizedURLStatic(_ raw: String) -> URL? {
        var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return nil }
        if str.hasPrefix("http://") { str = "https://" + str.dropFirst("http://".count) }
        if str.hasPrefix("//") { str = "https:" + str }
        return URL(string: str)
    }

    private nonisolated static func makeKeyStatic(url: String, maxPixelSize: CGFloat?, preferHDR: Bool = false) -> String {
        var key = url
        if let maxPixelSize {
            key += "#w=\(Int(maxPixelSize))"
        }
        if preferHDR {
            key += "#hdr"
        }
        return key
    }

    private func normalizedURL(_ raw: String) -> URL? {
        Self.normalizedURLStatic(raw)
    }

    private func makeKey(url: String, maxPixelSize: CGFloat?, preferHDR: Bool = false) -> String {
        Self.makeKeyStatic(url: url, maxPixelSize: maxPixelSize, preferHDR: preferHDR)
    }

    private func diskFileURL(for urlString: String) -> URL {
        let digest = SHA256.hash(data: Data(urlString.utf8)).map { String(format: "%02x", $0) }.joined()
        return diskDirectory.appendingPathComponent(digest)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
