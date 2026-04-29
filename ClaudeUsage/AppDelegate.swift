import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var usageVM = UsageViewModel()
    private var suppressNextLeftClick = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "☁ --"
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 180)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: UsageView(vm: usageVM)
        )

        usageVM.onTitleChange = { [weak self] title in
            self?.statusItem.button?.title = title
        }

        usageVM.refresh()
    }

    @objc func handleClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            suppressNextLeftClick = true
            let menu = NSMenu()
            menu.delegate = self
            menu.addItem(NSMenuItem(title: "↻  새로고침", action: #selector(onRefresh), keyEquivalent: "r"))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            if suppressNextLeftClick {
                suppressNextLeftClick = false
                return
            }
            togglePopover()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        // 메뉴 닫힌 후 spurious click이 없는 경우를 대비해 플래그 해제
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.suppressNextLeftClick = false
        }
    }

    @objc func onRefresh() {
        usageVM.refresh()
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
