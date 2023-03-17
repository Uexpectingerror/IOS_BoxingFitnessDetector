//
//  CameraService.swift
//  BoxingDetector
//
//  Created by Orson Wu on 3/1/23.
//
import UIKit
import Foundation
import AVFoundation

class CameraSevice: NSObject, ObservableObject{
    
    var session: AVCaptureSession?
    //var delegate: AVCapturePhotoCaptureDelegate?
    
    let output = AVCapturePhotoOutput()
    
    //graphic layer
    let previewLayer = AVCaptureVideoPreviewLayer()
    let pointsLayer = CAShapeLayer()
    let leftArmActionLayer = CAShapeLayer()
    let rightArmActionLayer = CAShapeLayer()
    let leftFistActionLayer = CAShapeLayer()
    let rightFistActionLayer = CAShapeLayer()
    
    //prev arm points
    //0 is wrist, 1 is elbow, 2 is shoulder
    var prevLeftArmPts: [CGPoint?] = [nil,nil,nil]
    var prevRightArmPts: [CGPoint?] = [nil,nil,nil]
    var prevFrameTime: Date? = nil
    var prevLLerpProgress: Double = 0
    var prevRLerpProgress: Double = 0
    
    let defaultArmColor = UIColor(white: 0.8, alpha: 0.3)
    let speedArmColor = UIColor(red: 20/255, green: 192/255, blue: 1, alpha: 1)
    let correctColor = UIColor.green
    let wrongColor = UIColor.red
    
    let predictor = Predictor()
    /// The worker thread the capture session uses to publish the video frames.
    private let videoCaptureQueue = DispatchQueue(label: "Video Capture Queue",
                                                  qos: .userInitiated)
    //for view reading
    @Published var actionPrompt:String = ""
    @Published var actionState:String = ""
    @Published var showGoodActionState: Bool = false
    
    let actionPromptList: [String] = ["Left Jab", "Right Jab", "Left Uppercut", "Right Uppercut"]
    
    let actionLabelToPrompt: [String:String] = [
        "jableft":"Left Jab",
        "jabright":"Right Jab",
        "uppercutleft":"Left Uppercut",
        "uppercutright":"Right Uppercut"]
    
    func start(completion: @escaping (Error?) -> ()) {
        //self.delegate = delegate
        predictor.delegate = self
        checkPermissions(completion: completion)
    }
    
