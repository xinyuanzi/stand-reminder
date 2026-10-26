import Foundation
import AVFoundation
import CoreAudio

/// 判断当前是否正在开会：摄像头被占用，或麦克风正在录音。
enum MeetingDetector {

    private static let videoSession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
        mediaType: .video,
        position: .unspecified
    )

    static func isBusy() -> Bool {
        cameraInUse() || microphoneInUse()
    }

    private static func cameraInUse() -> Bool {
        videoSession.devices.contains { $0.isInUseByAnotherApplication }
    }

    private static func microphoneInUse() -> Bool {
        guard let deviceID = defaultInputDevice() else { return false }
        return isDeviceRunning(deviceID)
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private static func isDeviceRunning(_ deviceID: AudioDeviceID) -> Bool {
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running)
        guard status == noErr else { return false }
        return running != 0
    }
}
