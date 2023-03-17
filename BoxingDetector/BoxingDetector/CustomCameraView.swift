//
//  CustomCameraView.swift
//  BoxingDetector
//
//  Created by Orson Wu on 3/1/23.
//

import SwiftUI

struct CustomCameraView: View {
    
    @StateObject var cameraService = CameraSevice()
    @Binding var capturedImage: UIImage?
    @State var isAnimating: Bool = false
    @State var isHidden: Bool = true
    @State var curScore: Int = 0

    @Environment(\.presentationMode) private var presentationMode
    
    var body: some View {
        ZStack {
            CameraView(cameraService: cameraService)
            
            VStack {
                Text(cameraService.actionPrompt)
                    .font(.largeTitle)
                    .fontWeight(.heavy)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.white)
                    .padding(.vertical, 12)
                
                
                Text(cameraService.actionState)
                    .font(.largeTitle)
                    .shadow(color: .black, radius: 10)
                    .fontWeight(.heavy)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.green)
                    .opacity(isHidden ? 0 : 1)
                    .scaleEffect(isAnimating ? 1.2 : 0.1)
                    .onChange(of: cameraService.showGoodActionState) { newValue in
                        if (newValue){
                            self.curScore += 1
                            self.isHidden = false
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.25, blendDuration: 0)) {
                                self.isAnimating.toggle()
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation(.easeIn(duration: 0.6)) {
                                    self.isAnimating.toggle()
                                }
                            }
                        }else{
                            self.isHidden = true
                            self.isAnimating = false
                        }
                    }
                Spacer()
                    .frame(height: 50)
                Text("\(curScore)")
                    .font(Font.custom("Helvetica", size: 50))
                    .fontWeight(.heavy)
                    .foregroundColor(Color.white)
                    .multilineTextAlignment(.trailing)
                    .padding(.trailing, 5)
                    .scaleEffect(isAnimating ? 1.5 : 1.0)
                    .onChange(of: cameraService.showGoodActionState) { newValue in
                        if (newValue){
                            withAnimation(.easeIn(duration: 0.5)) {
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                withAnimation(.easeOut(duration: 0.5)) {
                                }
                            }
                        }
                    }
                Spacer()
            }
        }
    }
}

