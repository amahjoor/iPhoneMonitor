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
import CoreGraphics
import CoreMedia
import Network

enum ScreenExtenderError: Error {
    case noDisplaysFound
}

class ScreenExtender: NSObject {
    private var stream: SCStream?
    private var webSocketServer: WebSocketServer?
    private var videoEncoder: H264Encoder?
    private let port: Int = 8080
    private let setupQueue = DispatchQueue(label: "com.arman.macscreenextender.setup", qos: .userInitiated)
    
    // Configuration
    struct Configuration {
        var width: Int = 1920
        var height: Int = 1080
        var frameRate: Int = 60
        var bitRate: Int = 5_000_000
        var displayID: CGDirectDisplayID = CGMainDisplayID()
    }
    
    var configuration = Configuration()
    var isStreaming: Bool = false
    var isInitialized: Bool = false
    var onInitialized: (() -> Void)?
    
    override init() {
        super.init()
        print("ScreenExtender: Initializing...")
        setupQueue.async { [weak self] in
            self?.setupComponents()
        }
    }
    
    private func setupComponents() {
        setupWebSocketServer()
        setupVideoEncoder()
        isInitialized = true
        print("ScreenExtender: Initialization complete")
        DispatchQueue.main.async { [weak self] in
            self?.onInitialized?()
        }
    }
    
    private func setupWebSocketServer() {
        print("ScreenExtender: Setting up WebSocket server on port \(port)")
        webSocketServer = WebSocketServer(port: port)
        webSocketServer?.onClientConnected = { [weak self] _ in
            print("ScreenExtender: iPhone client connected")
            self?.startStreaming()
        }
        
        webSocketServer?.onClientDisconnected = { [weak self] _ in
            print("ScreenExtender: iPhone client disconnected")
            self?.stopStreaming()
        }
    }
    
    private func setupVideoEncoder() {
        print("ScreenExtender: Setting up H264 encoder (\(configuration.width)x\(configuration.height) @ \(configuration.frameRate)fps)")
        videoEncoder = H264Encoder(width: configuration.width,
                                 height: configuration.height,
                                 bitRate: configuration.bitRate,
                                 frameRate: configuration.frameRate)
        
        videoEncoder?.onEncodedFrame = { [weak self] encodedData in
            print("ScreenExtender: Encoded frame: \(encodedData.count) bytes")
            self?.webSocketServer?.broadcast(data: encodedData)
        }
    }
    
    private func setupScreenCapture() async throws {
        print("ScreenExtender: Setting up screen capture...")
        
        // Get shareable content
        let content = try await SCShareableContent.current
        
        // Get the main display
        guard let display = content.displays.first else {
            throw ScreenExtenderError.noDisplaysFound
        }
        
        print("ScreenExtender: Using display: \(display.displayID)")
        
        // Create filter for the display
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        // Configure stream
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = configuration.width
        streamConfig.height = configuration.height
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(configuration.frameRate))
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfig.queueDepth = 5
        streamConfig.showsCursor = true
        
        // Create stream
        stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        print("ScreenExtender: Stream created")
        
        // Add stream output
        if let stream = stream {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue.global(qos: .userInteractive))
            print("ScreenExtender: Stream output added")
        } else {
            throw ScreenExtenderError.noDisplaysFound
        }
    }
    
    func startStreaming() {
        guard !isStreaming else {
            print("ScreenExtender: Already streaming")
            return
        }
        
        guard isInitialized else {
            print("ScreenExtender: Not initialized yet")
            return
        }
        
        print("ScreenExtender: Starting stream...")
        Task {
            do {
                try await setupScreenCapture()
                try await stream?.startCapture()
                isStreaming = true
                print("ScreenExtender: Stream started successfully")
            } catch {
                print("ScreenExtender: Failed to start capture: \(error)")
                // Notify client of error
                let errorData = "Error: \(error.localizedDescription)".data(using: .utf8) ?? Data()
                webSocketServer?.broadcast(data: errorData)
            }
        }
    }
    
    func stopStreaming() {
        guard isStreaming else {
            print("ScreenExtender: Not streaming")
            return
        }
        
        print("ScreenExtender: Stopping stream...")
        Task {
            do {
                try await stream?.stopCapture()
                isStreaming = false
                print("ScreenExtender: Stream stopped successfully")
            } catch {
                print("ScreenExtender: Failed to stop capture: \(error)")
            }
        }
    }
    
    func updateConfiguration(_ newConfig: Configuration) {
        print("ScreenExtender: Updating configuration...")
        let wasStreaming = isStreaming
        if wasStreaming {
            stopStreaming()
        }
        
        configuration = newConfig
        setupVideoEncoder()
        
        if wasStreaming {
            startStreaming()
        }
        print("ScreenExtender: Configuration updated")
    }
    
    deinit {
        print("ScreenExtender: Cleaning up...")
        stopStreaming()
        videoEncoder = nil
        print("ScreenExtender: Cleanup complete")
    }
}

// MARK: - SCStreamDelegate
extension ScreenExtender: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("ScreenExtender: Stream stopped with error: \(error)")
        isStreaming = false
        // Try to restart the stream after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            print("ScreenExtender: Attempting to restart stream...")
            self?.startStreaming()
        }
    }
}

// MARK: - SCStreamOutput
extension ScreenExtender: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let pixelBuffer = sampleBuffer.imageBuffer,
              isStreaming else { return }
        
        videoEncoder?.encode(pixelBuffer)
    }
}