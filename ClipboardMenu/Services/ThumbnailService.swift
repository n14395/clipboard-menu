import Foundation
import AppKit
@preconcurrency import AVFoundation

@MainActor
class ThumbnailService {
    func generateImageThumbnail(from data: Data, maxSize: CGFloat) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        return generateThumbnail(from: image, maxSize: maxSize)
    }

    func generateThumbnail(from image: NSImage, maxSize: CGFloat) -> Data? {
        let originalSize = image.size
        guard originalSize.width > 0 && originalSize.height > 0 else { return nil }

        // Calculate scaled size maintaining aspect ratio
        let scale: CGFloat
        if originalSize.width > originalSize.height {
            scale = maxSize / originalSize.width
        } else {
            scale = maxSize / originalSize.height
        }

        let newSize = NSSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        // Create scaled image
        let scaledImage = NSImage(size: newSize)
        scaledImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        scaledImage.unlockFocus()

        return scaledImage.pngData()
    }

    func generatePreviewImage(from path: String, maxSize: CGFloat) -> NSImage? {
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        return generatePreviewImage(from: image, maxSize: maxSize)
    }
    
    /// Generate a preview image from a video file by extracting a frame at 20% through the video
    func generateVideoPreviewImage(from path: String, maxSize: CGFloat) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize * 2, height: maxSize * 2)
        
        // Get video duration using async load (synchronous duration property is deprecated)
        var duration = CMTime.zero
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            if let loadedDuration = try? await asset.load(.duration) {
                duration = loadedDuration
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1.0)
        
        // Calculate time at 20% of the video
        let targetTime: CMTime
        if duration.seconds > 0 && !duration.seconds.isNaN {
            let targetSeconds = duration.seconds * 0.2
            targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        } else {
            // Fallback to 0 if duration is unavailable
            targetTime = CMTime(seconds: 0, preferredTimescale: 600)
        }
        
        do {
            let cgImage = try generator.copyCGImage(at: targetTime, actualTime: nil)
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            return generatePreviewImage(from: image, maxSize: maxSize)
        } catch {
            print("Failed to generate video preview: \(error)")
            return nil
        }
    }
    
    /// Async version that runs video frame extraction on a background thread
    nonisolated func generateVideoPreviewImageAsync(from path: String, maxSize: CGFloat) async -> NSImage? {
        let url = URL(fileURLWithPath: path)
        let asset = AVAsset(url: url)
        
        // Load duration asynchronously
        let duration: CMTime
        if let loadedDuration = try? await asset.load(.duration),
           loadedDuration.seconds > 0 && !loadedDuration.seconds.isNaN {
            duration = loadedDuration
        } else {
            duration = CMTime(seconds: 0, preferredTimescale: 600)
        }
        
        // Calculate time at 20% of the video
        let targetTime: CMTime
        if duration.seconds > 0 {
            let targetSeconds = duration.seconds * 0.2
            targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        } else {
            targetTime = CMTime(seconds: 0, preferredTimescale: 600)
        }
        
        // Run the synchronous image generation on a background thread
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: maxSize * 2, height: maxSize * 2)
                
                do {
                    let cgImage = try generator.copyCGImage(at: targetTime, actualTime: nil)
                    let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    
                    // Scale the image on main thread (NSGraphicsContext requires it)
                    DispatchQueue.main.async {
                        let scaledImage = self.generatePreviewImage(from: image, maxSize: maxSize)
                        continuation.resume(returning: scaledImage)
                    }
                } catch {
                    print("Failed to generate video preview: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func generatePreviewImage(from image: NSImage, maxSize: CGFloat) -> NSImage? {
        let originalSize = image.size
        guard originalSize.width > 0 && originalSize.height > 0 else { return nil }

        // If image is smaller than maxSize, return original
        if originalSize.width <= maxSize && originalSize.height <= maxSize {
            return image
        }

        // Calculate scaled size maintaining aspect ratio
        let scale: CGFloat
        if originalSize.width > originalSize.height {
            scale = maxSize / originalSize.width
        } else {
            scale = maxSize / originalSize.height
        }

        let newSize = NSSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        // Create scaled image
        let scaledImage = NSImage(size: newSize)
        scaledImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        scaledImage.unlockFocus()

        return scaledImage
    }
}
