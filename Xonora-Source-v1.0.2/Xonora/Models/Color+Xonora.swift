import SwiftUI

extension Color {
    static var xonoraGradient: LinearGradient {
        LinearGradient(
            colors: [.xonoraPurple, .xonoraBlue, .xonoraCyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var xonoraGradientHorizontal: LinearGradient {
        LinearGradient(
            colors: [.xonoraPurple, .xonoraBlue, .xonoraCyan],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
