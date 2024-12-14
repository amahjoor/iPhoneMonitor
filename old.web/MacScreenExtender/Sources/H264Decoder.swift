import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo
import Dispatch

class H264Decoder {
    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    var onDecodedFrame: ((CVPixelBuffer) -> Void)?
    
    init() {
        setupDecoder()
    }
    
    private func setupDecoder() {
        let decoderParameters = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ] as [String: Any]
        
        var decoderCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionCallback,
            decompressionOutputRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        // ... rest of the function
    }
}

private func decompressionCallback(
    decompressionOutputRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTDecodeInfoFlags,
    imageBuffer: CVImageBuffer?,
    presentationTimeStamp: CMTime,
    duration: CMTime
) {
    guard let decompressionOutputRefCon = decompressionOutputRefCon,
          let imageBuffer = imageBuffer else { return }
    
    let decoder = Unmanaged<H264Decoder>.fromOpaque(decompressionOutputRefCon).takeUnretainedValue()
    
    DispatchQueue.main.async {
        decoder.onDecodedFrame?(imageBuffer)
    }
} 