import SwiftUI

@main
struct QuotaBarApp: App {
    @State private var store = SubscriptionStore()
    @State private var refreshTimer: Timer?

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: store)
                .task {
                    await store.refreshAll()
                    startAutoRefreshIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                    startAutoRefreshIfNeeded()
                }
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
                .frame(minWidth: 440, idealWidth: 440, minHeight: 480, idealHeight: 520)
        }
    }

    private func startAutoRefreshIfNeeded() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        let minutes = UserDefaults.standard.integer(forKey: "autoRefreshMinutes")
        guard minutes > 0 else { return }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { _ in
            Task { @MainActor in
                await store.refreshAll()
            }
        }
    }
}
