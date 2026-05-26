// DetourPersonalizationPlanningBuilder.swift — personalization setup services (0.5A)

import Foundation

@MainActor
extension DetourPersonalizationRunner {
    func goalCandidates(
        installedApps: Set<String>,
        git: GitActivityInventory,
        contacts: ContactInventory
    ) -> [DetourSetupCandidate] {
        var candidates = [
            candidate(
                id: "goal.daily-brief",
                category: .goal,
                title: "Daily brief from calendar, reminders, apps, and active threads",
                detail: "personal planning",
                source: "Scout",
                recommended: true
            ),
            candidate(
                id: "goal.memory-review",
                category: .goal,
                title: "Turn repeated behavior into approved memories",
                detail: "memory curation",
                source: "Scout",
                recommended: true
            ),
        ]
        if containsAny(["xcode", "visual studio code", "cursor"], in: installedApps) || !git.repositories.isEmpty {
            candidates.append(candidate(
                id: "goal.project-tracking",
                category: .goal,
                title: "Track active repos, PRs, and coding loops",
                detail: "developer workflow",
                source: "Git history",
                recommended: true
            ))
        }
        if containsAny(["slack", "discord", "telegram"], in: installedApps) || contacts.totalCount > 0 {
            candidates.append(candidate(
                id: "goal.conversation-followup",
                category: .goal,
                title: "Keep important conversations and people from getting lost",
                detail: "message connectors",
                source: "Contacts and apps",
                recommended: true
            ))
        }
        return candidates
    }

    func scheduleCandidates(
        installedApps: Set<String>,
        appUsage: AppUsageInventory,
        git: GitActivityInventory
    ) -> [DetourSetupCandidate] {
        var candidates = [
            candidate(
                id: "schedule.morning-context",
                category: .schedule,
                title: "Morning context refresh",
                detail: "daily",
                source: "onboarding",
                recommended: true
            ),
            candidate(
                id: "schedule.weekly-memory",
                category: .schedule,
                title: "Weekly memory review",
                detail: "weekly",
                source: "Scout",
                recommended: true
            ),
        ]
        if hasAppleProductivity(installedApps) {
            candidates.append(candidate(
                id: "schedule.calendar-planning",
                category: .schedule,
                title: "Calendar and reminders planning",
                detail: "daily",
                source: "Apple apps",
                recommended: true
            ))
        }
        if hasBrowser(installedApps) || !appUsage.topApps.isEmpty {
            candidates.append(candidate(
                id: "schedule.research-recap",
                category: .schedule,
                title: "Evening research recap",
                detail: "daily",
                source: "browser/app usage",
                recommended: true
            ))
        }
        if !git.repositories.isEmpty {
            candidates.append(candidate(
                id: "schedule.repo-scout",
                category: .schedule,
                title: "Active repo scan",
                detail: "daily",
                source: "Git history",
                recommended: true
            ))
        }
        return candidates
    }
}
