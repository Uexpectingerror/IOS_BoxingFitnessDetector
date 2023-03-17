//
//  ActionPredicator.swift
//  BoxingDetector
//
//  Created by Orson Wu on 3/1/23.
//

import Foundation
import Vision
import CoreImage
typealias BoxingClassifier = BoxingActionClassifier_mixed_lessUC

//delegate to pass prediction results to the view controller to display
protocol PredictorDelegate: AnyObject{
    func predictBodyPoints(_ predictor: Predictor, didFindNewRecognizedPoints points: [CGPoint])
    func predictActionLabel(_ predictor: Predictor, didLabelAction action: String, with confidence: Double, _ bLeftHeavy: Bool)
    func predictCriticalPoints(_ predictor: Predictor,
                               leftWrist: CGPoint?,
                               rightWrist: CGPoint?,
                               leftElbow: CGPoint?,
                               rightElbow: CGPoint?,
                               leftShoulder:CGPoint?,
                               rightShoulder:CGPoint?)
}

class Predictor{
    /// A human body pose request instance that finds poses in each video frame.
    /// The video-processing chain reuses this instance for all frames
    /// - Tag: humanBodyPoseRequest
    private let humanBodyPoseRequest = VNDetectHumanBodyPoseRequest()
    
    weak var delegate: PredictorDelegate?
    let predictionWindowSize = 45
    var poseWindow: [VNHumanBodyPoseObservation?] = []
    //var validPoses: [VNHumanBodyPoseObservation] = []
    var leftMovement: Double = 0
    var rightMovement: Double = 0
    var bLeftHeavy = false
    
    init(){
        poseWindow.reserveCapacity(predictionWindowSize)
        //validPoses.reserveCapacity(predictionWindowSize)
    }
    
    /// Converts a sample buffer into a core graphics image.
    /// - Parameter buffer: A sample buffer, typically from a video capture.
    /// - Returns: A `CGImage` if Core Image successfully converts the sample
    /// buffer; otherwise `nil`.
    /// - Tag: imageFromFrame
    private func imageFromFrame(_ buffer: CMSampleBuffer) -> CGImage? {
        guard let imageBuffer = buffer.imageBuffer else {
            print("The frame doesn't have an underlying image buffer.")
            return nil
        }
        
        // Create a Core Image context.
        let ciContext = CIContext(options: nil)
        
        // Create a Core Image image from the sample buffer.
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        
        // Generate a Core Graphics image from the Core Image image.
        guard let cgImage = ciContext.createCGImage(ciImage,
                                                    from: ciImage.extent) else {
            print("Unable to create an image from a frame.")
            return nil
        }
        
        return cgImage
    }
    
    func estimation(sampleBuffer: CMSampleBuffer){
        if let frame = imageFromFrame(sampleBuffer){
            let requestHandler = VNImageRequestHandler(cgImage: frame, orientation: .up)
            
            do{
                try requestHandler.perform([humanBodyPoseRequest])
            } catch{
                print("unable to perform the request, with error: \(error)")
            }
            
            let observations = humanBodyPoseRequest.results
            processObservation(observations?.first)
        }
    }
    
