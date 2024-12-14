import Foundation
import VideoToolbox
import CoreVideo
import CoreMedia

class H264Decoder {
    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    var onDecodedFrame: ((CVPixelBuffer) -> Void)?
    
    private var sps: Data?
    private var pps: Data?
    
    init() {
        setupDecoder()
    }
    
    private func setupDecoder() {
        // We'll create the actual session when we receive the first frame with SPS and PPS
        print("H264Decoder: Waiting for SPS and PPS")
    }
    
    func decode(_ data: Data) {
        // Extract NAL units from the data
        let nalUnits = extractNALUnits(from: data)
        
        for nalUnit in nalUnits {
            let nalType = nalUnit[0] & 0x1F
            print("H264Decoder: Processing NAL unit type \(nalType)")
            
            switch nalType {
            case 7: // SPS
                print("H264Decoder: Found SPS NAL unit (\(nalUnit.count) bytes)")
                sps = nalUnit
            case 8: // PPS
                print("H264Decoder: Found PPS NAL unit (\(nalUnit.count) bytes)")
                pps = nalUnit
            case 5: // IDR Frame
                print("H264Decoder: Found IDR frame")
                if session == nil {
                    createDecoderSessionIfNeeded()
                }
                decodeFrame(nalUnit)
            default:
                if session != nil {
                    decodeFrame(nalUnit)
                }
            }
        }
    }
    
    private func extractNALUnits(from data: Data) -> [Data] {
        var nalUnits: [Data] = []
        var currentIndex = 0
        
        // Look for NAL unit start codes (0x00 0x00 0x00 0x01 or 0x00 0x00 0x01)
        while currentIndex < data.count {
            var startCodeLength = 0
            var nextStartCodeIndex = data.count
            
            // Find start code
            if currentIndex + 4 <= data.count &&
                data[currentIndex] == 0x00 &&
                data[currentIndex + 1] == 0x00 &&
                data[currentIndex + 2] == 0x00 &&
                data[currentIndex + 3] == 0x01 {
                startCodeLength = 4
            } else if currentIndex + 3 <= data.count &&
                data[currentIndex] == 0x00 &&
                data[currentIndex + 1] == 0x00 &&
                data[currentIndex + 2] == 0x01 {
                startCodeLength = 3
            }
            
            if startCodeLength > 0 {
                // Look for next start code
                var searchIndex = currentIndex + startCodeLength
                while searchIndex + 3 < data.count {
                    if (data[searchIndex] == 0x00 &&
                        data[searchIndex + 1] == 0x00 &&
                        data[searchIndex + 2] == 0x00 &&
                        data[searchIndex + 3] == 0x01) ||
                        (data[searchIndex] == 0x00 &&
                         data[searchIndex + 1] == 0x00 &&
                         data[searchIndex + 2] == 0x01) {
                        nextStartCodeIndex = searchIndex
                        break
                    }
                    searchIndex += 1
                }
                
                // Extract NAL unit
                let nalStartIndex = currentIndex + startCodeLength
                let nalUnit = data.subdata(in: nalStartIndex..<nextStartCodeIndex)
                if !nalUnit.isEmpty {
                    nalUnits.append(nalUnit)
                }
                
                currentIndex = nextStartCodeIndex
            } else {
                currentIndex += 1
            }
        }
        
        print("H264Decoder: Found \(nalUnits.count) NAL units")
        return nalUnits
    }
    
    private func createDecoderSessionIfNeeded() {
        guard let sps = sps, let pps = pps else {
            print("H264Decoder: Missing SPS or PPS")
            return
        }
        
        print("H264Decoder: Creating decoder session with SPS and PPS")
        
        // Create format description
        var formatDescription: CMFormatDescription?
        let parameterSets = [sps, pps]
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
        
        guard status == noErr, let formatDescription = formatDescription else {
            print("H264Decoder: Failed to create format description, status: \(status)")
            return
        }
        
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
        
        let decompressStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: decoderParameters,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )
        
        if decompressStatus == noErr {
            print("H264Decoder: Created decompression session successfully")
        } else {
            print("H264Decoder: Failed to create decompression session, status: \(decompressStatus)")
        }
    }
    
    private func decodeFrame(_ nalUnit: Data) {
        guard let session = session,
              let formatDescription = formatDescription else {
            print("H264Decoder: No valid session for decoding")
            return
        }
        
        var blockBuffer: CMBlockBuffer?
        let result = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: nalUnit.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: nalUnit.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard result == kCMBlockBufferNoErr,
              let blockBuffer = blockBuffer else {
            print("H264Decoder: Failed to create block buffer")
            return
        }
        
        let _ = nalUnit.withUnsafeBytes { buffer in
            CMBlockBufferReplaceDataBytes(
                with: buffer.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: nalUnit.count
            )
        }
        
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(value: 0, timescale: 1),
            decodeTimeStamp: CMTime.invalid
        )
        
        let status = CMSampleBufferCreateReady(
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
        
        if status != noErr {
            print("H264Decoder: Failed to create sample buffer, status: \(status)")
            return
        }
        
        if let sampleBuffer = sampleBuffer {
            let flags = VTDecodeFrameFlags(rawValue: 1)
            let decodeStatus = VTDecompressionSessionDecodeFrame(
                session,
                sampleBuffer: sampleBuffer,
                flags: flags,
                frameRefcon: nil,
                infoFlagsOut: nil
            )
            
            if decodeStatus != noErr {
                print("H264Decoder: Failed to decode frame, status: \(decodeStatus)")
            }
        }
    }
    
    func invalidateSession() {
        if let session = session {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }
        self.formatDescription = nil
        self.sps = nil
        self.pps = nil
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