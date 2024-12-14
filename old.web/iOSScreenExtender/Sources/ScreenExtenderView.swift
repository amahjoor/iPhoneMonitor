import SwiftUI
import AVFoundation
import MetalKit

struct ScreenExtenderView: View {
    @StateObject private var viewModel = ScreenExtenderViewModel()
    
    var body: some View {
        ZStack {
            MetalView(renderer: viewModel.renderer)
                .ignoresSafeArea()
            
            if !viewModel.isConnected {
                VStack {
                    Text("Waiting for connection...")
                    ProgressView()
                }
            }
        }
        .onAppear {
            viewModel.connect()
        }
    }
}

class ScreenExtenderViewModel: ObservableObject {
    private var webSocketClient: WebSocketClient?
    private var decoder: H264Decoder?
    let renderer = MetalRenderer()
    
    @Published var isConnected = false
    
    init() {
        setupDecoder()
        setupWebSocket()
    }
    
    private func setupDecoder() {
        decoder = H264Decoder()
        decoder?.onDecodedFrame = { [weak self] pixelBuffer in
            self?.renderer.update(pixelBuffer: pixelBuffer)
        }
    }
    
    private func setupWebSocket() {
        webSocketClient = WebSocketClient()
        webSocketClient?.onConnected = { [weak self] in
            DispatchQueue.main.async {
                self?.isConnected = true
            }
        }
        
        webSocketClient?.onFrameReceived = { [weak self] data in
            self?.decoder?.decode(data)
        }
    }
    
    func connect() {
        webSocketClient?.connect()
    }
} 