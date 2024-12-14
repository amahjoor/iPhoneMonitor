import Foundation
import Metal
import MetalKit

class MetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    // ... rest of the class
} 