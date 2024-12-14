//
//  MetalRenderer.swift
//  iPhoneScreenExtender
//
//  Created by Arman Mahjoor on 12/14/24.
//

import Foundation
import Metal
import MetalKit
import CoreVideo

class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let vertexBuffer: MTLBuffer
    private let textureCache: CVMetalTextureCache
    
    private let vertices: [Float] = [
        -1.0, -1.0,  0.0, 1.0,
         1.0, -1.0,  1.0, 1.0,
        -1.0,  1.0,  0.0, 0.0,
         1.0,  1.0,  1.0, 0.0,
    ]
    
    init?(metalView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        
        self.device = device
        self.commandQueue = commandQueue
        
        metalView.device = device
        metalView.framebufferOnly = true
        metalView.colorPixelFormat = .bgra8Unorm
        
        // Create vertex buffer
        guard let vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        ) else {
            return nil
        }
        self.vertexBuffer = vertexBuffer
        
        // Create texture cache
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &textureCache
        )
        
        guard let cache = textureCache else {
            return nil
        }
        self.textureCache = cache
        
        // Create pipeline state
        let library = device.makeDefaultLibrary()
        let vertexFunction = library?.makeFunction(name: "vertexShader")
        let fragmentFunction = library?.makeFunction(name: "fragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        
        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
            return nil
        }
        self.pipelineState = pipelineState
        
        super.init()
        metalView.delegate = self
    }
    
    func draw(in view: MTKView) {
        // This will be called by MTKView's display loop
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle resize if needed
    }
    
    func render(pixelBuffer: CVPixelBuffer, in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        var texture: CVMetalTexture?
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &texture
        )
        
        guard let metalTexture = texture,
              let textureRef = CVMetalTextureGetTexture(metalTexture) else {
            return
        }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(textureRef, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
} 
