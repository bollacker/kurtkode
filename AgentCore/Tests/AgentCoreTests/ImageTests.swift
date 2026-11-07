import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AgentCore

/// A PNG of the given size: flat color, or random noise (which doesn't compress).
private func png(width: Int, height: Int, noise: Bool = false) throws -> Data {
    let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    if noise, let data = ctx.data {
        let bytes = data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * height)
        var seed: UInt32 = 12345
        for i in 0..<(ctx.bytesPerRow * height) { seed = seed &* 1103515245 &+ 12345; bytes[i] = UInt8(truncatingIfNeeded: seed >> 16) }
    }
    let image = try #require(ctx.makeImage())
    return try ImageStore.encode(image, as: .png)
}

@Suite struct ImageTests {
    private let dir = FileManager.default.temporaryDirectory.appending(path: "kk-images-\(UUID().uuidString.prefix(8))")

    @Test func downscalesToTheLongEdgeLimit() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try ImageStore.save(try png(width: 3000, height: 2000), in: dir)
        #expect(a.width == ImageStore.maxPixels)
        #expect(a.height == 1045)
        #expect(a.mediaType == "image/png")
        #expect(FileManager.default.fileExists(atPath: a.path))
        let small = try ImageStore.save(try png(width: 400, height: 300), in: dir)
        #expect(small.width == 400 && small.height == 300)             // never upscaled
    }

    @Test func largePNGsBecomeJPEGAndNonImagesAreRefused() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try ImageStore.save(try png(width: 1500, height: 1500, noise: true), in: dir)
        #expect(a.mediaType == "image/jpeg")
        #expect(throws: ImageStore.Failure.self) { try ImageStore.save(Data("not an image".utf8), in: dir) }
    }

    @Test func encodesImagesAsContentPartsOrANote() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        var m = ChatMessage.user("What's in this?")
        m.images = [try ImageStore.save(try png(width: 64, height: 64), in: dir)]
        guard case .object(let withImages) = WireFormat.encodeMessage(m, images: true),
              case .array(let parts)? = withImages["content"] else { Issue.record("no parts"); return }
        #expect(parts.count == 2)
        #expect(parts[0] == ["type": "text", "text": "What's in this?"])
        guard case .object(let part) = parts[1], case .object(let url)? = part["image_url"],
              case .string(let dataURL)? = url["url"] else { Issue.record("no image part"); return }
        #expect(dataURL.hasPrefix("data:image/png;base64,iVBOR"))

        guard case .object(let without) = WireFormat.encodeMessage(m, images: false),
              case .string(let text)? = without["content"] else { Issue.record("no text"); return }
        #expect(text == "What's in this?\n\n[1 image was attached here; this model can't see images]")
        #expect(TokenEstimator.bytes([m]) >= ImageStore.estimatedBytes)

        // The message round-trips through the session file with its attachment.
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(m))
        #expect(decoded.images == m.images)
    }
}
