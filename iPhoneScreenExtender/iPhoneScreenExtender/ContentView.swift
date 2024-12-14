//
//  ContentView.swift
//  iPhoneScreenExtender
//
//  Created by Arman Mahjoor on 12/14/24.
//

import SwiftUI
import MetalKit

struct MetalView: UIViewRepresentable {
    let renderer: MetalRenderer
    
    init(renderer: MetalRenderer) {
        self.renderer = renderer
    }
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var webSocketClient = WebSocketClient()
    @State private var renderer: MetalRenderer?
    @State private var decoder: H264Decoder?
    @State private var metalView: MTKView?
    @State private var hostIP: String = ""
    
    var body: some View {
        ZStack {
            if let renderer = renderer {
                MetalView(renderer: renderer)
                    .edgesIgnoringSafeArea(.all)
            } else {
                Text("Initializing Metal renderer...")
            }
            
            VStack {
                Spacer()
                if !webSocketClient.isConnected {
                    TextField("Enter Mac's IP address", text: $hostIP)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                }
                HStack {
                    Button(action: connect) {
                        Text(webSocketClient.isConnected ? "Disconnect" : "Connect")
                            .padding()
                            .background(webSocketClient.isConnected ? Color.red : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .disabled(hostIP.isEmpty && !webSocketClient.isConnected)
                }
                .padding()
            }
        }
        .onAppear {
            setupComponents()
        }
    }
    
    private func setupComponents() {
        let mtkView = MTKView()
        self.metalView = mtkView
        
        guard let renderer = MetalRenderer(metalView: mtkView) else {
            print("Failed to create Metal renderer")
            return
        }
        self.renderer = renderer
        
        let decoder = H264Decoder()
        decoder.onDecodedFrame = { pixelBuffer in
            renderer.render(pixelBuffer: pixelBuffer, in: mtkView)
        }
        self.decoder = decoder
        
        webSocketClient.onFrameReceived = { [weak decoder] data in
            decoder?.decode(data)
        }
    }
    
    private func connect() {
        if webSocketClient.isConnected {
            webSocketClient.disconnect()
        } else {
            webSocketClient.connect(to: hostIP, port: 8080)
        }
    }
}