    func prepareInputWithObservation(_ observations: [VNHumanBodyPoseObservation?]) -> MLMultiArray?{
        let numAvailableFrames = observations.count
        var multiArrayBuffer = [MLMultiArray]()
        var poseCount = 0
        
        for frameIndex in 0 ..< numAvailableFrames {
            //if pose is empty, just add empty array
            guard let pose = observations[frameIndex] else{
                let oneFrameMultiArray = zeroedMultiArrayWithShape([1, 3, 18])
                multiArrayBuffer.append(oneFrameMultiArray)
                continue
            }

            //if not empty add the key point multi array
            do {
                //add arrary to buffer if such array exists
                let oneFrameMultiArray = try pose.keypointsMultiArray()
                
                //right ankle
                oneFrameMultiArray[[0,0,10] as [NSNumber]] = NSNumber(floatLiteral: 0)
                oneFrameMultiArray[[0,1,10] as [NSNumber]] = NSNumber(floatLiteral: 1)
                oneFrameMultiArray[[0,2,10] as [NSNumber]] = NSNumber(floatLiteral: 0)
                
                //left ankle
                oneFrameMultiArray[[0,0,13] as [NSNumber]] = NSNumber(floatLiteral: 0)
                oneFrameMultiArray[[0,1,13] as [NSNumber]] = NSNumber(floatLiteral: 1)
                oneFrameMultiArray[[0,2,13] as [NSNumber]] = NSNumber(floatLiteral: 0)
                
                //right knee
                oneFrameMultiArray[[0,0,9] as [NSNumber]] = NSNumber(floatLiteral: 0)
                oneFrameMultiArray[[0,1,9] as [NSNumber]] = NSNumber(floatLiteral: 1)
                oneFrameMultiArray[[0,2,9] as [NSNumber]] = NSNumber(floatLiteral: 0)
                
                //left ankle
                oneFrameMultiArray[[0,0,12] as [NSNumber]] = NSNumber(floatLiteral: 0)
                oneFrameMultiArray[[0,1,12] as [NSNumber]] = NSNumber(floatLiteral: 1)
                oneFrameMultiArray[[0,2,12] as [NSNumber]] = NSNumber(floatLiteral: 0)
                
                multiArrayBuffer.append(oneFrameMultiArray)
                poseCount += 1
            } catch {
                let oneFrameMultiArray = zeroedMultiArrayWithShape([1, 3, 18])
                multiArrayBuffer.append(oneFrameMultiArray)
            }
        }
        
        //if too many empty poses just return nil
        if Double(poseCount/predictionWindowSize) < 0.6{
            print("low valid pose count!!!")
            return nil
        }
        
        return MLMultiArray(concatenating: [MLMultiArray](multiArrayBuffer), axis: 0, dataType: .float)
    }
    
    func appendEmptyMLArray(_ buffer: inout [MLMultiArray]){
        //try add empty multiArray to the buffer
        let oneFrameMultiArray = zeroedMultiArrayWithShape([1, 3, 18])
            //try resetMultiArray(oneFrameMultiArray)
        buffer.append(oneFrameMultiArray)

    }
    
    func resetMultiArray(_ predictionWindow: MLMultiArray, with value: Double = 0.0) throws {
        let pointer = try UnsafeMutableBufferPointer<Double>(predictionWindow)
        pointer.initialize(repeating: value)
        
    }
    
    private func zeroedMultiArrayWithShape(_ shape: [Int]) -> MLMultiArray {
        // Create the multiarray.
        guard let array = try? MLMultiArray(shape: shape as [NSNumber],
                                            dataType: .double) else {
            fatalError("Creating a multiarray with \(shape) shouldn't fail.")
        }

        // Get a pointer to quickly set the array's values.
        guard let pointer = try? UnsafeMutableBufferPointer<Double>(array) else {
            fatalError("Unable to initialize multiarray with zeros.")
        }

        // Set every element to zero.
        pointer.initialize(repeating: 0.0)
        return array
    }
    
