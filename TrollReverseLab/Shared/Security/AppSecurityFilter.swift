//
//  AppSecurityFilter.swift
//  TrollReverseLab
//
//  Security filtering layer: ensures only user-selected TrollStore apps
//  are accessible for local research. Blocks system processes, App Store
//  apps, and any non-explicitly-selected targets.
//
//  CONSTRAINT: This tool is for personal local iOS reverse engineering
//  learning only. No global injection, no payment bypass, no online cheating.
//

import Foundation

/// Security filter that validates which apps can be targeted for local research.
/// All checks are conservative — deny by default, allow only with explicit user selection.
public final class AppSecurityFilter {

    public static let shared = AppSecurityFilter()

    // MARK: - Blocked bundle identifiers (system core processes)
    private let blockedSystemBundles: Set<String> = [
        "com.apple.springboard",
        "com.apple.mobilephone",
        "com.apple.MobileSMS",
        "com.apple.mobilesafari",
        "com.apple.Preferences",
        "com.apple.AppStore",
        "com.apple.apple-account",
        "com.apple.passbook",
        "com.apple.Health",
        "com.apple.mobilemail",
        "com.apple.mobiletimer",
        "com.apple.camera",
        "com.apple.photos",
        "com.apple.findmy",
        "com.apple.applepay"
    ]

    private init() {}

    // MARK: - Public API

    /// Validates whether a given app container is eligible for local research.
    /// - Parameters:
    ///   - bundleIdentifier: The app's bundle ID
    ///   - containerPath: The sandbox container path
    ///   - isUserSelected: Whether the user explicitly selected this app
    /// - Returns: Validation result with reason if denied
    public func validateTarget(
        bundleIdentifier: String,
        containerPath: String,
        isUserSelected: Bool
    ) -> SecurityValidationResult {

        // Rule 1: User must explicitly select the app
        guard isUserSelected else {
            return .denied(reason: "App was not explicitly selected by the user. Only manually chosen apps are allowed for local research.")
        }

        // Rule 2: Block system core processes
        if blockedSystemBundles.contains(bundleIdentifier) {
            return .denied(reason: "System core process '\(bundleIdentifier)' is blocked. This tool does not target system processes.")
        }

        // Rule 3: Block Apple system apps by bundle prefix
        if bundleIdentifier.hasPrefix("com.apple.") {
            return .denied(reason: "Apple system applications are blocked. Only TrollStore-installed apps are eligible.")
        }

        // Rule 4: Verify container path is in the expected location
        guard containerPath.contains("/var/mobile/Containers/Data/Application/") else {
            return .denied(reason: "Container path is not in the standard application data directory.")
        }

        // Rule 5: Verify .appInfo.plist exists (TrollStore marker)
        let appInfoPath = (containerPath as NSString).appendingPathComponent(".appInfo.plist")
        guard FileManager.default.fileExists(atPath: appInfoPath) else {
            return .denied(reason: "No .appInfo.plist found — this does not appear to be a TrollStore application.")
        }

        return .allowed
    }

    /// Validates a Frida script before execution to ensure it does not
    /// contain prohibited patterns.
    public func validateScript(_ script: String) -> ScriptValidationResult {
        let lowered = script.lowercased()

        let prohibitedPatterns: [(pattern: String, reason: String)] = [
            ("skpayment", "Script references StoreKit payment APIs — payment bypass is prohibited."),
            ("productpurchase", "Script references in-app purchase APIs — payment bypass is prohibited."),
            ("receiptvalidat", "Script references receipt validation — payment bypass is prohibited."),
            ("skproductsrequest", "Script references product request APIs — payment bypass is prohibited."),
            ("iap", "Script references IAP — payment bypass is prohibited."),
            ("unlocak", "Script may reference unlock mechanisms — verify this is for local data format research only."),
            ("crack", "Script references cracking — commercial cracking is prohibited.")
        ]

        for (pattern, reason) in prohibitedPatterns {
            if lowered.contains(pattern) {
                return .rejected(reason: reason)
            }
        }

        return .approved
    }
}

// MARK: - Result Types

public enum SecurityValidationResult {
    case allowed
    case denied(reason: String)
}

public enum ScriptValidationResult {
    case approved
    case rejected(reason: String)
}
