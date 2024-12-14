import Foundation
import Network

class WebSocketClient {
    private var connection: NWConnection?
    var onConnected: (() -> Void)?
    var onFrameReceived: ((Data) -> Void)?
    private let serverHost = "localhost" // Change this to your Mac's IP address
    private let serverPort = 8080
    
    func connect() {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(serverHost),
            port: NWEndpoint.Port(integerLiteral: UInt16(serverPort))
        )
        
        let parameters = NWParameters(tls: nil)
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        
        connection = NWConnection(to: endpoint, using: parameters)
        
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Connected to server")
                self?.onConnected?()
                self?.receiveNextMessage()
            case .failed(let error):
                print("Connection failed: \(error)")
                self?.reconnect()
            case .waiting(let error):
                print("Connection waiting: \(error)")
            default:
                break
            }
        }
        
        connection?.start(queue: .main)
    }
    
    private func reconnect() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.connect()
        }
    }
    
    private func receiveNextMessage() {
        connection?.receiveMessage { [weak self] content, context, isComplete, error in
            if let error = error {
                print("Receive error: \(error)")
                return
            }
            
            if let content = content,
               let metadata = context?.protocolMetadata.first as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .binary {
                self?.onFrameReceived?(content)
            }
            
            self?.receiveNextMessage()
        }
    }
} 