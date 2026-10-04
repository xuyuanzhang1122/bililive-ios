import AVFoundation
import AudioToolbox
import Foundation
import VideoToolbox

// 用明确的8-bit SDR、1080p60/level4.2 SPS/PPS创建真实解码器；不能把容器支持当编码支持。
enum NativePlaybackCapabilities {
    private static let parameterSets: [(String,String,String)] = [
        ("baseline","Z0LAKtkAeAIn5cBEAAADAAQAAAMB4DxgySA=","aMuDyyA="),
        ("main","Z01AKuygPAET8uAiAAADAAIAAAMA8B4wYyw=","aOvjyyA="),
        ("high","Z2QAKqzZQHgCJ+XARAAAAwAEAAADAeA8YMZY","aOvjyyLA")
    ]
    static func detect(videoProbe: ((String, Data, Data) -> Bool)? = nil, aacProbe: (() -> Bool)? = nil) -> PlaybackCapabilities {
        let profiles = parameterSets.compactMap { profile,sps,pps -> String? in
            guard let sps = Data(base64Encoded:sps), let pps = Data(base64Encoded:pps),
                  (videoProbe?(profile,sps,pps) ?? confirmsH264(sps:sps,pps:pps)) else { return nil }
            return profile
        }
        let video = profiles.isEmpty ? [] : [VideoDecodeCapability(codec:"h264",profiles:profiles,maxLevel:42,
            maxWidth:1920,maxHeight:1080,maxFps:60,maxBitDepth:8,hdr:false)]
        let audio = (aacProbe?() ?? confirmsAAC()) ? [AudioDecodeCapability(codec:"aac",profiles:["lc"],maxChannels:2,maxSampleRate:48000)] : []
        let mp4 = AVURLAsset.isPlayableExtendedMIMEType("video/mp4")
        let hls = AVURLAsset.isPlayableExtendedMIMEType("application/vnd.apple.mpegurl")
        return PlaybackCapabilities(containers:(mp4 ? ["mp4"] : []) + (hls ? ["hls"] : []),
            protocols:(mp4 ? ["file"] : []) + (hls ? ["hls"] : []),video:video,audio:audio)
    }
    private static func confirmsH264(sps:Data,pps:Data) -> Bool {
        var format: CMFormatDescription?
        let status = sps.withUnsafeBytes { s in pps.withUnsafeBytes { p in
            let pointers = [s.bindMemory(to:UInt8.self).baseAddress!,p.bindMemory(to:UInt8.self).baseAddress!]
            let sizes = [sps.count,pps.count]
            return pointers.withUnsafeBufferPointer { pointers in sizes.withUnsafeBufferPointer { sizes in
                CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator:nil,parameterSetCount:2,
                    parameterSetPointers:pointers.baseAddress!,parameterSetSizes:sizes.baseAddress!,nalUnitHeaderLength:4,formatDescriptionOut:&format)
            } }
        } }
        guard status == noErr, let format else { return false }
        let size = CMVideoFormatDescriptionGetDimensions(format)
        guard size.width == 1920, size.height == 1080 else { return false }
        var decoder: VTDecompressionSession?
        var callback = VTDecompressionOutputCallbackRecord(decompressionOutputCallback: { _,_,_,_,_,_,_ in },decompressionOutputRefCon:nil)
        let created = VTDecompressionSessionCreate(allocator:nil,formatDescription:format,decoderSpecification:nil,
            imageBufferAttributes:nil,outputCallback:&callback,decompressionSessionOut:&decoder)
        guard created == noErr, let decoder else { return false }
        VTDecompressionSessionInvalidate(decoder)
        return true
    }
    private static func confirmsAAC() -> Bool {
        var source = AudioStreamBasicDescription()
        source.mSampleRate = 48000; source.mFormatID = kAudioFormatMPEG4AAC
        source.mFormatFlags = UInt32(MPEG4ObjectID.AAC_LC.rawValue); source.mFramesPerPacket = 1024; source.mChannelsPerFrame = 2
        var target = AudioStreamBasicDescription()
        target.mSampleRate = 48000; target.mFormatID = kAudioFormatLinearPCM
        target.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        target.mFramesPerPacket = 1; target.mChannelsPerFrame = 2; target.mBitsPerChannel = 16
        target.mBytesPerFrame = 4; target.mBytesPerPacket = 4
        var converter: AudioConverterRef?
        guard AudioConverterNew(&source,&target,&converter) == noErr, let converter else { return false }
        AudioConverterDispose(converter)
        return true
    }
}
