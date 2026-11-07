import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An image attached to a user message. The file lives next to the session; the session records the path,
/// so its JSONL stays small, and the bytes are read only when a request is encoded.
public struct ImageAttachment: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// "image/png" or "image/jpeg".
    public var mediaType: String
    public var path: String
    public var width: Int
    public var height: Int

    public init(id: UUID = UUID(), mediaType: String, path: String, width: Int, height: Int) {
        self.id = id
        self.mediaType = mediaType
        self.path = path
        self.width = width
        self.height = height
    }

    /// A `data:` URL with the image, for OpenAI-style `image_url` parts; nil if the file is gone.
    public var dataURL: String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return "data:\(mediaType);base64,\(data.base64EncodedString())"
    }
}

public enum ImageStore {
    /// Longest edge after downscaling. Vision models resize further anyway; larger only costs tokens.
    public static let maxPixels = 1568
    /// Above this, a PNG is re-encoded as JPEG (photos, busy screenshots).
    static let maxPNGBytes = 1_500_000

    public struct Failure: Error, LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// Decodes an image in any format ImageIO reads, downscales it, and saves it in `directory`.
    /// Whether this is an image ImageIO can read (PDF isn't counted: it has its own handling).
    public static func isImage(_ data: Data) -> Bool {
        guard !data.starts(with: Array("%PDF".utf8)), let source = CGImageSourceCreateWithData(data.prefix(65_536) as CFData, nil) else { return false }
        return CGImageSourceGetType(source) != nil && CGImageSourceGetStatus(source) != .statusUnknownType && CGImageSourceGetCount(source) > 0
    }

    public static func save(_ data: Data, in directory: URL) throws -> ImageAttachment {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw Failure(message: "That isn't an image kurtkode can read.")
        }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0, h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,        // honor EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixels, max(w, h, 1)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure(message: "Couldn't decode the image.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        var encoded = try encode(image, as: .png)
        var type = UTType.png
        if encoded.count > maxPNGBytes {
            encoded = try encode(image, as: .jpeg, quality: 0.85)
            type = .jpeg
        }
        let url = directory.appending(path: "\(id.uuidString).\(type == .png ? "png" : "jpg")")
        try encoded.write(to: url)
        return ImageAttachment(id: id, mediaType: type.preferredMIMEType ?? "image/png", path: url.path,
                               width: image.width, height: image.height)
    }

    static func encode(_ image: CGImage, as type: UTType, quality: Double = 1) throws -> Data {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else {
            throw Failure(message: "Couldn't encode the image.")
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw Failure(message: "Couldn't encode the image.") }
        return out as Data
    }

    /// Rough prompt cost of one image, in estimator bytes (about 1000 tokens: models range from 256 to ~1500).
    public static let estimatedBytes = 3_300
}
