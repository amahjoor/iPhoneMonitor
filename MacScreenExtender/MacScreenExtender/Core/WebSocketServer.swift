/*
    WebSocketServer.swift
    MacScreenExtender

    Created by Arman Mahjoor on 12/14/24.

    This file is the WebSocket server that is used to send the screen stream to the iPhone client.
*/

import Foundation
import Network

class WebSocketServer {
    private var listener: NWListener?
    private var connectedClients: [NWConnection] = []
    private let networkQueue = DispatchQueue(label: "com.arman.macscreenextender.network", qos: .userInitiated)
    var onClientConnected: ((NWConnection) -> Void)?
    var onClientDisconnected: ((NWConnection) -> Void)?
    
    init(port: Int) {
        setupListener(port: port)
    }
    
    private func setupListener(port: Int) {
        print("WebSocketServer: -------- Setup Started --------")
        print("WebSocketServer: Port: \(port)")
        print("WebSocketServer: Queue: \(networkQueue.label)")
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true
        
        // Add WebSocket protocol
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        wsOptions.maximumMessageSize = 1_000_000
        wsOptions.setAdditionalHeaders([("Upgrade", "websocket")])
        parameters.defaultProtocolStack.applicationProtocols = [wsOptions]
        
        print("WebSocketServer: Parameters configured:")
        print("  - Protocol stack: \(parameters.defaultProtocolStack.applicationProtocols)")
        print("  - Local endpoint reuse: \(parameters.allowLocalEndpointReuse)")
        print("  - TCP keepalive: enabled")
        print("  - Fast open: enabled")
        
        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(port)))
            
            listener?.stateUpdateHandler = { [weak self] state in
                self?.networkQueue.async {
                    print("WebSocketServer: -------- Listener State Change --------")
                    print("WebSocketServer: New state: \(state)")
                    
                    switch state {
                    case .ready:
                        print("WebSocketServer: Listener READY on port \(port)")
                        if let endpoint = self?.listener?.port {
                            print("WebSocketServer: Bound to port: \(endpoint)")
                        }
                    case .failed(let error):
                        print("WebSocketServer: Listener FAILED")
                        print("WebSocketServer: Error details: \(error.localizedDescription)")
                        // Attempt restart after delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self?.setupListener(port: port)
                        }
                    case .setup:
                        print("WebSocketServer: Listener SETUP")
                    case .waiting(let error):
                        print("WebSocketServer: Listener WAITING")
                        print("WebSocketServer: Error details: \(error.localizedDescription)")
                    case .cancelled:
                        print("WebSocketServer: Listener CANCELLED")
                    default:
                        print("WebSocketServer: Unknown listener state: \(state)")
                    }
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                print("WebSocketServer: -------- New Connection --------")
                print("WebSocketServer: Remote endpoint: \(connection.endpoint)")
                self?.networkQueue.async {
                    self?.handleNewConnection(connection)
                }
            }
            
            print("WebSocketServer: Starting listener on queue: \(networkQueue.label)")
            listener?.start(queue: networkQueue)
        } catch {
            print("WebSocketServer: -------- Setup Failed --------")
            print("WebSocketServer: Error details: \(error.localizedDescription)")
            // Attempt restart after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.setupListener(port: port)
            }
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        print("WebSocketServer: -------- Handling Connection --------")
        print("WebSocketServer: Remote endpoint: \(connection.endpoint)")
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            self.networkQueue.async {
                print("WebSocketServer: -------- Connection State Change --------")
                print("WebSocketServer: New state: \(state)")
                
                switch state {
                case .ready:
                    print("WebSocketServer: Connection READY")
                    print("WebSocketServer: Path: \(connection.currentPath?.debugDescription ?? "unknown")")
                    self.connectedClients.append(connection)
                    DispatchQueue.main.async {
                        self.onClientConnected?(connection)
                    }
                case .failed(let error):
                    print("WebSocketServer: Connection FAILED")
                    print("WebSocketServer: Error details: \(error.localizedDescription)")
                    if let path = connection.currentPath {
                        print("WebSocketServer: Final path status: \(path.status)")
                    }
                    self.connectedClients.removeAll(where: { $0 === connection })
                    DispatchQueue.main.async {
                        self.onClientDisconnected?(connection)
                    }
                case .cancelled:
                    print("WebSocketServer: Connection CANCELLED")
                    self.connectedClients.removeAll(where: { $0 === connection })
                    DispatchQueue.main.async {
                        self.onClientDisconnected?(connection)
                    }
                case .preparing:
                    print("WebSocketServer: Connection PREPARING")
                    if let path = connection.currentPath {
                        print("WebSocketServer: Available interfaces: \(path.availableInterfaces)")
                    }
                case .waiting(let error):
                    print("WebSocketServer: Connection WAITING")
                    print("WebSocketServer: Error details: \(error.localizedDescription)")
                default:
                    print("WebSocketServer: Unknown connection state: \(state)")
                }
            }
        }
        
        print("WebSocketServer: Starting connection on queue: \(networkQueue.label)")
        connection.start(queue: networkQueue)
    }
    
    func broadcast(data: Data) {
        networkQueue.async { [weak self] in
            guard let self = self else { return }
            let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
            let context = NWConnection.ContentContext(identifier: "video-frame", metadata: [metadata])
            
            for client in self.connectedClients {
                client.send(
                    content: data,
                    contentContext: context,
                    isComplete: true,
                    completion: .contentProcessed { error in
                        if let error = error {
                            print("WebSocketServer: Failed to send frame: \(error)")
                        }
                    }
                )
            }
        }
    }
    
    deinit {
        networkQueue.async { [weak self] in
            guard let self = self else { return }
            print("WebSocketServer: Shutting down...")
            for client in self.connectedClients {
                client.cancel()
            }
            self.listener?.cancel()
        }
    }
}
