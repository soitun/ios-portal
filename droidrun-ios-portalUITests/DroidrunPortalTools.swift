//
//  DroidrunPortal.swift
//  droidrun-ios-portal
//
//  Created by Timo Beckmann on 03.06.25.
//

import Foundation
import XCTest

enum SwipeDirection: String, Codable {
    case up, down, left, right
}

extension XCUIDevice.Button {
    init?(rawValue: Int) {
        switch rawValue {
        case 0: self = .home
            //case 1: self = .volumeUp
            //case 2: self = .volumeDown
        case 4: self = .action
        case 5: self = .camera
        default: return nil
        }
    }
}

extension DroidrunPortalTools {
    enum Error: Swift.Error, LocalizedError {
        case invalidTool(name: String?, message: String)
        case noAppFound
        case apiNotConfigured
        
        var errorDescription: String? {
            switch self {
            case .invalidTool(let name, let message):
                "Invalid tool \(name ?? "unknown"): \(message)"
            case .noAppFound:
                "No app found to interact with, try to open an app first."
            case .apiNotConfigured:
                "No API key found"
            }
        }
    }
}

struct PhoneState: Codable {
    let activity: String
    let keyboardShown: Bool
    let focusedElement: String?
}

// tools
final class DroidrunPortalTools: XCTestCase {
    var app: XCUIApplication?
    var bundleIdentifier: String?
    
    static let shared = DroidrunPortalTools()

    func reset() {
        self.bundleIdentifier = "com.apple.springboard"
        self.app = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        self.app?.activate()
        print("reset to homescreen")
    }
    
    @MainActor
    func fetchPhoneState() throws -> PhoneState {
        guard let app else {
            return PhoneState(activity: "most likely apple springboard", keyboardShown: false, focusedElement: nil)
        }
        
        var activity = self.bundleIdentifier ?? "unknown"
        let navBar = app.navigationBars.firstMatch
        if navBar.exists,
           !navBar.identifier.isEmpty {
            activity += " - \(navBar.identifier)"
        }
        let label = app.staticTexts.firstMatch
        if label.exists, !label.label.isEmpty {
            activity += " - \(label.label)"
        }
        
        let keyboardShown = app.keyboards.element.exists && app.keyboards.element.isHittable
        
        // Find the focused element and get its label or identifier
        let focusedElement = app.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
        var focusedElementDescription: String? = nil
        if focusedElement.exists {
            if !focusedElement.label.isEmpty {
                focusedElementDescription = focusedElement.label
            } else if !focusedElement.identifier.isEmpty {
                focusedElementDescription = focusedElement.identifier
            } else {
                focusedElementDescription = String(describing: focusedElement)
            }
        }
        
        return PhoneState(activity: activity, keyboardShown: keyboardShown, focusedElement: focusedElementDescription)
    }
    
    @MainActor
    func openApp(bundleIdentifier: String) throws {
        if bundleIdentifier == self.bundleIdentifier, app != nil {
            app?.activate()
            return
        }
        
        let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
        
        if bundleIdentifier == "com.apple.springboard" {
            app.activate() // Avoid relaunching springboard since that locks the phone
        } else {
            app.launch()
        }
        
        self.bundleIdentifier = bundleIdentifier
        self.app = app
    }
    
    // TODO: vibecoded. this only shows bundle identifiers of apps launched in the testing session
    @MainActor
    func listApps() -> [String] {
        return ProcessInfo.processInfo.environment.keys
            .filter { $0.hasPrefix("DYLD_INSERT_ID_") }
            .map { String($0.dropFirst("DYLD_INSERT_ID_".count)) }
    }
    
    @MainActor
    func fetchAccessibilityTree() throws -> String {
        guard let app else {
            throw Error.noAppFound
        }
        
        return app.accessibilityTree()
    }

    @MainActor
    func fetchAccessibilityClickables() throws -> [AccessibilityTreeClickables.Node] {
        guard let app else {
            throw Error.noAppFound
        }
        return app.accessibilityClickables()
    }
    
    @MainActor
    func tapElement(rect coordinateString: String, count: Int?, longPress: Bool?) throws {
        print("Tap \(coordinateString) \(count ?? 1) times long: \(longPress ?? false)")
        guard let app else {
            throw Error.noAppFound
        }
        let coordinate = NSCoder.cgRect(for: coordinateString)
        let midPoint = CGPoint(x: coordinate.midX, y: coordinate.midY)
        let startCoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let targetCoordinate = startCoordinate.withOffset(CGVector(dx: midPoint.x, dy: midPoint.y))
        if longPress == true {
            targetCoordinate.press(forDuration: 0.5)
        } else {
            if count == 2 {
                targetCoordinate.doubleTap()
            } else {
                targetCoordinate.tap()
            }
        }
    }
    
