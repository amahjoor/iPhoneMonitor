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
        print("WebSocket: -------- Connection Attempt Started --------")
        print("WebSocket: Target: \(host):\(port)")
        print("WebSocket: Queue: \(queue.label)")
        lastHost = host
        lastPort = port
        
        // Create URL-based endpoint
        guard let url = URL(string: "ws://\(host):\(port)") else {
            print("WebSocket: Invalid URL format")
            return
        }
        let endpoint = NWEndpoint.url(url)
        print("WebSocket: Created URL endpoint: \(url)")
        
        // Create parameters with TCP options
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true
        
        // Add WebSocket protocol
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        wsOptions.maximumMessageSize = 1_000_000
        wsOptions.setAdditionalHeaders([("Upgrade", "websocket")])
        parameters.defaultProtocolStack.applicationProtocols = [wsOptions]
        
        print("WebSocket: Parameters configured:")
        print("  - Protocol stack: \(parameters.defaultProtocolStack.applicationProtocols)")
        print("  - Local endpoint reuse: \(parameters.allowLocalEndpointReuse)")
        
        // Set up connection with better error handling
        connection = NWConnection(to: endpoint, using: parameters)
        
        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                print("WebSocket: -------- State Change --------")
                print("WebSocket: New state: \(state)")
                
                switch state {
                case .ready:
                    print("WebSocket: Connection READY")
                    if let path = self?.connection?.currentPath {
                        print("WebSocket: Local endpoint: \(String(describing: path.localEndpoint))")
                        print("WebSocket: Remote endpoint: \(String(describing: path.remoteEndpoint))")
                        print("WebSocket: Available interfaces: \(path.availableInterfaces)")
                        print("WebSocket: Path status: \(path.status)")
                    }
                    self?.isConnected = true
                    self?.receiveNextFrame()
                case .setup:
                    print("WebSocket: Connection SETUP")
                case .preparing:
                    print("WebSocket: Connection PREPARING")
                    if let path = self?.connection?.currentPath {
                        print("WebSocket: Available interfaces: \(path.availableInterfaces)")
                        print("WebSocket: Path status: \(path.status)")
                        print("WebSocket: Unsatisfied Reason: \(String(describing: path.unsatisfiedReason))")
                    }
                case .waiting(let error):
                    print("WebSocket: Connection WAITING")
                    print("WebSocket: Error details: \(error.localizedDescription)")
                    if let path = self?.connection?.currentPath {
                        print("WebSocket: Path status: \(path.status)")
                        print("WebSocket: Available interfaces: \(path.availableInterfaces)")
                        print("WebSocket: Unsatisfied Reason: \(String(describing: path.unsatisfiedReason))")
                    }
                    // Attempt reconnect after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if let host = self?.lastHost, let port = self?.lastPort {
                            self?.connect(to: host, port: port)
                        }
                    }
                case .failed(let error):
                    print("WebSocket: Connection FAILED")
                    print("WebSocket: Error details: \(error.localizedDescription)")
                    if let path = self?.connection?.currentPath {
                        print("WebSocket: Final path status: \(path.status)")
                        print("WebSocket: Available interfaces: \(path.availableInterfaces)")
                        print("WebSocket: Unsatisfied Reason: \(String(describing: path.unsatisfiedReason))")
                    }
                    self?.isConnected = false
                    // Attempt reconnect after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if let host = self?.lastHost, let port = self?.lastPort {
                            self?.connect(to: host, port: port)
                        }
                    }
                case .cancelled:
                    print("WebSocket: Connection CANCELLED")
                    self?.isConnected = false
                default:
                    print("WebSocket: Unknown state change: \(state)")
                }
            }
        }
        
        print("WebSocket: Starting connection on queue: \(queue.label)")
        connection?.start(queue: queue)
    }
    
    private func receiveNextFrame() {
        guard let conn = connection else {
            print("WebSocket: Cannot receive - connection is nil")
            return
        }
        
        conn.receiveMessage { [weak self] content, context, isComplete, error in
            if let error = error {
                print("WebSocket: -------- Receive Error --------")
                print("WebSocket: Error details: \(error.localizedDescription)")
                print("WebSocket: Connection state: \(String(describing: self?.connection?.state))")
                if let path = self?.connection?.currentPath {
                    print("WebSocket: Path status: \(path.status)")
                    print("WebSocket: Available interfaces: \(path.availableInterfaces)")
                }
                DispatchQueue.main.async {
                    self?.isConnected = false
                }
                return
            }
            
            if let content = content,
               let metadata = context?.protocolMetadata.first as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .binary {
                print("WebSocket: -------- Frame Received --------")
                print("WebSocket: Frame size: \(content.count) bytes")
                print("WebSocket: Opcode: \(metadata.opcode)")
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
