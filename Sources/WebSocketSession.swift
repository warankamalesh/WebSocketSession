//
//  WebSocketSession.swift
//  WebSocketSession
//
//  Created by Kamaleshwaran Selvaraj on 06/08/21.
//

import Foundation

public protocol WebSocketSessionProtocol: AnyObject {
    func updatedWebsocketEvent(_ event: WebSocketSession.SocketEvent)
}

@available(iOS 13.0, *)
public class WebSocketSession: NSObject {
    
    private let socketURL: URL
    private var session: URLSession?
    private let pingPongTime: TimeInterval
    private let receiveMessageTime: TimeInterval
    private var webSocketTask: URLSessionWebSocketTask? = nil
    
    private var sheduleTimer: Timer? = nil
    private var readMessageSheduleTimer: Timer? = nil
    
    public typealias Delegate = WebSocketSessionProtocol
    public typealias CloseCode = URLSessionWebSocketTask.CloseCode
    public weak var delegate: Delegate? = nil
    
    
    public enum SocketEvent {
        case connected
        case pingRequested
        case receive(message: URLSessionWebSocketTask.Message)
        case failure(FailureReason)
        case disconnected(URLSessionWebSocketTask.CloseCode)
    }
    
    public enum FailureReason: Error {
        case invalidSocketUrl
        case pingPongError(Error)
        case sendMessageError(Error)
        case readMessageError(Error)
        case failure(Error)
    }
    
    
    public init(socketUrl: URL, pingPongTime durationInSeconds: TimeInterval = 10.0, receiveMessageTime: TimeInterval = 1.0) {
        
        self.socketURL = socketUrl
        self.pingPongTime = durationInSeconds
        self.receiveMessageTime = receiveMessageTime
        super.init()
        self.createSession()
    }
    
    public func connect() {
        
        self.establishSocketConnection()
        
        if nil == sheduleTimer {
            sheduleTimer = Timer.scheduledTimer(timeInterval: pingPongTime, target: self, selector: #selector(pingPongConnectionShedulerEvent), userInfo: nil, repeats: true)
        }
        
        if nil == readMessageSheduleTimer {
            readMessageSheduleTimer =  Timer.scheduledTimer(timeInterval: receiveMessageTime, target: self, selector: #selector(receiveMessgaeShedulerEvent), userInfo: nil, repeats: true)
        }
    }
    
    public func disConnect(with code: CloseCode = .normalClosure, reason: Data? = nil) {
        sheduleTimer?.invalidate()
        sheduleTimer = nil
        readMessageSheduleTimer?.invalidate()
        readMessageSheduleTimer = nil
        webSocketTask?.cancel(with: code, reason: reason)
        webSocketTask = nil
    }
    
    public func send(message: String) {
        self.sendSocket(message: .string(message))
    }
    
    public func send(data: Data) {
        self.sendSocket(message: .data(data))
    }
    
}


extension WebSocketSession {
    
    private func sendSocket(message: URLSessionWebSocketTask.Message) {
        webSocketTask?.send(message, completionHandler: { [weak self] error in
            guard  let self = self, let err = error else { return }
            let reason = FailureReason.sendMessageError(err)
            self.delegate?.updatedWebsocketEvent(.failure(reason))
        })
    }
    
    private func createSession() {
        let sessionConfig = URLSessionConfiguration.default
        session =  URLSession(configuration: sessionConfig, delegate: self, delegateQueue: nil)
    }
    
    private func establishSocketConnection() {
        guard socketURL.absoluteString.hasPrefix("ws://") || socketURL.absoluteString.hasPrefix("wss://") else {
            delegate?.updatedWebsocketEvent(.failure(.invalidSocketUrl))
            return
        }
        webSocketTask?.cancel()
        webSocketTask = session?.webSocketTask(with: socketURL)
        webSocketTask?.resume()
    }
    
    @objc func pingPongConnectionShedulerEvent() {
        webSocketTask?.sendPing(pongReceiveHandler: { [weak self] error in
            guard  let self = self, let err = error else { return }
            let reason = FailureReason.pingPongError(err)
            self.delegate?.updatedWebsocketEvent(.failure(reason))
        })
        
    }
    
    @objc func receiveMessgaeShedulerEvent() {
        webSocketTask?.receive(completionHandler: { [weak self] result in
            guard  let self = self else { return }
            switch result {
            case .failure(let error):
                let reason = FailureReason.readMessageError(error)
                self.delegate?.updatedWebsocketEvent(.failure(reason))
            case .success(let message):
                self.delegate?.updatedWebsocketEvent(.receive(message: message))
            }
        })
    }
    
}

extension WebSocketSession: URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        self.delegate?.updatedWebsocketEvent(.connected)
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        self.delegate?.updatedWebsocketEvent(.disconnected(closeCode))
    }
}
