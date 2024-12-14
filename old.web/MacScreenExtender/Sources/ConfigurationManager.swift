import Foundation

class ConfigurationManager {
    static let shared = ConfigurationManager()
    
    private let defaults = UserDefaults.standard
    private let configKey = "screenExtenderConfig"
    
    struct Configuration: Codable {
        var resolution: Resolution
        var refreshRate: Int
        var pairedDevices: [PairedDevice]
        
        struct Resolution: Codable {
            var width: Int
            var height: Int
        }
        
        struct PairedDevice: Codable {
            var id: String
            var name: String
            var lastConnected: Date
        }
    }
    
    private var config: Configuration {
        get {
            if let data = defaults.data(forKey: configKey),
               let config = try? JSONDecoder().decode(Configuration.self, from: data) {
                return config
            }
            return defaultConfiguration()
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: configKey)
            }
        }
    }
    
    private func defaultConfiguration() -> Configuration {
        return Configuration(
            resolution: .init(width: 1920, height: 1080),
            refreshRate: 60,
            pairedDevices: []
        )
    }
    
    func addPairedDevice(id: String, name: String) {
        var currentConfig = config
        let device = Configuration.PairedDevice(
            id: id,
            name: name,
            lastConnected: Date()
        )
        currentConfig.pairedDevices.append(device)
        config = currentConfig
    }
    
    func getPairedDevices() -> [Configuration.PairedDevice] {
        return config.pairedDevices
    }
    
    func getResolution() -> Configuration.Resolution {
        return config.resolution
    }
    
    func setResolution(width: Int, height: Int) {
        var currentConfig = config
        currentConfig.resolution = .init(width: width, height: height)
        config = currentConfig
    }
} 