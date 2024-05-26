//
//  ContentView.swift
//  Bird
//
//  Created by Llamalaptop on 3/22/24.
//

import SwiftUI
import ARKit
import OSCKit

class OSCClientManager {
    var oscClient: OSCClient
    var host: String
    var port: UInt16
    
    init() {
        oscClient = OSCClient()
        // Set default IP and port
        host = "10.0.0.57"
        port = 7175
    }
    
    func updateConfiguration(host: String, port: Int) {
        self.host = host
        self.port = UInt16(port)
    }
    
    func sendMessage(address: String, value: Float) {
        let message = OSCMessage(address, values: [value])
        do {
            try oscClient.send(message, to: host, port: port)
        } catch {
            print("Failed to send message: \(error)")
        }
    }
}

struct ContentView: View {
    var body: some View {
        ARViewContainer().edgesIgnoringSafeArea(.all)
    }
}

struct ARViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView()
        arView.session.delegate = context.coordinator
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        let arSession = ARSession()
        var textView = UITextView()
        let oscClientManager = OSCClientManager()
        
        override init() {
            super.init()
            setupARSession()
            setupTextView()
        }
        
        func setupARSession() {
            guard ARFaceTrackingConfiguration.isSupported else { return }
            let configuration = ARFaceTrackingConfiguration()
            arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            arSession.delegate = self
        }
        
        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            for anchor in anchors {
                guard let faceAnchor = anchor as? ARFaceAnchor else { continue }
                
                DispatchQueue.main.async {
                    self.updateTextView(with: faceAnchor.blendShapes)
                    self.sendOSCMessage(with: faceAnchor.blendShapes)
                }
            }
        }
        
        func setupTextView() {
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    self.textView = UITextView(frame: CGRect(x: 20, y: 50, width: window.frame.width - 40, height: window.frame.height - 20))
                    self.textView.backgroundColor = .darkGray
                    self.textView.isEditable = false
                    window.addSubview(self.textView)
                }
            }
        }
        
        func updateTextView(with blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]) {
            var text = ""
            for (blendShape, value) in blendShapes.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                let roundedValue = round(value.floatValue * 1000) / 1000.0
                text += "\(blendShape.rawValue): \(roundedValue)\n"
            }
            self.textView.text = text
        }
        
        func sendOSCMessage(with blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]) {
            for (blendShape, value) in blendShapes {
                let address = "/blendShape/\(blendShape.rawValue)"
                let floatValue = value.floatValue
                oscClientManager.sendMessage(address: address, value: floatValue)
            }
        }
    }
}
