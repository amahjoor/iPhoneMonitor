//
//  WebSocketClient.swift
//  iPhoneScreenExtender
//
//  Created by Arman Mahjoor on 12/14/24.
//

import Foundation
import Network

class WebSocketClient: ObservableObject {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.arman.iphonescreenextender.websocket")
    
    @Published var isConnected = false
    var onFrameReceived: ((Data) -> Void)?
    
    func connect(to host: String, port: Int) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)))
        
        let parameters = NWParameters(tls: nil)
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        
        connection = NWConnection(to: endpoint, using: parameters)
        
        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    print("WebSocket: Connected")
                    self?.isConnected = true
                    self?.receiveNextFrame()
                case .failed(let error):
                    print("WebSocket: Connection failed: \(error)")
                    self?.isConnected = false
                    self?.reconnect()
                case .cancelled:
                    print("WebSocket: Connection cancelled")
                    self?.isConnected = false
                default:
                    break
                }
            }
        }
        
        connection?.start(queue: queue)
    }
    
    private func reconnect() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self,
                  !self.isConnected else { return }
            
            print("WebSocket: Attempting to reconnect...")
            self.connection?.cancel()
            self.connect(to: "localhost", port: 8080) // You might want to make these configurable
        }
    }
    
    private func receiveNextFrame() {
        connection?.receiveMessage { [weak self] content, context, isComplete, error in
            if let error = error {
                print("WebSocket: Receive error: \(error)")
                return
            }
            
            if let content = content,
               let metadata = context?.protocolMetadata.first as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .binary {
                self?.onFrameReceived?(content)
            }
            
            self?.receiveNextFrame()
        }
    }
    
    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
    }
    
    deinit {
        disconnect()
    }
} 
