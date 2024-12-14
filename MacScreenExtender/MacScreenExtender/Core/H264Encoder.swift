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
    private let width: Int
    private let height: Int
    private let bitRate: Int
    private let frameRate: Int
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
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true
        ]
        
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
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
            print("Failed to create compression session with status: \(status)")
            return
        }
        
        // Configure encoder settings for low latency
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: frameRate))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: frameRate))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitRate))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: [bitRate / 8, 1] as CFArray)
        
        // Enable B-frames for better compression
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowTemporalCompression, value: kCFBooleanTrue)
        
        // Set encoding quality
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_Quality, value: NSNumber(value: 0.7))
        
        VTCompressionSessionPrepareToEncodeFrames(session)
    }
    
    func encode(_ pixelBuffer: CVPixelBuffer) {
        guard let session = session else { return }
        
        let presentationTimeStamp = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: CMTimeScale(frameRate * 2))
        let duration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
        
        if status != noErr {
            print("Encoding failed with status: \(status)")
        }
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
    
    let data = Data(bytes: pointer, count: length)
    
    DispatchQueue.main.async {
        encoder.onEncodedFrame?(data)
    }
}
