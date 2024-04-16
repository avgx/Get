import Foundation
import Pulse
import Logging

public func defaultDataStreamValidate(_ response: URLResponse) -> URLSession.ResponseDisposition {
    if((response as! HTTPURLResponse).statusCode != 200){
        return .cancel
    }
    
    return .allow
}

public class DataStreamDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    private let logger: NetworkLogger?
    
    var received: (_ data: Data) -> ()
    var validate: (_ response: URLResponse) -> URLSession.ResponseDisposition
    
    public init(loggerConfiguration: HttpClient5.LoggerConfiguration, 
        received: @escaping (_ data: Data) -> (),
        validate: @escaping (_ response: URLResponse) -> URLSession.ResponseDisposition = defaultDataStreamValidate
    ) {
        self.logger = loggerConfiguration.pulse
        self.received = received
        self.validate = validate
    }
    
    public func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        logger?.logTaskCreated(task)
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        assert(task is URLSessionDataTask)
        logger?.logTask(task, didCompleteWithError: error)
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        logger?.logTask(task, didFinishCollecting: metrics)
    }
    
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            return (.cancelAuthenticationChallenge, nil)
        }
        
        return (.useCredential, URLCredential(trust: serverTrust))
    }
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        return self.validate(response)
    }

    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Callback once all of the data has been received
//        logger?.logDataTask(dataTask, didReceive: data)
        self.received(data)
    }

}
