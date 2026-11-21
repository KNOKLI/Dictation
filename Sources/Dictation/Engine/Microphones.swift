import CoreAudio
import AudioToolbox
import Observation
import Foundation
import AVFoundation

struct AudioInput: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String   // постоянный идентификатор устройства — его и запоминаем
    let name: String
}

/// Доступ к списку аудиоустройств через CoreAudio.
enum CoreAudioDevices {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    static func inputs() -> [AudioInput] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard inputChannels(id) > 0,
                  let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return AudioInput(id: id, uid: uid, name: name)
        }
    }

    static func defaultInput() -> AudioDeviceID? {
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    static func device(forUID uid: String) -> AudioDeviceID? {
        inputs().first { $0.uid == uid }?.id
    }

    static func name(of id: AudioDeviceID) -> String? { string(id, kAudioObjectPropertyName) }

    /// Подписка на изменения (подключили/отключили устройство, сменили системный вход).
    static func observe(_ selector: AudioObjectPropertySelector, _ block: @escaping () -> Void) {
        var addr = address(selector)
        AudioObjectAddPropertyListenerBlock(system, &addr, DispatchQueue.main) { _, _ in block() }
    }

    // MARK: - Внутреннее

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func inputChannels(_ id: AudioDeviceID) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
        }
        guard status == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }
}

/// Живой список микрофонов для интерфейса.
@MainActor
@Observable
final class MicrophoneList {
    private(set) var devices: [AudioInput] = []
    private(set) var defaultName = ""

    init() {
        refresh()
        CoreAudioDevices.observe(kAudioHardwarePropertyDevices) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        CoreAudioDevices.observe(kAudioHardwarePropertyDefaultInputDevice) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        // только то, что запись реально умеет открыть (без служебных виртуальных устройств)
        devices = CoreAudioDevices.inputs().filter { AVCaptureDevice(uniqueID: $0.uid) != nil }
        defaultName = CoreAudioDevices.defaultInput().flatMap(CoreAudioDevices.name(of:)) ?? "—"
    }
}
