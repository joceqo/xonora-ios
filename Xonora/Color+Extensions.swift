import SwiftUI

extension Color {
    static let xonoraPurple = Color(red: 0.58, green: 0.22, blue: 0.92)
    static let xonoraCyan = Color(red: 0.0, green: 0.85, blue: 0.85)
    
    static var xonoraGradient: LinearGradient {
        LinearGradient(
            colors: [.xonoraPurple, .xonoraCyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
