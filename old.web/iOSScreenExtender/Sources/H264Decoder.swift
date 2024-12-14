import Foundation
import VideoToolbox
import CoreMedia

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
        
        let decoderCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionCallback,
            decompressionOutputRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        // Format description will be created with the first frame
        guard let formatDescription = formatDescription else { return }
        
        VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: decoderParameters as CFDictionary,
            outputCallback: &decoderCallback,
            decompressionSessionOut: &session
        )
    }
    
    func decode(_ data: Data) {
        let nalHeader: [UInt8] = [0x00, 0x00, 0x00, 0x01]
        var frameData = Data(nalHeader)
        frameData.append(data)
        
        frameData.withUnsafeBytes { buffer in
            let pointer = buffer.baseAddress!
            var spsSize: Int = 0
            var ppsSize: Int = 0
            
            // Find SPS and PPS if present
            if data[4] & 0x1F == 7 { // SPS
                for i in 4..<data.count - 4 {
                    if data[i..<i+4] == Data(nalHeader) {
                        spsSize = i - 4
                        break
                    }
                }
            }
            
            if spsSize > 0 { // Look for PPS
                for i in (4 + spsSize + 4)..<data.count - 4 {
                    if data[i..<i+4] == Data(nalHeader) {
                        ppsSize = i - (4 + spsSize + 4)
                        break
                    }
                }
            }
            
            if spsSize > 0 && ppsSize > 0 && formatDescription == nil {
                // Create format description from SPS and PPS
                var pointers: [UnsafePointer<UInt8>] = []
                var sizes: [Int] = []
                
                let spsPointer = pointer.advanced(by: 4)
                let ppsPointer = pointer.advanced(by: 4 + spsSize + 4)
                
                pointers.append(spsPointer.assumingMemoryBound(to: UInt8.self))
                pointers.append(ppsPointer.assumingMemoryBound(to: UInt8.self))
                sizes.append(spsSize)
                sizes.append(ppsSize)
                
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: pointers,
                    parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &formatDescription
                )
                
                setupDecoder()
            }
        }
        
        guard let session = session else { return }
        
        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: frameData.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: frameData.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard let blockBuffer = blockBuffer else { return }
        
        frameData.withUnsafeBytes { buffer in
            CMBlockBufferReplaceDataBytes(
                with: buffer.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: frameData.count
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
        
        guard let sampleBuffer = sampleBuffer else { return }
        
        VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [._EnableAsynchronousDecompression],
            frameRefcon: nil,
            infoFlagsOut: nil
        )
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
    guard let decoder = unsafeBitCast(decompressionOutputRefCon, to: H264Decoder.self),
          let imageBuffer = imageBuffer else { return }
    
    DispatchQueue.main.async {
        decoder.onDecodedFrame?(imageBuffer)
    }
} 