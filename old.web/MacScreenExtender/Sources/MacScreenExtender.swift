import Foundation
import CoreGraphics
import AVFoundation

class ScreenExtender {
    private var displayStream: CGDisplayStream?
    private var webSocketServer: WebSocketServer?
    private var videoEncoder: H264Encoder?
    private var virtualDisplay: VirtualDisplay?
    private let port: Int = 8080
    
    init() {
        setupVirtualDisplay()
        setupWebSocketServer()
        setupVideoEncoder()
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
    
    private func setupVirtualDisplay() {
        virtualDisplay = VirtualDisplay(width: 1920, height: 1080)
        guard virtualDisplay?.create() == true else {
            print("Failed to create virtual display")
            return
        }
    }
    
    private func startStreaming() {
        guard let displayID = virtualDisplay?.currentDisplayID else {
            print("No virtual display available")
            return
        }
        let width = 1920 // Adjust based on iPhone resolution
        let height = 1080
        
        displayStream = CGDisplayStream(
            dispatchQueueDisplay: displayID,
            outputWidth: width,
            outputHeight: height,
            pixelFormat: Int32(kCVPixelFormatType_32BGRA),
            properties: nil,
            queue: DispatchQueue.global(qos: .userInteractive),
            handler: { [weak self] status, displayTime, frameSurface, updateRef in
                guard status == .frameComplete,
                      let frameSurface = frameSurface else { return }
                
                let pixelBuffer = self?.createPixelBuffer(from: frameSurface)
                if let pixelBuffer = pixelBuffer {
                    self?.videoEncoder?.encode(pixelBuffer)
                }
            }
        )
        
        displayStream?.start()
    }
    
    private func createPixelBuffer(from surface: IOSurfaceRef) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let width = IOSurfaceGetWidth(surface)
        let height = IOSurfaceGetHeight(surface)
        
        let pixelBufferAttributes = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        
        let status = CVPixelBufferCreateWithIOSurface(
            kCFAllocatorDefault,
            surface,
            pixelBufferAttributes,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess else {
            print("Failed to create pixel buffer: \(status)")
            return nil
        }
        
        return pixelBuffer
    }
    
    deinit {
        virtualDisplay?.destroy()
    }
} 