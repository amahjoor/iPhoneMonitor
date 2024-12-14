import Foundation
import Network

class WebSocketServer {
    private var listener: NWListener?
    private var connectedClients: [NWConnection] = []
    var onClientConnected: ((NWConnection) -> Void)?
    
    init(port: Int) {
        setupListener(port: port)
    }
    
    private func setupListener(port: Int) {
        let parameters = NWParameters(tls: nil)
        parameters.allowLocalEndpointReuse = true
        
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        
        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(port)))
            
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("WebSocket server ready on port \(port)")
                case .failed(let error):
                    print("WebSocket server failed: \(error)")
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener?.start(queue: .main)
        } catch {
            print("Failed to create WebSocket server: \(error)")
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.connectedClients.append(connection)
            case .failed, .cancelled:
                self?.connectedClients.removeAll(where: { $0 === connection })
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    func broadcast(data: Data) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "video-frame", metadata: [metadata])
        
        for client in connectedClients {
            client.send(
                content: data,
                contentContext: context,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error = error {
                        print("Failed to send frame: \(error)")
                    }
                }
            )
        }
    }
} 