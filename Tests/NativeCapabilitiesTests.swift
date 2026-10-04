import Foundation

@MainActor func runNativeCapabilitiesTests() -> Int {
    var failures = 0
    let unavailable = NativePlaybackCapabilities.detect(videoProbe: { _,_,_ in false }, aacProbe: { false })
    if !unavailable.video.isEmpty || !unavailable.audio.isEmpty { failures += 1; print("FAIL: 未确认的解码能力不能上报") }
    let confirmed = NativePlaybackCapabilities.detect(videoProbe: { profile,_,_ in profile == "main" },aacProbe:{true})
    if confirmed.video.first?.profiles != ["main"] || confirmed.audio.first?.profiles != ["lc"] {
        failures += 1; print("FAIL: 仅上报实际确认的profile")
    }
    let actual = NativePlaybackCapabilities.detect()
    let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
    if let data = try? encoder.encode(actual), let value = String(data:data,encoding:.utf8) { print("当前主机native能力（不代表手机）: \(value)") }
    return failures
}