    func processObservation(_ newObservation: VNHumanBodyPoseObservation?){
        //if observation is valid,
        //publish point
        if let obs = newObservation{
            //publish the body point
            publishBodyPoints(obs)
            
        }
        //add pose regardless to the main window
        poseWindow.append(newObservation)
        
        //simple way: loop through all elements in pose window and sum the total movement
        var lastValidPose:VNHumanBodyPoseObservation? = nil

        leftMovement = 0.0
        rightMovement = 0.0
        for pose in poseWindow{
            if let validPose = pose{
                //assign the last pose to valid pose
                if lastValidPose == nil{
                    lastValidPose = validPose
                    continue
                }
                
                if let tempLastValidPose = lastValidPose{
                    do{
                        let lastObsLP = try tempLastValidPose.recognizedPoint(.leftElbow)
                        let leftP = try validPose.recognizedPoint(.leftElbow)
                        leftMovement += lastObsLP.distance(leftP)
                        
                        let lastObsRP = try tempLastValidPose.recognizedPoint(.rightElbow)
                        let rightP = try validPose.recognizedPoint(.rightElbow)
                        rightMovement += lastObsRP.distance(rightP)
                    }
                    catch{
                        print("error finding recogonizedPoints")
                    }
                }
                lastValidPose = validPose
            }
        }
        
        if leftMovement > rightMovement{
            bLeftHeavy = true
        }
        else if rightMovement > leftMovement{
            bLeftHeavy = false
        }

        //abort if not enough pose frames
        if poseWindow.count < predictionWindowSize{
            return
        }
        
        //prepare the window as MLarray
        //if not enough good frames, it would return nil
        //get the prediction
        guard let filledWindow = prepareInputWithObservation(poseWindow),
              let boxingClassifier = try? BoxingClassifier(configuration: MLModelConfiguration()),
              let predictions = try? boxingClassifier.prediction(poses: filledWindow)
        else {
            poseWindow.removeFirst(10)
            return
        }
        //remove some stride
        poseWindow.removeFirst(5)
        var label = predictions.label
        let confidence = predictions.labelProbabilities[label] ?? 0
        
        //all results data
//        let results = predictions.labelProbabilities.sorted { $0.1>$1.1
//        }
//        let result = results.map { return "\($0) = \($1 * 100)%"
//        }.joined(separator: "\n")
        //print(label, " : ", confidence)
        
        //clear the pose data window if found a confident one
        if confidence > 0.3 && (leftMovement > 0.2 || rightMovement > 0.2) {
            if label == "jab" || label == "uppercut"{
                if bLeftHeavy{
                    label += "left"
                }
                else{
                    label += "right"
                }
                print(label, "--good action--: ", confidence)

                poseWindow.removeAll()
                leftMovement = 0
                rightMovement = 0
            }
        }
        delegate?.predictActionLabel(self, didLabelAction: label, with: confidence, bLeftHeavy)
    }
    
    func publishBodyPoints( _ observation: VNHumanBodyPoseObservation){
        var lwGP: CGPoint? = nil
        var rwGP: CGPoint? = nil
        var leGP: CGPoint? = nil
        var reGP: CGPoint? = nil
        var lsGP: CGPoint? = nil
        var rsGP: CGPoint? = nil

        //publish critical points
        do{
            let lwP = try observation.recognizedPoint(.leftWrist)
            if lwP.confidence > 0.1{
                lwGP = CGPoint(x: lwP.x, y: 1 - lwP.y)
            }
            
            let rwP = try observation.recognizedPoint(.rightWrist)
            if rwP.confidence > 0.1{
                rwGP = CGPoint(x: rwP.x, y: 1 - rwP.y)
            }
            
            let leP = try observation.recognizedPoint(.leftElbow)
            if leP.confidence > 0.1{
                leGP = CGPoint(x: leP.x, y: 1 - leP.y)
            }
            
            let reP = try observation.recognizedPoint(.rightElbow)
            if reP.confidence > 0.1{
                reGP = CGPoint(x: reP.x, y: 1 - reP.y)
            }
            
            let lsP = try observation.recognizedPoint(.leftShoulder)
            if lsP.confidence > 0.1{
                lsGP = CGPoint(x: lsP.x, y: 1 - lsP.y)
            }
            
            let rsP = try observation.recognizedPoint(.rightShoulder)
            if rsP.confidence > 0.1{
                rsGP = CGPoint(x: rsP.x, y: 1 - rsP.y)
            }
            
            delegate?.predictCriticalPoints(self, leftWrist: lwGP, rightWrist: rwGP, leftElbow: leGP, rightElbow: reGP, leftShoulder: lsGP, rightShoulder: rsGP)
        }
        catch{
            print("error finding recogonizedPoints")
            return
        }
    }
}
