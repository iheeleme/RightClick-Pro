import Foundation

@objc public protocol RightToolActionRunnerXPCProtocol {
    @objc(performActionWithRequestData:reply:)
    func performAction(requestData: NSData, reply: @escaping (NSData?, NSError?) -> Void)
}

public final class RightToolActionRunnerXPCAdapter: NSObject, RightToolActionRunnerXPCProtocol {
    private let runner: ActionRunner
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(runner: ActionRunner) {
        self.runner = runner
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
}

public enum RightToolXPCClientError: Error, LocalizedError {
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

public final class RightToolActionRunnerXPCClient {
    private let serviceName: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(serviceName: String = RightToolConstants.defaultXPCServiceName) {
        self.serviceName = serviceName
    }

    public func perform(_ request: ActionRequest, completion: @escaping (Result<ActionResult, Error>) -> Void) {
        do {
            let requestData = try encoder.encode(request)
            let connection = NSXPCConnection(serviceName: serviceName)
            connection.remoteObjectInterface = NSXPCInterface(with: RightToolActionRunnerXPCProtocol.self)
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                connection.invalidate()
                completion(.failure(error))
            }) as? RightToolActionRunnerXPCProtocol else {
                connection.invalidate()
                completion(.failure(RightToolXPCClientError.unavailable))
                return
            }

            proxy.performAction(requestData: requestData as NSData) { responseData, error in
                connection.invalidate()

                if let error {
                    completion(.failure(error))
                    return
                }

                guard let responseData else {
                    completion(.failure(RightToolXPCClientError.missingResponse))
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
}