    private func checkPermissions(completion: @escaping (Error?) -> ()) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                self?.setupCamera(completion: completion)
            }
        case .restricted:
            break
        case .denied:
            break
        case .authorized:
            setupCamera(completion: completion)
        @unknown default:
            break
        }
    }
    
    public func generateNewRandomPrompt(){
        //publish a random action prompt
        DispatchQueue.main.async { [weak self] in
            self?.actionPrompt = self?.getRandomActionPrompt() ?? "None"
        }
    }
    
    private func getRandomActionPrompt()->String{
        return actionPromptList.randomElement() ?? "--None--"
    }
    
    private func setupCamera(completion: @escaping (Error?) -> ()) {
        let session = AVCaptureSession()
        guard let videoDataOutput = configureCaptureSession(session) else { return }
        // Set the video capture as the video output's delegate.
        videoDataOutput.setSampleBufferDelegate(self, queue: videoCaptureQueue)
        
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.session = session
        
        //publish a random action prompt
        DispatchQueue.main.async { [weak self] in
            self?.actionPrompt = self?.getRandomActionPrompt() ?? "None"
        }
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.session?.startRunning()
        }
        
        self.session = session
    }
    
    /// Configures or reconfigures the session to the new camera settings.
    /// - Tag: configureCaptureSession
    private func configureCaptureSession(_ captureSession: AVCaptureSession) -> AVCaptureVideoDataOutput? {
        
        // Tell the capture session to start configuration.
        session?.beginConfiguration()
        
        // Finalize the configuration after this method returns.
        defer { session?.commitConfiguration() }
        
        let input = AVCaptureDeviceInput.createCameraInput(position: .front,
                                                           frameRate: 30.0)
        
        let output = AVCaptureVideoDataOutput.withPixelFormatType(kCVPixelFormatType_32BGRA)
        
        let success = configureCaptureConnection(captureSession, input, output)
        return success ? output : nil
    }
    
    /// Sets the connection's orientation, image mirroring, and video stabilization.
    /// - Tag: configureCaptureConnection
    private func configureCaptureConnection(_ captureSession: AVCaptureSession,
                                            _ input: AVCaptureDeviceInput?,
                                            _ output: AVCaptureVideoDataOutput?) -> Bool {
        
        guard let input = input else { return false }
        guard let output = output else { return false }
        
        // Clear inputs and outputs from the capture session.
        captureSession.inputs.forEach(captureSession.removeInput)
        captureSession.outputs.forEach(captureSession.removeOutput)
        
        guard captureSession.canAddInput(input) else {
            print("The camera input isn't compatible with the capture session.")
            return false
        }
        
        guard captureSession.canAddOutput(output) else {
            print("The video output isn't compatible with the capture session.")
            return false
        }
        
        // Add the input and output to the capture session.
        captureSession.addInput(input)
        captureSession.addOutput(output)
        
        // This capture session must only have one connection.
        guard captureSession.connections.count == 1 else {
            let count = captureSession.connections.count
            print("The capture session has \(count) connections instead of 1.")
            return false
        }
        
        // Configure the first, and only, connection.
        guard let connection = captureSession.connections.first else {
            print("Getting the first/only capture-session connection shouldn't fail.")
            return false
        }
        
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = false
        }
        
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .off
        }
        
        // Discard newer frames if the app is busy with an earlier frame.
        output.alwaysDiscardsLateVideoFrames = true
        return true
    }
    
    func distanceBetween(point1: CGPoint, point2: CGPoint) -> Double {
        let xDist = point2.x - point1.x
        let yDist = point2.y - point1.y
        return sqrt((xDist * xDist) + (yDist * yDist))
    }
    
}

extension UIColor {
    func lerp(to: UIColor, with progress: CGFloat) -> UIColor {
        var fromR: CGFloat = 0, fromG: CGFloat = 0, fromB: CGFloat = 0, fromA: CGFloat = 0
        var toR: CGFloat = 0, toG: CGFloat = 0, toB: CGFloat = 0, toA: CGFloat = 0
        
        getRed(&fromR, green: &fromG, blue: &fromB, alpha: &fromA)
        
        to.getRed(&toR, green: &toG, blue: &toB, alpha: &toA)

        let lerpedRed = fromR + ((toR - fromR) * progress)
        let lerpedGreen = fromG + ((toG - fromG) * progress)
        let lerpedBlue = fromB + ((toB - fromB) * progress)
        let lerpedAlpha = fromA + ((toA - fromA) * progress)

        return UIColor(red: lerpedRed, green: lerpedGreen, blue: lerpedBlue, alpha: lerpedAlpha)
    }
}

extension CameraSevice: AVCaptureVideoDataOutputSampleBufferDelegate{
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        predictor.estimation(sampleBuffer: sampleBuffer)
    }
}

