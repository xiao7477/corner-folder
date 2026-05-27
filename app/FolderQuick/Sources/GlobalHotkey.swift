import AppKit
import Carbon

final class GlobalHotkey {
    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return noErr }
                let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
                hotkey.action()
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )

        let hotkeyID = EventHotKeyID(signature: OSType(0x46514B31), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_F),
            UInt32(optionKey | cmdKey),
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }

    deinit {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }
}
