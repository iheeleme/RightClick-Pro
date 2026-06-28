import Foundation

@objc public protocol RightClickProActionRunnerXPCProtocol {
    @objc(performActionWithRequestData:reply:)
    func performAction(requestData: NSData, reply: @escaping (NSData?, NSError?) -> Void)

    @objc(performMaintenanceWithRequestData:reply:)
    func performMaintenance(requestData: NSData, reply: @escaping (NSData?, NSError?) -> Void)
}

public final class RightClickProActionRunnerXPCAdapter: NSObject, RightClickProActionRunnerXPCProtocol {
    private let runner: ActionRunner
    private let maintenanceService: SystemMaintenanceService
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(runner: ActionRunner, maintenanceService: SystemMaintenanceService = SystemMaintenanceService()) {
        self.runner = runner
        self.maintenanceService = maintenanceService
    }

    public func performAction(requestData: NSData, reply: @escaping (NSData?, NSError?) -> Void) {
        do {
            let request = try decoder.decode(ActionRequest.self, from: requestData as Data)
            let result = runner.run(request)
            let data = try encoder.encode(result)
            reply(data as NSData, nil)
        } catch {
            reply(nil, error as NSError)
        }
    }

    public func performMaintenance(requestData: NSData, reply: @escaping (NSData?, NSError?) -> Void) {
        do {
            let request = try decoder.decode(SystemMaintenanceRequest.self, from: requestData as Data)
            let result = maintenanceService.perform(request)
            let data = try encoder.encode(result)
            reply(data as NSData, nil)
        } catch {
            reply(nil, error as NSError)
        }
    }
}

public enum RightClickProXPCClientError: Error, LocalizedError {
    case unavailable
    case missingResponse

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "ActionRunner XPC 服务不可用"
        case .missingResponse:
            return "ActionRunner 没有返回结果"
        }
    }
}

public final class RightClickProActionRunnerXPCClient {
    private let serviceName: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(serviceName: String = RightClickProConstants.defaultXPCServiceName) {
        self.serviceName = serviceName
    }

    public func perform(_ request: ActionRequest, completion: @escaping (Result<ActionResult, Error>) -> Void) {
        do {
            let requestData = try encoder.encode(request)
            let connection = NSXPCConnection(serviceName: serviceName)
            connection.remoteObjectInterface = NSXPCInterface(with: RightClickProActionRunnerXPCProtocol.self)
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                connection.invalidate()
                completion(.failure(error))
            }) as? RightClickProActionRunnerXPCProtocol else {
                connection.invalidate()
                completion(.failure(RightClickProXPCClientError.unavailable))
                return
            }

            proxy.performAction(requestData: requestData as NSData) { responseData, error in
                connection.invalidate()

                if let error {
                    completion(.failure(error))
                    return
                }

                guard let responseData else {
                    completion(.failure(RightClickProXPCClientError.missingResponse))
                    return
                }

                do {
                    let result = try self.decoder.decode(ActionResult.self, from: responseData as Data)
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    public func performMaintenance(
        _ request: SystemMaintenanceRequest,
        completion: @escaping (Result<SystemMaintenanceResult, Error>) -> Void
    ) {
        do {
            let requestData = try encoder.encode(request)
            let connection = NSXPCConnection(serviceName: serviceName)
            connection.remoteObjectInterface = NSXPCInterface(with: RightClickProActionRunnerXPCProtocol.self)
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                connection.invalidate()
                completion(.failure(error))
            }) as? RightClickProActionRunnerXPCProtocol else {
                connection.invalidate()
                completion(.failure(RightClickProXPCClientError.unavailable))
                return
            }

            proxy.performMaintenance(requestData: requestData as NSData) { responseData, error in
                connection.invalidate()

                if let error {
                    completion(.failure(error))
                    return
                }

                guard let responseData else {
                    completion(.failure(RightClickProXPCClientError.missingResponse))
                    return
                }

                do {
                    let result = try self.decoder.decode(SystemMaintenanceResult.self, from: responseData as Data)
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
}
