import Foundation
import VideoToolbox
import CoreMedia
import QuartzCore

class H264Encoder {
    private var session: VTCompressionSession?
    var onEncodedFrame: ((Data) -> Void)?
    
    init() {
        setupEncoder()
    }
    
    private func setupEncoder() {
        let width = 1920
        let height = 1080
        
        VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: compressCallback,
            refcon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            compressionSessionOut: &session
        )
        
        guard let session = session else { return }
        
        // Configure encoder settings
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: 5_000_000))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: 60))
        
        VTCompressionSessionPrepareToEncodeFrames(session)
    }
    
    func encode(_ pixelBuffer: CVPixelBuffer) {
        guard let session = session else { return }
        
        let presentationTimeStamp = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600)
        let duration = CMTime(value: 1, timescale: 30)
        
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }
}

private func compressCallback(
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) {
    guard let outputCallbackRefCon = outputCallbackRefCon else { return }
    let encoder = Unmanaged<H264Encoder>.fromOpaque(outputCallbackRefCon).takeUnretainedValue()
    
    guard let sampleBuffer = sampleBuffer,
          let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
    
    var length = 0
    var dataPointer: UnsafeMutablePointer<Int8>?
    CMBlockBufferGetDataPointer(
        dataBuffer,
        atOffset: 0,
        lengthAtOffsetOut: nil,
        totalLengthOut: &length,
        dataPointerOut: &dataPointer
    )
    
    guard let pointer = dataPointer else { return }
    let data = Data(bytes: pointer, count: length)
    
    DispatchQueue.main.async {
        encoder.onEncodedFrame?(data)
    }
} 