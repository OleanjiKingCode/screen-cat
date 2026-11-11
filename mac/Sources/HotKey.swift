import Carbon.HIToolbox

/// One system-wide keyboard shortcut. Carbon's hot key API works from a
/// menu bar app and needs no Accessibility permission, unlike watching every
/// key press. The shortcut is gone as soon as this is released.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// `keyCode` is a `kVK_` code; `modifiers` are Carbon flags such as
    /// `cmdKey | optionKey`. Nil when another app already holds the keys.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &type, me, &handler)
        // "SCat".
        let id = EventHotKeyID(signature: OSType(0x5343_6174), id: 1)
        guard installed == noErr,
              RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref) == noErr
        else {
            // deinit still runs after a failed init, so it does the cleanup.
            return nil
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