//graphic goal:
//normally the two arms and the two fists are in white color, but when you move them quickly they will change color,
// the faster, more yellow it gets? need to separate them into 4 layers
extension CameraSevice: PredictorDelegate{
    func predictCriticalPoints(_ predictor: Predictor, leftWrist: CGPoint?, rightWrist: CGPoint?, leftElbow: CGPoint?, rightElbow: CGPoint?, leftShoulder: CGPoint?, rightShoulder: CGPoint?) {
        
        let leftArmPath = CGMutablePath()
        let rightArmPath = CGMutablePath()
        let leftFistPath = CGMutablePath()
        let rightFistPath = CGMutablePath()
        let pointsPath = CGMutablePath();
        
        //get converted CG points
        var lwDeltaDist: Double = 0
        var leftWristPt: CGPoint?
        if let pt = leftWrist{
            leftWristPt = previewLayer.layerPointConverted(fromCaptureDevicePoint: pt)
            lwDeltaDist = distanceBetween(point1: leftWristPt!, point2: prevLeftArmPts[0] ?? leftWristPt!)
            prevLeftArmPts[0] = leftWristPt!
            //add dot path
            let dotPath = UIBezierPath(ovalIn: CGRect(x: leftWristPt!.x, y: leftWristPt!.y, width: 12, height: 12))
            pointsPath.addPath(dotPath.cgPath)
        }
        
        var rwDeltaDist: Double = 0
        var rightWristPt: CGPoint?
        if let pt = rightWrist{
            rightWristPt = previewLayer.layerPointConverted(fromCaptureDevicePoint: pt)
            rwDeltaDist = distanceBetween(point1: rightWristPt!, point2: prevRightArmPts[0] ?? rightWristPt!)
            prevRightArmPts[0] = rightWristPt
            //add dot path
            let dotPath = UIBezierPath(ovalIn: CGRect(x: rightWristPt!.x, y: rightWristPt!.y, width: 12, height: 12))
            pointsPath.addPath(dotPath.cgPath)
        }
        
        var leDeltaDist : Double = 0
        var leftElbowPt: CGPoint?
        if let pt = leftElbow{
            leftElbowPt = previewLayer.layerPointConverted(fromCaptureDevicePoint: pt)
            leDeltaDist = distanceBetween(point1: leftElbowPt!, point2: prevLeftArmPts[1] ?? leftElbowPt!)
            prevLeftArmPts[1] = leftElbowPt
            //add dot path
            let dotPath = UIBezierPath(ovalIn: CGRect(x: leftElbowPt!.x, y: leftElbowPt!.y, width: 12, height: 12))
            pointsPath.addPath(dotPath.cgPath)
        }
        
        var reDeltaDist : Double = 0
        var rightElbowPt: CGPoint?
        if let pt = rightElbow{
            rightElbowPt = previewLayer.layerPointConverted(fromCaptureDevicePoint: pt)
            reDeltaDist = distanceBetween(point1: rightElbowPt!, point2: prevRightArmPts[1] ?? rightElbowPt!)
            prevRightArmPts[1] = rightElbowPt!
            //add dot path
            let dotPath = UIBezierPath(ovalIn: CGRect(x: rightElbowPt!.x, y: rightElbowPt!.y, width: 12, height: 12))
            pointsPath.addPath(dotPath.cgPath)
        }
        
        var lsDeltaDist : Double = 0
        var leftShoulderPt: CGPoint?
        if let pt = leftShoulder{
            leftShoulderPt = previewLayer.layerPointConverted(fromCaptureDevicePoint: pt)
            lsDeltaDist = distanceBetween(point1: leftShoulderPt!, point2: prevLeftArmPts[2] ?? leftShoulderPt!)
            prevLeftArmPts[2] = leftShoulderPt!
            //add dot path
            let dotPath = UIBezierPath(ovalIn: CGRect(x: leftShoulderPt!.x, y: leftShoulderPt!.y, width: 12, height: 12))
            pointsPath.addPath(dotPath.cgPath)
        }
        
        var rsDeltaDist : Double = 0
        var rightShoulderPt: CGPoint?
        if let pt = rightShoulder{
            rightShoulderPt = previewLayer.layerPointConverted(fromCaptureDevicePoint: pt)
            rsDeltaDist = distanceBetween(point1: rightShoulderPt!, point2: prevRightArmPts[2] ?? rightShoulderPt!)
            prevRightArmPts[2] = rightShoulderPt!
            //add dot path
            let dotPath = UIBezierPath(ovalIn: CGRect(x: rightShoulderPt!.x, y: rightShoulderPt!.y, width: 12, height: 12))
            pointsPath.addPath(dotPath.cgPath)
        }
        
        //goal here is to draw two fists plus two arms together
        //left arm
        if let B = leftElbowPt, let A = leftShoulderPt {
            let path = UIBezierPath()
            path.move(to: A)
            path.addLine(to: B)
            
            if let C = leftWristPt {
                //fore arm
                path.addLine(to: C)
                
                //Left fist
                let dX = C.x - B.x
                let dY = C.y - B.y
                let tX = dX * 0.3 + C.x
                let tY = dY * 0.3 + C.y
                let fist = UIBezierPath(roundedRect: CGRect(x: tX-25, y: tY-25, width: 50, height: 50), cornerRadius: 17)
                leftFistPath.addPath(fist.cgPath)
            }
            leftArmPath.addPath(path.cgPath)
        }
        
        //right arm
        if let B = rightElbowPt, let A = rightShoulderPt {
            let path = UIBezierPath()
            path.move(to: A)
            path.addLine(to: B)
            
            if let C = rightWristPt{
                //forearm
                path.addLine(to: C)
                
                //right fist
                let dX = C.x - B.x
                let dY = C.y - B.y
                let tX = dX * 0.3 + C.x
                let tY = dY * 0.3 + C.y
                let fist = UIBezierPath(roundedRect: CGRect(x: tX-25, y: tY-25, width: 50, height: 50), cornerRadius: 17)
                rightFistPath.addPath(fist.cgPath)
            }
            rightArmPath.addPath(path.cgPath)
        }
        
        leftArmActionLayer.path = leftArmPath
        rightArmActionLayer.path = rightArmPath
        leftFistActionLayer.path = leftFistPath
        rightFistActionLayer.path = rightFistPath
        pointsLayer.path = pointsPath
        
        //using arm speed to color the path, when it is not showing good matched action
        if !showGoodActionState{
            //calculating arm speed
            if let prevT = prevFrameTime{
                let deltaT = Double(Date().timeIntervalSince(prevT))
                let maxSpeed = 200.0
                let lerpSpeed = 1.2 * deltaT
                let targetLLerpProgress = min(1, (lwDeltaDist + leDeltaDist + lsDeltaDist) / 3 / deltaT / maxSpeed)
                let targetRLerpProgress = min(1, (rwDeltaDist + reDeltaDist + rsDeltaDist) / 3 / deltaT / maxSpeed)
                
                //get current left color lerp progress
                if prevLLerpProgress < targetLLerpProgress-0.01{
                    prevLLerpProgress += lerpSpeed
                    prevLLerpProgress = min(prevLLerpProgress, targetLLerpProgress)
                }
                else if prevLLerpProgress > targetLLerpProgress+0.01{
                    prevLLerpProgress -= lerpSpeed
                    prevLLerpProgress = max(prevLLerpProgress, targetLLerpProgress)
                }
                
                //get current right color lerp progress
                if prevRLerpProgress < targetRLerpProgress-0.01{
                    prevRLerpProgress += lerpSpeed
                    prevRLerpProgress = min(prevRLerpProgress, targetRLerpProgress)
                }
                else if prevRLerpProgress > targetRLerpProgress+0.01{
                    prevRLerpProgress -= lerpSpeed
                    prevRLerpProgress = max(prevRLerpProgress, targetRLerpProgress)
                }
                
                //set colors
                leftArmActionLayer.strokeColor =
                defaultArmColor.lerp(
                    to: speedArmColor,
                    with: prevLLerpProgress).cgColor
                
                leftFistActionLayer.strokeColor =
                defaultArmColor.lerp(
                    to: speedArmColor,
                    with: prevLLerpProgress).cgColor
                
                rightArmActionLayer.strokeColor =
                defaultArmColor.lerp(
                    to: speedArmColor,
                    with: prevRLerpProgress).cgColor
                
                rightFistActionLayer.strokeColor =
                defaultArmColor.lerp(
                    to: speedArmColor,
                    with: prevRLerpProgress).cgColor
            }
        }
        else{
            //reset speed color for arms
            prevRLerpProgress = 0
            prevLLerpProgress = 0
            lwDeltaDist = 0
            leDeltaDist = 0
            lsDeltaDist = 0
            rwDeltaDist = 0
            reDeltaDist = 0
            rsDeltaDist = 0
        }
        
        prevFrameTime = Date()
        
        DispatchQueue.main.async {
            self.leftArmActionLayer.didChangeValue(for: \.path)
            self.rightArmActionLayer.didChangeValue(for: \.path)
            self.leftFistActionLayer.didChangeValue(for: \.path)
            self.rightFistActionLayer.didChangeValue(for: \.path)
            self.pointsLayer.didChangeValue(for: \.path)
        }
    }
    
