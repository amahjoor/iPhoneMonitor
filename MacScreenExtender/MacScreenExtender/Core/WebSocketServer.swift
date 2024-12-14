/*
    WebSocketServer.swift
    MacScreenExtender

    Created by Arman Mahjoor on 12/14/24.

    Created by Arman Mahjoor on 12/14/2024

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
        print("WebSocketServer: Setting up listener on port \(port)")
        
        // Create parameters with explicit WebSocket support
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        wsOptions.maximumMessageSize = 1_000_000 // Allow larger messages
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        
        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(port)))
            
            listener?.stateUpdateHandler = { [weak self] state in
                self?.networkQueue.async {
                    switch state {
                    case .ready:
                        print("WebSocketServer: Ready and listening on port \(port)")
                    case .failed(let error):
                        print("WebSocketServer: Failed with error: \(error)")
                    case .setup:
                        print("WebSocketServer: Setting up...")
                    case .waiting(let error):
                        print("WebSocketServer: Waiting... Error: \(error)")
                    case .cancelled:
                        print("WebSocketServer: Cancelled")
                    default:
                        print("WebSocketServer: State changed to \(state)")
                    }
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                print("WebSocketServer: New connection attempt from \(connection.endpoint)")
                self?.networkQueue.async {
                    self?.handleNewConnection(connection)
                }
            }
            
            print("WebSocketServer: Starting listener...")
            listener?.start(queue: networkQueue)
        } catch {
            print("WebSocketServer: Failed to create listener: \(error)")
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        print("WebSocketServer: Handling new connection from \(connection.endpoint)")
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            self.networkQueue.async {
                switch state {
                case .ready:
                    print("WebSocketServer: Client connected successfully")
                    self.connectedClients.append(connection)
                    DispatchQueue.main.async {
                        self.onClientConnected?(connection)
                    }
                case .failed(let error):
                    print("WebSocketServer: Client connection failed: \(error)")
                    self.connectedClients.removeAll(where: { $0 === connection })
                    DispatchQueue.main.async {
                        self.onClientDisconnected?(connection)
                    }
                case .cancelled:
                    print("WebSocketServer: Client connection cancelled")
                    self.connectedClients.removeAll(where: { $0 === connection })
                    DispatchQueue.main.async {
                        self.onClientDisconnected?(connection)
                    }
                case .preparing:
                    print("WebSocketServer: Client connection preparing")
                case .waiting(let error):
                    print("WebSocketServer: Client connection waiting: \(error)")
                default:
                    print("WebSocketServer: Client connection state changed to \(state)")
                }
            }
        }
        
        print("WebSocketServer: Starting client connection...")
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
