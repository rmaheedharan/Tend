// TendAI scaffold (WI-M2-M1). The adapters arrive in WI-M2-M2 (on-device model), M3 (speech), M4 (cloud transport),
// M5 (Keychain key store) and M6 (cloud adapters). AC-M2-09 Rules 2, 3 and 5 scan this root (`ScanScope`: required).
// P-1, P-2.

import Foundation

/// The module's identity, used by the scaffold tests on macOS and in the iOS Simulator host.
public enum TendAIModule {
    public static let name = "TendAI"
}
