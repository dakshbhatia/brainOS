import SwiftUI
import SceneKit

public struct BrainAvatarView: View {
    @State private var scene: SCNScene?
    @State private var brainNode: SCNNode?
    
    public init() {}
    
    public var body: some View {
        SceneView(
            scene: createScene(),
            pointOfView: nil,
            options: [.allowsCameraControl, .autoenablesDefaultLighting],
            preferredFramesPerSecond: 60
        )
        .background(Color.clear)
    }
    
    private func createScene() -> SCNScene {
        let scene = SCNScene()
        
        // Create a stylized brain (using a sphere with a custom shader or texture for now)
        let brainGeometry = SCNSphere(radius: 1.0)
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.systemPink.withAlphaComponent(0.8)
        material.emission.contents = NSColor.systemPink.withAlphaComponent(0.2)
        material.specular.contents = NSColor.white
        material.shininess = 0.9
        
        // Add some "neural" texture/bump
        brainGeometry.materials = [material]
        
        let node = SCNNode(geometry: brainGeometry)
        node.position = SCNVector3(0, 0, 0)
        
        // Add a rotating animation
        let rotate = SCNAction.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 10)
        node.runAction(SCNAction.repeatForever(rotate))
        
        scene.rootNode.addChildNode(node)
        
        // Add some ambient light
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = NSColor(white: 0.3, alpha: 1.0)
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
        
        return scene
    }
}