    @MainActor
    func scroll(x: CGFloat, y: CGFloat, distanceX: CGFloat, distanceY: CGFloat) throws {
        guard let app else {
            throw Error.noAppFound
        }
        let mid  = CGPoint(x: x, y: y)
        
        let root = app.coordinate(withNormalizedOffset: .zero)
        
        let start = root.withOffset(CGVector(dx: mid.x, dy: mid.y))
        
        let end = root.withOffset(CGVector(dx: mid.x + distanceX, dy: mid.y + distanceY))
        
        start.press(forDuration: 0, thenDragTo: end)
    }
    
    @MainActor
    func swipe(x: CGFloat, y: CGFloat, direction: SwipeDirection) throws {
        print("Swipe \(direction) {x: \(x), y: \(y)}")
        guard let app else {
            throw Error.noAppFound
        }
        let mid = CGPoint(x: x, y: y)
        
        // Root (0,0) of the screen
        let root = app.coordinate(withNormalizedOffset: .zero)
        
        let start = root.withOffset(CGVector(dx: mid.x, dy: mid.y))
        
        let end: XCUICoordinate
        switch direction {
        case .up:
            end = root.withOffset(CGVector(dx: mid.x, dy: mid.y - 100))
        case .down:
            end = root.withOffset(CGVector(dx: mid.x, dy: mid.y + 100))
        case .left:
            end = root.withOffset(CGVector(dx: mid.x - 100, dy: mid.y))
        case .right:
            end = root.withOffset(CGVector(dx: mid.x + 100, dy: mid.y))
        }
        
        start.press(forDuration: 0.1, thenDragTo: end)
    }
    
    @MainActor
    func enterText(rect: String, text: String) async throws {
        print("Enter Text \(rect) -> \(text)")
        guard let app else {
            throw Error.noAppFound
        }
        try tapElement(rect: rect, count: 1, longPress: false)
        let keyboard = app.keyboards.element
        
        let appeared = keyboard.waitForExistence(timeout: 2)
        guard appeared && keyboard.isHittable else {
            throw Error.invalidTool(name: "enterText", message: "Keyboard not present or not hittable after tapping element.")
        }

        // Defensive: Check if any text field is focused
        let focusedElement = app.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
        guard focusedElement.exists else {
            throw Error.invalidTool(name: "enterText", message: "No element has keyboard focus.")
        }
        
        app.typeText(text + "\n")
    }
    
    @MainActor
    func enterText(_ text: String) throws {
        guard let app = self.app else {
            throw Error.noAppFound
        }
        // Find the focused element
        let focusedElement = app.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
        guard focusedElement.exists else {
            throw Error.invalidTool(name: "enterText", message: "No element has keyboard focus.")
        }
        print("Typing text into focused element: \(text)")
        focusedElement.typeText(text)
    }
    
    @MainActor
    func pressKey(key: XCUIDevice.Button) throws {
        print("Press Key \(key)")
        XCUIDevice.shared.press(key)
    }
    
    @MainActor
    func pressKeycode(_ keycode: Int) throws {
        // Map keycodes to iOS representations
        let keyMap: [Int: String] = [
            66: "\n",      // Enter/Return
            67: "\u{8}",   // Delete/Backspace
            61: "\t"       // Tab
        ]
        guard let keyString = keyMap[keycode] else {
            throw Error.invalidTool(name: "pressKeycode", message: "Unsupported keycode: \(keycode)")
        }
        guard let app = self.app else {
            throw Error.noAppFound
        }
        // Find the focused element
        let focusedElement = app.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
        guard focusedElement.exists else {
            throw Error.invalidTool(name: "pressKeycode", message: "No element has keyboard focus.")
        }
        print("Typing key for keycode \(keycode): \(keyString)")
        focusedElement.typeText(keyString)
    }
    
    @MainActor
    func takeScreenshot() throws -> Data {
        let snapshot = XCUIScreen.main.screenshot()
        
        /*guard let app else {
         throw Error.noAppFound
         }
         let snapshot = app.screenshot()*/
        
        return snapshot.pngRepresentation
    }
    
    @MainActor
    func back() throws {
        guard let app = self.app else {
            throw Error.noAppFound
        }
        // Try to tap the navigation bar back button
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists && backButton.isHittable {
            print("Tapping navigation bar back button")
            backButton.tap()
            return
        }
        // If not, try a right-edge swipe gesture (from left edge to right)
        let window = app.windows.element(boundBy: 0)
        if window.exists {
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            print("Performing right-edge swipe gesture for back navigation")
            start.press(forDuration: 0.1, thenDragTo: end)
            return
        }
        throw Error.invalidTool(name: "back", message: "No back navigation available.")
    }
}
