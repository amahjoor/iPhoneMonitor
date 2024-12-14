import Foundation
import VideoToolbox
import CoreVideo
import CoreMedia

class H264Decoder {
    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    var onDecodedFrame: ((CVPixelBuffer) -> Void)?
    
    init() {
        setupDecoder()
    }
    
    private func setupDecoder() {
        // We'll create the actual session when we receive the first frame with SPS and PPS
        // No need to set up parameters here since they'll be used in createSessionIfNeeded
    }
    
    func decode(_ data: Data) {
        // Check if this is a keyframe (contains SPS and PPS)
        if data.count > 4 && isKeyframe(data) {
            createSessionIfNeeded(with: data)
        }
        
        guard let session = session else { return }
        
        var blockBuffer: CMBlockBuffer?
        let result = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard result == kCMBlockBufferNoErr,
              let blockBuffer = blockBuffer else { return }
        
        let _ = data.withUnsafeBytes { buffer in
            CMBlockBufferReplaceDataBytes(
                with: buffer.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: data.count
            )
        }
        
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(value: 0, timescale: 1),
            decodeTimeStamp: CMTime.invalid
        )
        
        CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        
        if let sampleBuffer = sampleBuffer {
            let flags: VTDecodeFrameFlags = VTDecodeFrameFlags(rawValue: 1)
            VTDecompressionSessionDecodeFrame(
                session,
                sampleBuffer: sampleBuffer,
                flags: flags,
                frameRefcon: nil,
                infoFlagsOut: nil
            )
        }
    }
    
    private func isKeyframe(_ data: Data) -> Bool {
        // Simple check for NAL unit type 7 (SPS) or 8 (PPS)
        if data.count > 4 {
            let nalUnitType = data[4] & 0x1F
            return nalUnitType == 7 || nalUnitType == 8
        }
        return false
    }
    
    private func createSessionIfNeeded(with keyframeData: Data) {
        // Parse SPS and PPS from keyframe
        var parameterSets: [Data] = []
        var currentIndex = 0
        
        while currentIndex < keyframeData.count - 4 {
            if keyframeData[currentIndex..<currentIndex+4] == Data([0x00, 0x00, 0x00, 0x01]) {
                let nalUnitType = keyframeData[currentIndex + 4] & 0x1F
                if nalUnitType == 7 || nalUnitType == 8 { // SPS or PPS
                    var nextStartIndex = currentIndex + 4
                    while nextStartIndex < keyframeData.count - 4 {
                        if keyframeData[nextStartIndex..<nextStartIndex+4] == Data([0x00, 0x00, 0x00, 0x01]) {
                            break
                        }
                        nextStartIndex += 1
                    }
                    let parameterSet = keyframeData[currentIndex+4..<nextStartIndex]
                    parameterSets.append(Data(parameterSet))
                }
                currentIndex = currentIndex + 4
            } else {
                currentIndex += 1
            }
        }
        
        guard parameterSets.count >= 2 else { return }
        
        // Create format description
        var formatDescription: CMFormatDescription?
        let parameterSetPointers: [UnsafePointer<UInt8>] = parameterSets.map { $0.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) } }
        let parameterSetSizes: [Int] = parameterSets.map { $0.count }
        
        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: parameterSets.count,
            parameterSetPointers: parameterSetPointers,
            parameterSetSizes: parameterSetSizes,
            nalUnitHeaderLength: 4,
            formatDescriptionOut: &formatDescription
        )
        
        guard status == noErr,
              let formatDescription = formatDescription else { return }
        
        self.formatDescription = formatDescription
        
        // Create decompression session
        let decoderParameters = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ] as CFDictionary
        
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionCallback,
            decompressionOutputRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: decoderParameters,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )
    }
    
    func invalidateSession() {
        if let session = session {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }
    }
    
    deinit {
        invalidateSession()
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
          status == noErr,
          let imageBuffer = imageBuffer else { return }
    
    let decoder = Unmanaged<H264Decoder>.fromOpaque(decompressionOutputRefCon).takeUnretainedValue()
    decoder.onDecodedFrame?(imageBuffer)
}