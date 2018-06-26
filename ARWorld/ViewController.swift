//
//  ViewController.swift
//  ARWorld
//
//  Created by Costantino Pistagna on 09/06/2018.
//  Copyright © 2018 https://www.sofapps.it All rights reserved.
//

import UIKit
import SceneKit
import ARKit

struct SANodeAnchor {
    var date:Date
    var node:SCNNode
    var anchor:ARAnchor
}

struct Card {
    var url:URL
    var name:String
    var width:CGFloat
}

extension URLSession {
    func synchronousDataTask(with url: URL) -> (Data?, URLResponse?, Error?) {
        var data: Data?
        var response: URLResponse?
        var error: Error?
        
        let semaphore = DispatchSemaphore(value: 0)
        
        let dataTask = self.dataTask(with: url) {
            data = $0
            response = $1
            error = $2
            
            semaphore.signal()
        }
        dataTask.resume()
        
        _ = semaphore.wait(timeout: .distantFuture)
        
        return (data, response, error)
    }
}

class ViewController: UIViewController, ARSCNViewDelegate {
    private var lastUpdate = [String:SANodeAnchor]()
    private var scheduledTimer:Timer?
    private var sceneSize = UIScreen.main.bounds.size
    
    @IBOutlet var sceneView: ARSCNView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        
        sceneView.showsStatistics = true
        sceneView.autoenablesDefaultLighting = true
        sceneView.automaticallyUpdatesLighting = true
    }
    
    func resetTrackingConfiguration() {
        self.createDataset { [weak self] (referenceImages, error) in
            if let error = error {
                print("oops!, something happened on the way to heaven...", error)
            }
            else if let referenceImages = referenceImages {
                var configuration:ARConfiguration!

                if #available(iOS 12.0, *) {
                    configuration = ARImageTrackingConfiguration()
                    (configuration as! ARImageTrackingConfiguration).trackingImages =  Set(referenceImages.map { $0 }) 
                    (configuration as! ARImageTrackingConfiguration).maximumNumberOfTrackedImages = referenceImages.count
                } else {
                    configuration = ARWorldTrackingConfiguration()
                    (configuration as! ARWorldTrackingConfiguration).detectionImages = Set(referenceImages.map { $0 })
                }

                let options: ARSession.RunOptions = [.resetTracking, .removeExistingAnchors]
                self?.sceneView.session.run(configuration, options: options)
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        resetTrackingConfiguration()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if #available(iOS 12.0, *) {
            
        }
        else {
            if let scheduledTimer = scheduledTimer {
                scheduledTimer.invalidate()
            }
            scheduledTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [unowned self] (timer) in
                for (_, nodeStruct) in self.lastUpdate {
                    if Date().timeIntervalSinceNow - nodeStruct.date.timeIntervalSinceNow > 3 {
                        nodeStruct.node.removeFromParentNode()
                        self.sceneView.session.remove(anchor: nodeStruct.anchor)
                    }
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    // MARK: - ARSCNViewDelegate
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        if let identifier = node.name {
            let aStruct = SANodeAnchor(date: Date(), node: node, anchor: anchor)
            lastUpdate[identifier] = aStruct
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        if let imageAnchor = anchor as? ARImageAnchor {
            let node = SCNNode()
            node.name = anchor.identifier.description
            var labelNode:SCNNode?
            
            switch imageAnchor.referenceImage.name {
            case "card1":
                labelNode = self.addLabel(text: "Hi, Costantino!\nYour loyalties points are 2032.", anchor: imageAnchor)
            case "card2":
                labelNode = self.addLabel(text: "Last tweet from Costantino:\n#WWDC18 #ARKit2 rocks!", anchor: imageAnchor)
            default:
                break
            }
            
            return labelNode
        }
        return nil
    }
    
    func addLabel(text: String, anchor: ARImageAnchor) -> SCNNode {
        let plane = SCNPlane(width: anchor.referenceImage.physicalSize.width,
                             height: anchor.referenceImage.physicalSize.height)
        
        let planeNode = SCNNode(geometry: plane)
        planeNode.eulerAngles.x = -.pi / 2

        let skScene = SKScene(size: sceneSize)
        
        skScene.backgroundColor = UIColor(white: 0.0, alpha: 0.0)

        
        let substrings: [String] = text.components(separatedBy: "\n")
        for aSubstring in substrings {
            let lbl = SKLabelNode(text: aSubstring)
            lbl.fontSize = 20
            lbl.numberOfLines = 1
            lbl.fontColor = UIColor.white.withAlphaComponent(0.85)
            lbl.fontName = "Helvetica-Bold"
            let y = CGFloat(substrings.index(of: aSubstring)! + 1) * lbl.fontSize
            lbl.position = CGPoint(x: 20, y: y)
            lbl.horizontalAlignmentMode = .left
            lbl.yScale *= -1
            skScene.addChild(lbl)
        }
        
        let material = SCNMaterial()
        material.isDoubleSided = false
        material.diffuse.contents = skScene
        plane.materials = [material]

        return planeNode
    }
    
    //MARK: Networking stuff
    
    func loadRemotedataset(fromURL: URL, _ completion: @escaping ([Card]?, Error?)->Void) {
        URLSession.shared.dataTask(with: fromURL) { (data, response, error) in
            if let error = error {
                DispatchQueue.main.async {
                    completion(nil, error)
                }
            }
            else if let data = data {
                var retArray = [Card]()
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [[String:Any]] {
                        for aRow in json {
                            if let aString = aRow["imageURL"] as? String,
                                let anURL = URL(string: aString),
                                let aName = aRow["name"] as? String,
                                let width = aRow["width"] as? CGFloat
                            {
                                retArray.append(Card(url: anURL, name: aName, width: width))
                            }
                        }
                        DispatchQueue.main.async {
                            completion(retArray, nil)
                        }
                    }
                    else {
                        throw NSError(domain: "JSON parse error", code: -1, userInfo: nil)
                    }
                }
                catch {
                    DispatchQueue.main.async {
                        completion(nil, error)
                    }
                }
            }
            }.resume()
    }
    
    func createDataset(_ completion: @escaping ([ARReferenceImage]?, Error?) -> Void) {
        self.loadRemotedataset(fromURL: URL(string: "https://www.sofapps.it/sampleDataset.json")!) { (response, error) in
            if let error = error {
                print("something happened in the way to heaven...", error)
                completion(nil, error)
            }
            else if let response = response {
                var retArray = [ARReferenceImage]()
                for aCard in response {
                    let response = URLSession.shared.synchronousDataTask(with: aCard.url)
                    if let error = response.2 {
                        print("something happened in the way to heaven...", error)
                    }
                    else if let data = response.0, let anImage = UIImage(data: data) {
                        var orientation = CGImagePropertyOrientation.up
                        switch anImage.imageOrientation {
                        case .up:
                            orientation = .up
                        case .down:
                            orientation = .down
                        case .left:
                            orientation = .left
                        case .right:
                            orientation = .right
                        default:
                            orientation = .up
                        }
                        if let cgImage = anImage.cgImage {
                            let aReferenceImage = ARReferenceImage.init(cgImage, orientation: orientation, physicalWidth: aCard.width)
                            aReferenceImage.name = aCard.name
                            retArray.append(aReferenceImage)
                        }
                    }
                }
                completion(retArray, nil)
            }
        }
    }
}
