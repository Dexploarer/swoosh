// DetouriOSUserActivity.swift — proactive setup continuation (0.5A)

import Foundation

enum DetouriOSUserActivity {
    static let onboardingType = "ai.swoosh.detour.onboarding"

    static func makeOnboardingActivity(step: DetouriOSOnboardingStep) -> NSUserActivity {
        let activity = NSUserActivity(activityType: onboardingType)
        activity.title = "Continue Detour setup"
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.persistentIdentifier = NSUserActivityPersistentIdentifier(onboardingType)
        activity.targetContentIdentifier = onboardingType
        activity.userInfo = ["step": step.rawValue]
        activity.requiredUserInfoKeys = ["step"]
        activity.needsSave = true
        return activity
    }
}
