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
            let nalTypeName = getNALUnitTypeName(nalType)
            print("H264Decoder: Processing NAL unit type \(nalType) (\(nalTypeName)) size: \(nalUnit.count) bytes")
            
            switch nalType {
            case 7: // SPS
                print("H264Decoder: Found SPS NAL unit (\(nalUnit.count) bytes)")
                sps = nalUnit
                print("H264Decoder: SPS data: \(nalUnit.map { String(format: "%02X", $0) }.joined())")
            case 8: // PPS
                print("H264Decoder: Found PPS NAL unit (\(nalUnit.count) bytes)")
                pps = nalUnit
                print("H264Decoder: PPS data: \(nalUnit.map { String(format: "%02X", $0) }.joined())")
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
                
                // Extract NAL unit including start code
                let nalUnit = data.subdata(in: currentIndex..<nextStartCodeIndex)
                if nalUnit.count > startCodeLength {
                    nalUnits.append(nalUnit)
                }
                
                currentIndex = nextStartCodeIndex
            } else {
                // If no start code found at current position, treat entire remaining data as one NAL unit
                if currentIndex == 0 {
                    let startCode = Data([0x00, 0x00, 0x00, 0x01])
                    nalUnits.append(startCode + data)
                }
                break
            }
        }
        
        return nalUnits
    }
    
    private func createDecoderSessionIfNeeded() {
        guard let sps = sps, let pps = pps else {
            print("H264Decoder: Missing SPS or PPS")
            return
        }
        
        print("H264Decoder: Creating decoder session with SPS and PPS")
        
        // Add NAL start code if not present
        let startCode = Data([0x00, 0x00, 0x00, 0x01])
        let spsWithStartCode = sps.starts(with: startCode) ? sps : startCode + sps
        let ppsWithStartCode = pps.starts(with: startCode) ? pps : startCode + pps
        
        // Create format description
        var formatDescription: CMFormatDescription?
        let parameterSets = [spsWithStartCode, ppsWithStartCode]
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
        
        // Create decompression session with hardware acceleration
        let decoderParameters = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: 1920,
            kCVPixelBufferHeightKey as String: 1080,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ] as [String: Any]
        
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionCallback,
            decompressionOutputRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        let decompressStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: [
                kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder as String: true,
                kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder as String: true
            ] as CFDictionary,
            imageBufferAttributes: decoderParameters as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )
        
        if decompressStatus == noErr {
            print("H264Decoder: Created decompression session successfully")
            
            // Configure decoder for low latency
            if let session = session {
                VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
                VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_ThreadCount, value: NSNumber(value: 1))
                VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_MaximizePowerEfficiency, value: kCFBooleanFalse)
            }
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
        
        // Ensure NAL unit has start code
        let startCode = Data([0x00, 0x00, 0x00, 0x01])
        let nalUnitWithStartCode = nalUnit.starts(with: startCode) ? nalUnit : startCode + nalUnit
        
        var blockBuffer: CMBlockBuffer?
        let result = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: nalUnitWithStartCode.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: nalUnitWithStartCode.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard result == kCMBlockBufferNoErr,
              let blockBuffer = blockBuffer else {
            print("H264Decoder: Failed to create block buffer")
            return
        }
        
        let _ = nalUnitWithStartCode.withUnsafeBytes { buffer in
            CMBlockBufferReplaceDataBytes(
                with: buffer.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: nalUnitWithStartCode.count
            )
        }
        
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),  // Assuming 60 FPS
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
            let flags = VTDecodeFrameFlags._EnableAsynchronousDecompression
            let decodeStatus = VTDecompressionSessionDecodeFrame(
                session,
                sampleBuffer: sampleBuffer,
                flags: flags,
                frameRefcon: nil,
                infoFlagsOut: nil
            )
            
            if decodeStatus != noErr {
                print("H264Decoder: Failed to decode frame, status: \(decodeStatus)")
                
                // If decoding fails, try to recreate the session
                if decodeStatus == kVTInvalidSessionErr {
                    print("H264Decoder: Invalid session, attempting to recreate")
                    invalidateSession()
                    createDecoderSessionIfNeeded()
                }
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
    
    private func getNALUnitTypeName(_ type: UInt8) -> String {
        switch type {
        case 0: return "Unspecified"
        case 1: return "Coded slice"
        case 2: return "Coded slice data partition A"
        case 3: return "Coded slice data partition B"
        case 4: return "Coded slice data partition C"
        case 5: return "IDR"
        case 6: return "SEI"
        case 7: return "SPS"
        case 8: return "PPS"
        case 9: return "Access unit delimiter"
        case 10: return "End of sequence"
        case 11: return "End of stream"
        case 12: return "Filler data"
        case 13: return "Sequence parameter set extension"
        case 14: return "Prefix NAL unit"
        case 15: return "Subset sequence parameter set"
        case 16: return "Reserved"
        case 17: return "Reserved"
        case 18: return "Reserved"
        case 19: return "Coded slice of an auxiliary coded picture"
        case 20: return "Coded slice extension"
        case 21: return "Coded slice extension for depth view"
        case 22: return "Reserved"
        case 23: return "Reserved"
        case 24: return "Unspecified"
        case 25: return "Unspecified"
        case 26: return "Unspecified"
        case 27: return "Unspecified"
        case 28: return "Unspecified"
        case 29: return "Unspecified"
        case 30: return "Unspecified"
        case 31: return "Unspecified"
        default: return "Unknown"
        }
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