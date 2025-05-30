/*
    H264Encoder.swift
    MacScreenExtender

    Created by Arman Mahjoor on 12/14/2024

    This file is the H.264 encoder that is used to encode the screen stream into an H.264 stream.
*/

import Foundation
import VideoToolbox
import CoreMedia
import QuartzCore
import CoreVideo

// Add CVPixelBuffer extension
extension CVPixelBuffer {
    static func create(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ] as [String: Any]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess else {
            print("Failed to create pixel buffer: \(status)")
            return nil
        }
        
        return pixelBuffer
    }
}

enum H264EncoderError: Error {
    case sessionCreationFailed
    case compressionFailed(OSStatus)
    case invalidPixelBuffer
    
    var localizedDescription: String {
        switch self {
        case .sessionCreationFailed:
            return "Failed to create encoding session"
        case .compressionFailed(let status):
            return "Compression failed with status: \(status)"
        case .invalidPixelBuffer:
            return "Invalid pixel buffer provided"
        }
    }
}

class H264Encoder {
    private var session: VTCompressionSession?
    private var formatDescription: CMFormatDescription?
    private let width: Int
    private let height: Int
    private let bitRate: Int
    private let frameRate: Int
    internal var sps: Data?
    internal var pps: Data?
    var onEncodedFrame: ((Data) -> Void)?
    
    init(width: Int = 1920, height: Int = 1080, bitRate: Int = 5_000_000, frameRate: Int = 60) {
        self.width = width
        self.height = height
        self.bitRate = bitRate
        self.frameRate = frameRate
        setupEncoder()
    }
    
    private func setupEncoder() {
        let encoderSpecification: [String: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true,
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true,
            kVTCompressionPropertyKey_ProfileLevel as String: kVTProfileLevel_H264_High_AutoLevel,
            kVTCompressionPropertyKey_RealTime as String: true
        ]
        
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: encoderSpecification as CFDictionary,
            imageBufferAttributes: pixelBufferAttributes as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: compressCallback,
            refcon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            compressionSessionOut: &session
        )
        
        guard status == noErr, let session = session else {
            print("H264Encoder: Failed to create compression session with status: \(status)")
            return
        }
        
        // Configure encoder settings for low latency and reliable keyframes
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: 30))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: frameRate))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitRate))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: [bitRate / 8, 1] as CFArray)
        
        // Force keyframe every 1 second
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 1))
        
        // Set H.264 specific properties
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_H264EntropyMode, value: kVTH264EntropyMode_CABAC)
        
        // Ensure clean aperture and pixel aspect ratio are set
        let cleanAperture = [
            kCVImageBufferCleanApertureWidthKey: width,
            kCVImageBufferCleanApertureHeightKey: height,
            kCVImageBufferCleanApertureHorizontalOffsetKey: 0,
            kCVImageBufferCleanApertureVerticalOffsetKey: 0
        ] as CFDictionary
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_CleanAperture, value: cleanAperture)
        
        let pixelAspectRatio = [
            kCVImageBufferPixelAspectRatioHorizontalSpacingKey: 1,
            kCVImageBufferPixelAspectRatioVerticalSpacingKey: 1
        ] as CFDictionary
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_PixelAspectRatio, value: pixelAspectRatio)
        
        // Request keyframe for first frame
        forceNextKeyframe = true
        frameCount = 0
        
        // Prepare session
        VTCompressionSessionPrepareToEncodeFrames(session)
        
        print("H264Encoder: Encoder setup complete")
    }
    
    private func createSampleBuffer(session: VTCompressionSession) -> CMSampleBuffer? {
        // Create a sample pixel buffer
        guard let pixelBuffer = CVPixelBuffer.create(width: width, height: height) else {
            print("H264Encoder: Failed to create pixel buffer")
            return nil
        }
        
        // Lock base address
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        
        // Fill with black
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            memset(baseAddress, 0, bytesPerRow * height)
        }
        
        // Encode a single frame
        let presentationTimeStamp = CMTime(value: 0, timescale: 1)
        let duration = CMTime(value: 1, timescale: Int32(frameRate))
        
        var outputFlags: VTEncodeInfoFlags = []
        var sampleBuffer: CMSampleBuffer?
        
        let encodeStatus = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: &outputFlags
        )
        
        if encodeStatus != noErr {
            print("H264Encoder: Failed to encode sample frame, status: \(encodeStatus)")
            return nil
        }
        
        // Wait for the encoded frame
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: presentationTimeStamp + duration)
        
        return sampleBuffer
    }
    
    private var forceNextKeyframe = true
    private var frameCount = 0
    private let keyframeInterval = 30 // Reduced from 60 to 30 for more frequent keyframes
    
    func encode(_ pixelBuffer: CVPixelBuffer) {
        guard let session = session else { return }
        
        frameCount += 1
        if frameCount >= keyframeInterval {
            forceNextKeyframe = true
            frameCount = 0
            print("H264Encoder: Forcing keyframe due to interval")
        }
        
        let presentationTimeStamp = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: CMTimeScale(frameRate * 2))
        let duration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        
        var frameProperties: [String: Any] = [:]
        if forceNextKeyframe {
            frameProperties[kVTEncodeFrameOptionKey_ForceKeyFrame as String] = kCFBooleanTrue
            print("H264Encoder: Forcing keyframe")
            forceNextKeyframe = false
        }
        
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration,
            frameProperties: frameProperties as CFDictionary,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
        
        if status != noErr {
            print("H264Encoder: Encoding failed with status: \(status)")
            forceNextKeyframe = true
        }
    }
    
    internal func packageNALUnit(_ data: Data) -> Data {
        let startCode = Data([0x00, 0x00, 0x00, 0x01])
        return data.starts(with: startCode) ? data : startCode + data
    }
    
    func invalidateSession() {
        if let session = session {
            VTCompressionSessionInvalidate(session)
            self.session = nil
        }
    }
    
    deinit {
        invalidateSession()
    }
}

