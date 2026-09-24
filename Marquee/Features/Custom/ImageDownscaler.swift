import UIKit

// MARK: - ImageDownscaler

/// Shrinks user-picked photos to poster size before they are stored in SwiftData.
enum ImageDownscaler {

    /// Re-encodes `data` as JPEG with the longer side at most `maxDimension`
    /// pixels. The image is drawn through a 1x `UIGraphicsImageRenderer`, which
    /// bakes the EXIF orientation into the pixels so the result is always
    /// upright. Returns `nil` when `data` is not a decodable image.
    static func jpegData(from data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        guard !data.isEmpty, let image = UIImage(data: data) else { return nil }

        let targetSize = fittedSize(for: image.size, maxDimension: maxDimension)
        guard targetSize.width >= 1, targetSize.height >= 1 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let rendered = renderer.image { context in
            let bounds = CGRect(origin: .zero, size: targetSize)
            UIColor.white.setFill()
            context.fill(bounds)
            image.draw(in: bounds)
        }

        let clampedQuality = min(max(quality, 0), 1)
        return rendered.jpegData(compressionQuality: clampedQuality)
    }

    /// `size` scaled down (never up) so its longer side is at most
    /// `maxDimension`, rounded to whole pixels.
    static func fittedSize(for size: CGSize, maxDimension: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let limit = max(maxDimension, 1)
        let longest = max(size.width, size.height)
        guard longest > limit else {
            return CGSize(width: size.width.rounded(.down), height: size.height.rounded(.down))
        }
        let scale = limit / longest
        return CGSize(
            width: max((size.width * scale).rounded(), 1),
            height: max((size.height * scale).rounded(), 1)
        )
    }
}
