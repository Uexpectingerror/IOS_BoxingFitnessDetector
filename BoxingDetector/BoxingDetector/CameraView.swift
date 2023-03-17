//
//  CameraView.swift
//  BoxingDetector
//
//  Created by Orson Wu on 3/1/23.
//

import SwiftUI
import AVFoundation

struct CameraView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    
    let cameraService: CameraSevice
    
    func makeUIViewController(context: Context) -> UIViewController {
        
        cameraService.start() { err in
            if err != nil {
                return
            }
        }
        
        let viewController = UIViewController()
        viewController.view.backgroundColor = .black
        
        //add camera feed layer
        viewController.view.layer.addSublayer(cameraService.previewLayer)
        cameraService.previewLayer.frame = viewController.view.bounds
        
        //left arm
        viewController.view.layer.addSublayer(cameraService.leftArmActionLayer)
        cameraService.leftArmActionLayer.frame = viewController.view.bounds
        cameraService.leftArmActionLayer.strokeColor = UIColor.init(white: 1, alpha: 0.5).cgColor
        cameraService.leftArmActionLayer.fillColor = UIColor.clear.cgColor
        cameraService.leftArmActionLayer.lineWidth = 15
        cameraService.leftArmActionLayer.lineJoin = .round
        
        //right arm
        viewController.view.layer.addSublayer(cameraService.rightArmActionLayer)
        cameraService.rightArmActionLayer.frame = viewController.view.bounds
        cameraService.rightArmActionLayer.strokeColor = UIColor.init(white: 1, alpha: 0.5).cgColor
        cameraService.rightArmActionLayer.fillColor = UIColor.clear.cgColor
        cameraService.rightArmActionLayer.lineWidth = 15
        cameraService.rightArmActionLayer.lineJoin = .round
        
        //left fist
        viewController.view.layer.addSublayer(cameraService.leftFistActionLayer)
        cameraService.leftFistActionLayer.frame = viewController.view.bounds
        cameraService.leftFistActionLayer.strokeColor = UIColor.init(white: 1, alpha: 0.5).cgColor
        cameraService.leftFistActionLayer.fillColor = UIColor.clear.cgColor
        cameraService.leftFistActionLayer.lineWidth = 10
        cameraService.leftFistActionLayer.lineJoin = .round
        
        //right fist
        viewController.view.layer.addSublayer(cameraService.rightFistActionLayer)
        cameraService.rightFistActionLayer.frame = viewController.view.bounds
        cameraService.rightFistActionLayer.strokeColor = UIColor.init(white: 1, alpha: 0.5).cgColor
        cameraService.rightFistActionLayer.fillColor = UIColor.clear.cgColor
        cameraService.rightFistActionLayer.lineWidth = 10
        cameraService.rightFistActionLayer.lineJoin = .round
        
        //add prediction body points
        viewController.view.layer.addSublayer(cameraService.pointsLayer)
        cameraService.pointsLayer.frame = viewController.view.bounds
        cameraService.pointsLayer.strokeColor = UIColor(white: 1, alpha: 0.8).cgColor
        cameraService.pointsLayer.fillColor = UIColor(white: 1, alpha: 0.8).cgColor
        
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }
}
