import SwiftUI

extension View {
    /// 悬浮控件背景：iOS 26+ 采用 Liquid Glass（`.glassEffect`），旧系统回退到原毛玻璃材质。
    ///
    /// 仅用于悬浮在内容之上的交互控件或 HUD（播放器控制、浮动标签等）；
    /// 内容自身的背景应保持扁平，不要套用，符合 Apple Liquid Glass 设计指引。
    @ViewBuilder
    func floatingGlass<S: Shape>(
        in shape: S,
        interactive: Bool = false,
        fallback material: Material = .ultraThinMaterial
    ) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(material, in: shape)
        }
    }
}
