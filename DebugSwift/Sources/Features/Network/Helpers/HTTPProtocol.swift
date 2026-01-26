//
//  HTTPProtocol.swift
//  DebugSwift
//
//  Created by Matheus Gois on 15/12/23.
//  Copyright © 2023 apple. All rights reserved.
//

import Foundation

// MARK: - Shared Session Manager

/// Manages a shared URLSession to avoid creating new sessions per request
private final class SharedSessionManager: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = SharedSessionManager()

    private var session: URLSession!
    private let lock = NSLock()
    private var protocolHandlers: [Int: WeakProtocolBox] = [:] // taskIdentifier -> protocol

    private class WeakProtocolBox {
        weak var value: CustomHTTPProtocol?
        init(_ value: CustomHTTPProtocol) { self.value = value }
    }

    private override init() {
        super.init()

        // Create configuration without CustomHTTPProtocol to prevent recursion
        let config = URLSessionConfiguration.default
        config.protocolClasses = config.protocolClasses?.filter { $0 != CustomHTTPProtocol.self } ?? []

        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func createTask(with request: URLRequest, for protocolInstance: CustomHTTPProtocol) -> URLSessionDataTask {
        let task = session.dataTask(with: request)
        lock.lock()
        protocolHandlers[task.taskIdentifier] = WeakProtocolBox(protocolInstance)
        lock.unlock()
        return task
    }

    func removeHandler(for taskIdentifier: Int) {
        lock.lock()
        protocolHandlers.removeValue(forKey: taskIdentifier)
        lock.unlock()
    }

    private func getProtocol(for task: URLSessionTask) -> CustomHTTPProtocol? {
        lock.lock()
        let handler = protocolHandlers[task.taskIdentifier]?.value
        lock.unlock()
        return handler
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let proto = getProtocol(for: task) {
            proto.handleRedirection(response: response, newRequest: request, completionHandler: completionHandler)
        } else {
            completionHandler(request)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let proto = getProtocol(for: dataTask) {
            proto.handleResponse(dataTask: dataTask, response: response, completionHandler: completionHandler)
        } else {
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let proto = getProtocol(for: dataTask) {
            proto.handleData(data)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let proto = getProtocol(for: task) {
            proto.handleCompletion(session: session, task: task, error: error)
        }
        removeHandler(for: task.taskIdentifier)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        if let proto = getProtocol(for: task) {
            proto.handleBodyDataSent(
                session: session,
                task: task,
                bytesSent: bytesSent,
                totalBytesSent: totalBytesSent,
                totalBytesExpectedToSend: totalBytesExpectedToSend
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // For session-level challenges, try to find any active protocol to forward
        lock.lock()
        let anyProto = protocolHandlers.values.first?.value
        lock.unlock()

        if let proto = anyProto {
            proto.handleSessionChallenge(session: session, challenge: challenge, completionHandler: completionHandler)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if let proto = getProtocol(for: task) {
            proto.handleTaskChallenge(session: session, task: task, challenge: challenge, completionHandler: completionHandler)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - CustomHTTPProtocol

public final class CustomHTTPProtocol: URLProtocol, @unchecked Sendable {
    private static let requestProperty = "com.custom.http.protocol"

    public final class func clearCache() {
        URLCache.customHttp.removeAllCachedResponses()
    }

    public final class func start() {
        URLProtocol.registerClass(self)
    }

    public final class func stop() {
        URLProtocol.unregisterClass(self)
    }

    private final class func canServeRequest(_ request: URLRequest) -> Bool {
        if let _ = property(forKey: requestProperty, in: request) { return false }

        // Never intercept WebSocket requests - they should be handled by WebSocketMonitor
        if let scheme = request.url?.scheme?.lowercased() {
            if scheme == "ws" || scheme == "wss" {
                return false
            }
        }

        for onlyScheme in DebugSwift.Network.shared.onlySchemes {
            if let scheme = request.url?.scheme?.lowercased(), scheme == onlyScheme.rawValue {
                return true
            }
        }

        return false
    }

    public override final class func canInit(with request: URLRequest) -> Bool {
        canServeRequest(request)
    }

    public override final class func canInit(with task: URLSessionTask) -> Bool {
        guard let request = task.currentRequest else { return false }
        return canServeRequest(request)
    }

    public override final class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    private var dataTask: URLSessionDataTask?
    private var cachePolicy: URLCache.StoragePolicy = .notAllowed
    private var data: Data = .init()
    private var didRetry = false
    private var didReceiveData = false
    private var startTime = Date()
    private var response: HTTPURLResponse?
    private var error: Error?
    private var prevUrl: URL?
    private var prevStartTime: Date?

    private var threadOperator: ThreadOperator?

    // Store reference to original delegate for forwarding
    private weak var originalDelegate: URLSessionDelegate?

    private func use(_ cache: CachedURLResponse) {
        DebugSwift.Network.shared.delegate?.urlSession(
            self,
            didReceive: cache.response
        )
        client?.urlProtocol(
            self,
            didReceive: cache.response,
            cacheStoragePolicy: .allowed
        )

        DebugSwift.Network.shared.delegate?.urlSession(
            self,
            didReceive: cache.data
        )
        client?.urlProtocol(
            self,
            didLoad: cache.data
        )

        DebugSwift.Network.shared.delegate?.didFinishLoading(self)
        client?.urlProtocolDidFinishLoading(self)
    }

    public override func startLoading() {
        guard let newRequest = (request as NSObject).mutableCopy() as? NSMutableURLRequest else {
            fatalError("Can not convert to NSMutableURLRequest")
        }

        URLProtocol.setProperty(true, forKey: CustomHTTPProtocol.requestProperty, in: newRequest)

        // Track request for threshold monitoring
        if let url = request.url {
            NetworkThresholdTracker.shared.trackRequest(url: url)
        }

        if let cache = URLCache.customHttp.validCache(for: request) {
            use(cache)

            Debug.execute {
                if let name = request.url?.lastPathComponent {
                    Debug.print("Use cache for \(name)")
                } else {
                    Debug.print("Use cache")
                }
            }

            return
        }

        Debug.print(request.requestId)
        threadOperator = ThreadOperator()
        startTime = Date()
        prevUrl = request.url
        prevStartTime = startTime

        // Capture the most recent application delegate for forwarding authentication challenges
        originalDelegate = URLSessionDelegateRegistry.shared.getMostRecentDelegate()

        // Use shared session manager to avoid creating new URLSession per request
        dataTask = SharedSessionManager.shared.createTask(with: newRequest as URLRequest, for: self)
        dataTask?.resume()
    }

    public override func stopLoading() {
        if let task = dataTask {
            SharedSessionManager.shared.removeHandler(for: task.taskIdentifier)
            task.cancel()
            dataTask = nil
        }

        Task { @Sendable in
            guard await NetworkHelper.shared.isNetworkEnable else {
                return
            }

            await processNetworkData()
        }
    }

    // MARK: - Handler Methods (called by SharedSessionManager)

    func handleRedirection(
        response: HTTPURLResponse,
        newRequest: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        threadOperator?.execute { [weak self] in
            guard let self else { return }
            Debug.print(#function)

            self.client?.urlProtocol(self, wasRedirectedTo: newRequest, redirectResponse: response)
            self.response = response
            completionHandler(newRequest)
        }
    }

    func handleResponse(
        dataTask: URLSessionDataTask,
        response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        threadOperator?.execute { [weak self] in
            guard let self else { return }
            Debug.print(#function)

            if let response = response as? HTTPURLResponse, let request = dataTask.originalRequest {
                self.cachePolicy = CacheHelper.cacheStoragePolicy(for: request, and: response)
            }

            DebugSwift.Network.shared.delegate?.urlSession(
                self,
                didReceive: response
            )
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: self.cachePolicy)
            self.response = response as? HTTPURLResponse
            completionHandler(.allow)
        }
    }

    func handleData(_ data: Data) {
        threadOperator?.execute { [weak self] in
            guard let self else { return }
            Debug.print(#function)

            var hasAddedData = false
            if self.cachePolicy == .allowed {
                self.data.append(data)
                hasAddedData = true
            }

            DebugSwift.Network.shared.delegate?.urlSession(
                self,
                didReceive: data
            )
            self.client?.urlProtocol(self, didLoad: data)
            self.didReceiveData = true
            if self.prevUrl == self.response?.url, self.prevStartTime == self.startTime {
                if !hasAddedData { self.data.append(data) }
            } else {
                self.data = data
            }
        }
    }

    func handleCompletion(session: URLSession, task: URLSessionTask, error: Error?) {
        threadOperator?.execute { [weak self] in
            guard let self else { return }
            if let error {
                self.error = error
                if self.canRetry(error: error as NSError), let request = task.originalRequest {
                    self.didRetry = true
                    self.dataTask = SharedSessionManager.shared.createTask(with: request, for: self)
                    self.dataTask?.resume()
                    return
                }
                DebugSwift.Network.shared.delegate?.urlSession(
                    self,
                    didFailWithError: error
                )
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }

            DebugSwift.Network.shared.delegate?.didFinishLoading(self)
            self.client?.urlProtocolDidFinishLoading(self)

            if self.cachePolicy == .allowed {
                URLCache.customHttp.storeIfNeeded(for: task, data: self.data)
            }
        }
    }

    func handleBodyDataSent(
        session: URLSession,
        task: URLSessionTask,
        bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        threadOperator?.execute { [weak self] in
            guard let self else { return }
            Debug.print(#function)

            DebugSwift.Network.shared.delegate?.urlSession(
                self,
                session,
                task: task,
                didSendBodyData: bytesSent,
                totalBytesSent: totalBytesSent,
                totalBytesExpectedToSend: totalBytesExpectedToSend
            )
        }
    }

    func handleSessionChallenge(
        session: URLSession,
        challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        threadOperator?.execute { [weak self] in
            guard let self else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            Debug.print(#function)

            // Forward to original delegate if available and implements the method
            if let originalDelegate = self.originalDelegate,
               originalDelegate.responds(to: #selector(URLSessionDelegate.urlSession(_:didReceive:completionHandler:))) {
                originalDelegate.urlSession?(session, didReceive: challenge, completionHandler: completionHandler)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }

    func handleTaskChallenge(
        session: URLSession,
        task: URLSessionTask,
        challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        threadOperator?.execute { [weak self] in
            guard let self else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            Debug.print(#function)

            // Forward to original delegate if available and implements the method
            if let originalDelegate = self.originalDelegate as? URLSessionTaskDelegate,
               originalDelegate.responds(to: #selector(URLSessionTaskDelegate.urlSession(_:task:didReceive:completionHandler:))) {
                originalDelegate.urlSession?(session, task: task, didReceive: challenge, completionHandler: completionHandler)
            } else {
                // Fallback to session-level challenge if task-level not implemented
                self.handleSessionChallenge(session: session, challenge: challenge, completionHandler: completionHandler)
            }
        }
    }
    
    @MainActor
    private func processNetworkData() async {
        var model = HttpModel()
        model.url = request.url
        model.method = request.httpMethod
        model.mineType = response?.mimeType

        if let requestBody = request.httpBody {
            model.requestData = requestBody
        }

        if let requestBodyStream = request.httpBodyStream {
            model.requestData = requestBodyStream.toData()
        }

        if let httpResponse = response {
            model.statusCode = "\(httpResponse.statusCode)"
        }

        model.responseData = data
        model.size = data.formattedSize()
        model.isImage = (response?.mimeType?.contains("image")) ?? false

        // Time
        let startTimeDouble = startTime.timeIntervalSince1970
        let endTimeDouble = Date().timeIntervalSince1970
        let durationDouble = abs(endTimeDouble - startTimeDouble)
        let formattedDuration = String(format: "%.4f", durationDouble)

        model.startTime = "\(startTime.formatted())"
        model.endTime = "\(Date().formatted())"
        model.totalDuration = "\(formattedDuration) (s)"

        model.errorDescription = error?.localizedDescription ?? ""
        model.errorLocalizedDescription = error?.localizedDescription ?? ""
        model.requestHeaderFields = request.allHTTPHeaderFields

        if let response {
            model.responseHeaderFields = response.allHeaderFields.convertKeysToString()
            model.responseHeaderFields?.updateValue(getCachePolicy(value: request.cachePolicy.rawValue), forKey: "Cache-Policy")
        }

        if let responseDate = model.endTime {
            model.responseHeaderFields?.updateValue(responseDate, forKey: "Response-Date")
        }

        if response?.mimeType == nil {
            model.isImage = false
        }

        if let urlString = model.url?.absoluteString, urlString.count > 4 {
            let str = String(urlString.suffix(4))
            if ["png", "PNG", "jpg", "JPG", "gif", "GIF"].contains(str) {
                model.isImage = true
            }
        }

        if let urlString = model.url?.absoluteString, urlString.count > 5 {
            let str = String(urlString.suffix(5))
            if ["jpeg", "JPEG"].contains(str) {
                model.isImage = true
            }
        }

        model.requestId = request.requestId
        model = ErrorHelper.handle(error, model: model)
        if HttpDatasource.shared.addHttpRequest(model) {
            NotificationCenter.default.post(
                name: NSNotification.Name("reloadHttp_DebugSwift"),
                object: model.isSuccess
            )
        }
    }

    // MARK: - Private Helper Methods

    private func canRetry(error: NSError) -> Bool {
        guard error.code == Int(CFNetworkErrors.cfurlErrorNetworkConnectionLost.rawValue),
              !didRetry,
              !didReceiveData
        else {
            return false
        }

        Debug.print("Retry download...")
        return true
    }

    private func getCachePolicy(value: UInt?) -> String {
        switch value {
        case 0:
            return "useProtocolCachePolicy"
        case 1:
            return "reloadIgnoringLocalCacheData"
        case 4:
            return "reloadIgnoringLocalAndRemoteCacheData"
        case 3:
            return "returnCacheDataDontLoad"
        case 2:
            return "returnCacheDataElseLoad"
        case 5:
            return "reloadRevalidatingCacheData"
        default:
            return "reloadIgnoringCacheData"
        }
    }
}
