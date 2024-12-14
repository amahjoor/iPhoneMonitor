/*
    ScreenExtender.swift
    MacScreenExtender
  
    Created by Arman Mahjoor on 12/14/24.
 
    This file is the core of the MacScreenExtender application.
    It is responsible for capturing the screen and encoding it into an H.264 stream.
    The stream is then sent to the iPhone client via a WebSocket connection.
 */

import Foundation
import ScreenCaptureKit
import AVFoundation

class ScreenExtender: NSObject {
    private var stream: SCStream?
    private var webSocketServer: WebSocketServer?
    private var videoEncoder: H264Encoder?
    private let port: Int = 8080
    
    override init() {
        super.init()
        setupWebSocketServer()
        setupVideoEncoder()
        setupScreenCapture()
    }
    
    private func setupWebSocketServer() {
        webSocketServer = WebSocketServer(port: port)
        webSocketServer?.onClientConnected = { [weak self] client in
            print("iPhone client connected")
            self?.startStreaming()
        }
    }
    
    private func setupVideoEncoder() {
        videoEncoder = H264Encoder()
        videoEncoder?.onEncodedFrame = { [weak self] encodedData in
            self?.webSocketServer?.broadcast(data: encodedData)
        }
    }
    
    private func setupScreenCapture() {
        Task {
            do {
                // Get the main display
                let displays = try await SCShareableContent.current.displays
                guard let display = displays.first else {
                    print("No display found")
                    return
                }
                
                // Create filter for the display
                let filter = SCContentFilter(display: display, excludingWindows: [])
                
                // Configure stream
                let configuration = SCStreamConfiguration()
                configuration.width = 1920
                configuration.height = 1080
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                
                // Create stream
                stream = SCStream(filter: filter, configuration: configuration, delegate: self)
                
                // Add stream output
                try await stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue.global(qos: .userInteractive))
            } catch {
                print("Failed to setup screen capture: \(error)")
            }
        }
    }
    
    private func startStreaming() {
        Task {
            do {
                try await stream?.startCapture()
            } catch {
                print("Failed to start capture: \(error)")
            }
        }
    }
    
    deinit {
        Task {
            try? await stream?.stopCapture()
        }
    }
}

// MARK: - SCStreamDelegate
extension ScreenExtender: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stopped with error: \(error)")
    }
}

// MARK: - SCStreamOutput
extension ScreenExtender: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        
        videoEncoder?.encode(pixelBuffer)
    }
}