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
    private var lastHost: String?
    private var lastPort: Int?
    
    @Published var isConnected = false
    var onFrameReceived: ((Data) -> Void)?
    
    func connect(to host: String, port: Int) {
        print("WebSocket: Attempting to connect to \(host):\(port)")
        lastHost = host
        lastPort = port
        
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)))
        
        // Create parameters with explicit WebSocket support
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        wsOptions.maximumMessageSize = 1_000_000 // Allow larger messages
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        
        // Set up connection
        connection = NWConnection(to: endpoint, using: parameters)
        
        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    print("WebSocket: Connected successfully")
                    self?.isConnected = true
                    self?.receiveNextFrame()
                case .setup:
                    print("WebSocket: Setting up connection...")
                case .preparing:
                    print("WebSocket: Preparing connection...")
                case .waiting(let error):
                    print("WebSocket: Waiting to connect... Error: \(error)")
                case .failed(let error):
                    print("WebSocket: Connection failed with error: \(error)")
                    self?.isConnected = false
                case .cancelled:
                    print("WebSocket: Connection cancelled")
                    self?.isConnected = false
                default:
                    print("WebSocket: State changed to \(state)")
                }
            }
        }
        
        print("WebSocket: Starting connection...")
        connection?.start(queue: queue)
        
        // Start receiving immediately
        receiveNextFrame()
    }
    
    private func receiveNextFrame() {
        guard let conn = connection else { return }
        
        conn.receiveMessage { [weak self] content, context, isComplete, error in
            if let error = error {
                print("WebSocket: Receive error: \(error)")
                DispatchQueue.main.async {
                    self?.isConnected = false
                }
                return
            }
            
            if let content = content,
               let metadata = context?.protocolMetadata.first as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .binary {
                print("WebSocket: Received frame of size: \(content.count) bytes")
                self?.onFrameReceived?(content)
            }
            
            // Continue receiving if still connected
            if self?.isConnected == true {
                self?.receiveNextFrame()
            }
        }
    }
    
    func disconnect() {
        print("WebSocket: Disconnecting...")
        connection?.cancel()
        connection = nil
        isConnected = false
    }
    
    deinit {
        disconnect()
    }
} 
