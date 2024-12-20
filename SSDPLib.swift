//
//  UPnPLib.swift
//  UPnPTesting
//
//  Created by Connor Gibbons  on 12/19/24.
//
import Network
import Foundation


final class SSDPClient: @unchecked Sendable {
    private var multicastGroup = "239.255.255.250"
    private var connectionGroup: NWConnectionGroup?
    private var port: UInt16 = 1900
    private let queue = DispatchQueue(label: "com.ssdpclient.queue")
    private var listenTimer: DispatchWorkItem?
    private var searchMessage: String?
    private var handleIncomingMessage: ((Data) -> Void)?
    
    init() {
        handleIncomingMessage = { content in
            guard let message = String(data: content, encoding: .utf8) else {
                print("Could not decode message as string.")
                return
            }
            print(message)
        }
        searchMessage = """
        M-SEARCH * HTTP/1.1\r
        HOST: 239.255.255.250:1900\r
        MAN: "ssdp:discover"\r
        MX: 3\r
        ST: ssdp:all\r
        User-Agent: UPnP/1.0\r
        \r
        
        """
        setupListener()
    }
    
    func setSearchMessage(_ message: String) {
        searchMessage = message
    }
    
    func setIncomingMessageHandler(_ handler: @escaping ((Data) -> Void)) {
        handleIncomingMessage = handler
    }
    
    private func setupListener(customMessage: String = "") {
        let endpoint = NWEndpoint.hostPort(host: .init(multicastGroup), port: .init(integerLiteral: port))
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true
        
        guard let multicastGroup = try? NWMulticastGroup(for: [endpoint]) else {
            print("Could not join multicast group.")
            return
        }
        
        connectionGroup = NWConnectionGroup(with: multicastGroup, using: parameters)
        setupConnectionGroupHandlers(customMessage: customMessage)
    }
    
    private func setupConnectionGroupHandlers(customMessage: String = "") {
        connectionGroup?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .setup:
                print("Setup in process")
            case .waiting(let error):
                print("Waiting: \(error.localizedDescription)")
            case .ready:
                print("Connection group ready")
                self!.sendMSearch()
            case .failed(let error):
                print("Connection group failed: \(error.localizedDescription)")
            case .cancelled:
                print("Connection group cancelled.")
            default:
                print("Bruh \(state)")
            }
        }
        
        connectionGroup?.setReceiveHandler(maximumMessageSize: 65536, rejectOversizedMessages: true) { [weak self] message, content, isComplete in
            guard let content = content else { return }
            self?.handleIncomingMessage!(content)
        }
    }
    
    func stopListening(clearingOld: Bool = false) {
        listenTimer?.cancel()
        listenTimer = nil
        connectionGroup?.cancel()
        connectionGroup = nil
        
        if(!clearingOld) {
            print("SSDP Scan Stopped")
        }
        else {
            print("Old SSDP Connections Cleared")
        }
    }
    
    func startListening(timeout: Double) {
        stopListening(clearingOld: true)
        setupListener()
        connectionGroup?.start(queue: .main)
        let timeoutItem = DispatchWorkItem { [weak self] in
            self?.stopListening()
        }
        listenTimer = timeoutItem
        queue.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
    }
    
    func startListening() {
        if(listenTimer != nil || connectionGroup?.state == .ready) {
            print("Can't start SSDP listening -- already active.")
            return
        }
        stopListening(clearingOld: true)
        setupListener()
        connectionGroup?.start(queue: .main)
    }
    
    private func sendMSearch() {
        guard let data = searchMessage!.data(using: .utf8) else {return}
        connectionGroup?.send(content: data) { error in
            if let error = error {
                print("Error with M-SEARCH: \(error.localizedDescription)")
            }
            else {
                print("Sent M-SEARCH!")
            }
        }
    }
    
    
    
}
