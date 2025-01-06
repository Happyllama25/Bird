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
        // Retrieve saved IP and port from UserDefaults or set defaults
        host = UserDefaults.standard.string(forKey: "OSC_Host") ?? "10.0.0.93"
        port = UInt16(UserDefaults.standard.integer(forKey: "OSC_Port"))
        if port == 0 { port = 7175 } // Default port if not saved
    }
    
    func updateConfiguration(host: String, port: Int) {
        self.host = host
        self.port = UInt16(port)
        // Save to UserDefaults
        UserDefaults.standard.set(host, forKey: "OSC_Host")
        UserDefaults.standard.set(port, forKey: "OSC_Port")
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
    @State private var showConfigScreen = true // Show config screen on startup
    
    var body: some View {
        if showConfigScreen {
            ConfigView(showConfigScreen: $showConfigScreen)
        } else {
            ARViewContainer().edgesIgnoringSafeArea(.all)
            .onAppear {
                // Keep the screen awake while the app is active
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                // Allow the screen to sleep when the app is no longer active
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }
}

struct ConfigView: View {
    @Binding var showConfigScreen: Bool
    @State private var ipAddress: String = ""
    @State private var port: String = ""
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("OSC Configuration")
                .font(.largeTitle)
            
            TextField("IP Address", text: $ipAddress)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.numbersAndPunctuation)
            
            TextField("Port", text: $port)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.numberPad)
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            }
            
            Button("Save and Start") {
                guard validateInput() else { return }
                let oscClientManager = OSCClientManager()
                oscClientManager.updateConfiguration(host: ipAddress, port: Int(port) ?? 7175)
                showConfigScreen = false
            }
            .buttonStyle(DefaultButtonStyle())
        }
        .padding()
        .onAppear {
            // Preload saved settings
            let savedHost = UserDefaults.standard.string(forKey: "OSC_Host") ?? "10.0.0.93"
            let savedPort = UserDefaults.standard.integer(forKey: "OSC_Port")
            ipAddress = savedHost
            port = savedPort == 0 ? "7175" : "\(savedPort)"
        }
    }
    
    func validateInput() -> Bool {
        guard !ipAddress.isEmpty else {
            errorMessage = "IP Address cannot be empty."
            return false
        }
        guard let portNumber = Int(port), portNumber > 0 && portNumber <= 65535 else {
            errorMessage = "Port must be a valid number between 1 and 65535."
            return false
        }
        errorMessage = nil
        return true
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
                    self.updateTextView(with: faceAnchor.blendShapes, faceAnchor.transform)
                    self.sendOSCMessage(with: faceAnchor.blendShapes, faceAnchor.transform)
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
        
        func updateTextView(with blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber], _ transform: simd_float4x4) {
            var text = ""
            
            // Display blend shapes
            for (blendShape, value) in blendShapes.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                let roundedValue = round(value.floatValue * 1000) / 1000.0
                text += "\(blendShape.rawValue): \(roundedValue)\n"
            }
            
            // Display face orientation
            let orientation = extractFaceOrientation(transform)
            text += "\nFace Orientation:\n"
            text += "Pitch: \(orientation.pitch)\n"
            text += "Yaw: \(orientation.yaw)\n"
            text += "Roll: \(orientation.roll)\n"
            
            self.textView.text = text
        }
        
        func sendOSCMessage(with blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber], _ transform: simd_float4x4) {
            for (blendShape, value) in blendShapes {
                let address = "/blendShape/\(blendShape.rawValue)"
                let floatValue = value.floatValue
                oscClientManager.sendMessage(address: address, value: floatValue)
            }
            
            // Send orientation as OSC messages
            let orientation = extractFaceOrientation(transform)
            oscClientManager.sendMessage(address: "/face/orientation/pitch", value: orientation.pitch)
            oscClientManager.sendMessage(address: "/face/orientation/yaw", value: orientation.yaw)
            oscClientManager.sendMessage(address: "/face/orientation/roll", value: orientation.roll)
        }

        func extractFaceOrientation(_ transform: simd_float4x4) -> (pitch: Float, yaw: Float, roll: Float) {
            let pitch = atan2(-transform.columns.2.y, transform.columns.2.z) // X-axis rotation
            let yaw = atan2(transform.columns.2.x, sqrt(transform.columns.2.y * transform.columns.2.y + transform.columns.2.z * transform.columns.2.z)) // Y-axis rotation
            let roll = atan2(transform.columns.0.y, transform.columns.0.x) // Z-axis rotation
            
            return (pitch, yaw, roll)
        }

    }
}