    func predictBodyPoints(_ predictor: Predictor, didFindNewRecognizedPoints points: [CGPoint]) {
        let convertedPoints = points.map{
            previewLayer.layerPointConverted(fromCaptureDevicePoint: $0)
        }
        let combinedPath = CGMutablePath()
        for point in convertedPoints{
            let dotPath = UIBezierPath(ovalIn: CGRect(x: point.x, y: point.y, width: 12, height: 12))
            combinedPath.addPath(dotPath.cgPath)
        }
        
        pointsLayer.path = combinedPath
        DispatchQueue.main.async {
            self.pointsLayer.didChangeValue(for: \.path)
        }
    }
    
    func predictActionLabel(_ predictor: Predictor, didLabelAction actionLabel: String, with confidence: Double, _ bLeftHeavy: Bool) {
        if actionPrompt == actionLabelToPrompt[actionLabel]{
            if !showGoodActionState {
                //update UI stuff
                DispatchQueue.main.async { [weak self] in
                    self?.actionPrompt = "Complete"
                    self?.showGoodActionState = true
                    self?.actionState = "Good Job!"
                    
                    //make double blinking color animation when the action is completed
                    self?.leftArmActionLayer.strokeColor = self?.defaultArmColor.cgColor
                    self?.rightArmActionLayer.strokeColor = self?.defaultArmColor.cgColor
                    self?.leftFistActionLayer.strokeColor = self?.defaultArmColor.cgColor
                    self?.rightFistActionLayer.strokeColor = self?.defaultArmColor.cgColor
                    
                    let colorAnim = CABasicAnimation(keyPath: "strokeColor")
                    colorAnim.duration = 0.25
                    colorAnim.fromValue = self?.defaultArmColor.cgColor
                    colorAnim.toValue = self?.correctColor.cgColor
                    colorAnim.autoreverses = true
                    colorAnim.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeIn)

                    self?.leftArmActionLayer.add(colorAnim, forKey: "strokeColorAnimation")
                    self?.rightArmActionLayer.add(colorAnim, forKey: "strokeColorAnimation")
                    self?.leftFistActionLayer.add(colorAnim, forKey: "strokeColorAnimation")
                    self?.rightFistActionLayer.add(colorAnim, forKey: "strokeColorAnimation")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2*colorAnim.duration+0.05) {
                        self?.leftArmActionLayer.add(colorAnim, forKey: "strokeColorAnimation")
                        self?.rightArmActionLayer.add(colorAnim, forKey: "strokeColorAnimation")
                        self?.leftFistActionLayer.add(colorAnim, forKey: "strokeColorAnimation")
                        self?.rightFistActionLayer.add(colorAnim, forKey: "strokeColorAnimation")
                    }
                    
                    let NewPromptDelay = 2.8
                    DispatchQueue.main.asyncAfter(deadline: .now() + NewPromptDelay) {
                        self?.showGoodActionState = false
                        self?.generateNewRandomPrompt()
                    }
                }
            }
        }
    }
}