private func compressCallback(
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) {
    guard let outputCallbackRefCon = outputCallbackRefCon,
          status == noErr else { return }
    
    let encoder = Unmanaged<H264Encoder>.fromOpaque(outputCallbackRefCon).takeUnretainedValue()
    
    guard let sampleBuffer = sampleBuffer,
          let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
    
    var length = 0
    var dataPointer: UnsafeMutablePointer<Int8>?
    let blockBufferStatus = CMBlockBufferGetDataPointer(
        dataBuffer,
        atOffset: 0,
        lengthAtOffsetOut: nil,
        totalLengthOut: &length,
        dataPointerOut: &dataPointer
    )
    
    guard blockBufferStatus == kCMBlockBufferNoErr,
          let pointer = dataPointer else { return }
    
    // Check if this is a keyframe
    let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
    let isKeyframe = attachments?.first?[kCMSampleAttachmentKey_NotSync] == nil
    
    if isKeyframe {
        print("H264Encoder: Keyframe detected")
        
        // For keyframes, get fresh SPS and PPS
        if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
            var spsSize: Int = 0
            var spsCount: Int = 0
            var ppsSize: Int = 0
            var ppsCount: Int = 0
            
            // Get SPS
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: 0,
                parameterSetPointerOut: nil,
                parameterSetSizeOut: &spsSize,
                parameterSetCountOut: &spsCount,
                nalUnitHeaderLengthOut: nil
            )
            
            // Get PPS
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: 1,
                parameterSetPointerOut: nil,
                parameterSetSizeOut: &ppsSize,
                parameterSetCountOut: &ppsCount,
                nalUnitHeaderLengthOut: nil
            )
            
            var spsData: Data?
            var ppsData: Data?
            
            if spsSize > 0 {
                var spsPointer: UnsafePointer<UInt8>?
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    formatDescription,
                    parameterSetIndex: 0,
                    parameterSetPointerOut: &spsPointer,
                    parameterSetSizeOut: nil,
                    parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil
                )
                if let spsPtr = spsPointer {
                    spsData = Data(bytes: spsPtr, count: spsSize)
                }
            }
            
            if ppsSize > 0 {
                var ppsPointer: UnsafePointer<UInt8>?
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    formatDescription,
                    parameterSetIndex: 1,
                    parameterSetPointerOut: &ppsPointer,
                    parameterSetSizeOut: nil,
                    parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil
                )
                if let ppsPtr = ppsPointer {
                    ppsData = Data(bytes: ppsPtr, count: ppsSize)
                }
            }
            
            // Send SPS and PPS with start codes
            let startCode = Data([0x00, 0x00, 0x00, 0x01])
            
            if let spsData = spsData {
                let spsWithStartCode = startCode + spsData
                print("H264Encoder: Sending SPS (\(spsData.count) bytes)")
                DispatchQueue.main.async {
                    encoder.onEncodedFrame?(spsWithStartCode)
                }
            }
            
            if let ppsData = ppsData {
                let ppsWithStartCode = startCode + ppsData
                print("H264Encoder: Sending PPS (\(ppsData.count) bytes)")
                DispatchQueue.main.async {
                    encoder.onEncodedFrame?(ppsWithStartCode)
                }
            }
        }
    }
    
    // Get NAL units from the sample buffer
    var nalUnits: [Data] = []
    var currentOffset = 0
    
    while currentOffset < length {
        var nalLength: UInt32 = 0
        memcpy(&nalLength, pointer.advanced(by: currentOffset), 4)
        
        // Convert from big-endian to host
        nalLength = CFSwapInt32BigToHost(nalLength)
        
        let nalStartOffset = currentOffset + 4
        let nalData = Data(bytes: pointer.advanced(by: nalStartOffset), count: Int(nalLength))
        
        // Add start code and NAL unit
        let startCode = Data([0x00, 0x00, 0x00, 0x01])
        nalUnits.append(startCode + nalData)
        
        currentOffset = nalStartOffset + Int(nalLength)
    }
    
    // Send each NAL unit
    for nalUnit in nalUnits {
        if let firstByte = nalUnit.dropFirst(4).first {
            let nalType = firstByte & 0x1F
            print("H264Encoder: Sending NAL unit type \(nalType) (\(nalUnit.count) bytes)")
            DispatchQueue.main.async {
                encoder.onEncodedFrame?(nalUnit)
            }
        }
    }
}
