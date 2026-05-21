// SwooshDaemon/DaemonRuntime.swift — Long-lived daemon resources
import Foundation
import SwooshCron
import SwooshGoals
import SwooshManifesting
import SwooshScout
import SwooshSkills

struct DaemonRuntime: Sendable {
    let skillStore: FileSkillStore
    let goalStore: FileGoalStore
    let manifestStore: FileManifestationStore
    let manifester: Manifester
    let goalRunner: GoalRunner
    let appUsageRecorder: AppUsageRecorder
    let personalizationSignals: PersonalizationSignalStore
    let scoutAutopilotTask: Task<Void, Never>
    let manifestationTask: Task<Void, Never>
    let goalAutopilotTask: Task<Void, Never>
    let cronStore: FileCronJobStore
    let cronScheduler: CronScheduler
    let cronTask: Task<Void, Never>

    func stop() async {
        scoutAutopilotTask.cancel()
        manifestationTask.cancel()
        goalAutopilotTask.cancel()
        cronTask.cancel()
        await appUsageRecorder.stop()
    }
}
