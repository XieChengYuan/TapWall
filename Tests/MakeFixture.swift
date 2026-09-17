import AppKit
import AVFoundation
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 960, AVVideoHeightKey: 540])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 960, kCVPixelBufferHeightKey as String: 540])
writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
for frame in 0..<180 {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
    var buffer: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    let pixel = buffer!; CVPixelBufferLockBaseAddress(pixel, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: 960, height: 540, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    ctx.setFillColor(NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.19, alpha: 1).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 960, height: 540))
    ctx.setFillColor(NSColor(calibratedRed: 0.4, green: 0.75, blue: 0.95, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: 50 + Double(frame) * 4, y: 240 + sin(Double(frame) / 15) * 100, width: 80, height: 80))
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    (String(format: "TapWall   %0.2f s", Double(frame) / 30) as NSString).draw(at: CGPoint(x: 60, y: 60), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 38, weight: .medium), .foregroundColor: NSColor.white])
    NSGraphicsContext.restoreGraphicsState(); CVPixelBufferUnlockBaseAddress(pixel, [])
    adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0); writer.finishWriting { done.signal() }; done.wait()
precondition(writer.status == .completed)
print(url.path)
