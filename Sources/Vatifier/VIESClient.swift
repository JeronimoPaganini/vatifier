import Vapor

public struct VIESClient: VatifierClient {
    public enum Environment {
        case production
        case testing
        
        var apiURL: String {
            switch self {
            case .production:
                return "https://ec.europa.eu/taxation_customs/vies/rest-api/ms/%COUNTRY%/vat/%VATNUMBER%"
            case .testing:
                return "https://ec.europa.eu/taxation_customs/vies/rest-api/ms/%COUNTRY%/vat/%VATNUMBER%"
            }
        }
    }
    
    private let client: Client
    private let environment: Environment
    
    init(client: Client, environment: Environment) {
        self.client = client
        self.environment = environment
    }
    
    public func hopped(to eventLoop: EventLoop) -> VatifierClient {
        VIESClient(client: self.client.delegating(to: eventLoop), environment: self.environment)
    }
    
    public func verify(_ vatNumber: String, country: Country) -> EventLoopFuture<VATVerificationResponse> {
        guard country != .invalid else {
            return client.eventLoop.future(error: VIESError.invalidInput)
        }
        
        let apiURL = self.environment.apiURL
            .replacingOccurrences(of: "%COUNTRY%", with: country.rawValue)
            .replacingOccurrences(of: "%VATNUMBER%", with: vatNumber)
        
        let headers = HTTPHeaders([
            ("Content-Type", "application/json"),
            ("Cache-Control", "no-cache")
        ])
        
        let request = ClientRequest(method: .GET, url: URI(string: apiURL), headers: headers)
        
        return client.send(request)
            .flatMap { response in
                guard let buffer = response.body else {
                    return self.client.eventLoop.future(error: VIESError.failedToParseResponse)
                }
                
                do {
                    let result = try JSONDecoder().decode(VATVerificationResponse.self, from: buffer)
                    
                    var address: String? = nil
                    var name: String? = nil
                    
                    if result.name != "---" {
                        name = result.name
                    }
                    
                    if result.address != "---" {
                        address = result.address
                    }
                    
                    return self.client.eventLoop.future(VATVerificationResponse(isValid: result.isValid, name: name, address: address))
                } catch {
                    return self.client.eventLoop.future(error: error)
                }
        }
    }
}
