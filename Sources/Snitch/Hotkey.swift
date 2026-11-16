import Carbon.HIToolbox

/// Global ⌃⌥S shortcut to open Snitch from anywhere.
final class Hotkey {
    private var ref: EventHotKeyRef?
    private static var handler: (() -> Void)?

    init(handler: @escaping () -> Void) {
        Hotkey.handler = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Hotkey.handler?()
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x534E4348), id: 1) // 'SNCH'
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }
}
