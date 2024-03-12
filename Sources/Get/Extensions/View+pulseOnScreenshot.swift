////
////  View+pulseOnScreenshot.swift
////
////
////  Created by Alexey Govorovsky on 06.03.2024.
////
//
//import SwiftUI
//import PulseUI
//
//
//private struct PulseOnScreenshotViewModifier: ViewModifier {
//    let console: Bool
//    @State private var isPresentingPulse: Bool = false
//    
//    func body(content: Content) -> some View {
//        content
//        //.alert(isPresented: $isPresentingAlert, content: alert)
//            .sheet(isPresented: $isPresentingPulse, onDismiss: { isPresentingPulse = false }) {
//                if console {
//                    NavigationView {
//                        ConsoleView(store: .shared)
//                    }
//                } else {
//                    StandaloneShareStoreView(store: .shared, onDismiss: { isPresentingPulse = false })
//                }
//            }
//            .onReceive(
//                NotificationCenter.default.publisher(
//                    for: UIApplication.userDidTakeScreenshotNotification,
//                    object: nil
//                )
//            ) { _ in
//                isPresentingPulse = true
//            }
//    }
//}
//
//extension View {
//    /// Displays an alert on the current view if the user takes a screenshot of their device
//    public func pulseOnScreenshot(console: Bool = false) -> some View {
//        modifier(PulseOnScreenshotViewModifier(console: console))
//    }
//}
