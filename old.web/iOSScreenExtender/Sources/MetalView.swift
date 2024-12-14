import SwiftUI
import MetalKit
import UIKit

struct MetalView: UIViewRepresentable {
    let renderer: MetalRenderer
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView(frame: .zero, device: renderer.device)
        mtkView.delegate = renderer
        mtkView.preferredFramesPerSecond = 60
        mtkView.framebufferOnly = true
        mtkView.drawableSize = mtkView.frame.size
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {}
} 