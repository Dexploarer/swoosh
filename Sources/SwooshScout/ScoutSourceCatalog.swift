// SwooshScout/ScoutSourceCatalog.swift — Operational Scout source catalog

import Foundation

public enum ScoutSourceCatalog {
    public static func operationalLocalSources(folderURLs: [URL] = []) -> [any ScoutSource] {
        var sources: [any ScoutSource] = [
            DeviceSource(),
            InstalledAppsSource(),
            RunningAppsSource(),
            ShellEnvironmentSource(),
            AppUsageSource(),
            FocusModeSource(),
            CalendarSource(),
            RemindersSource(),
            RecentDocumentsSource(),
        ]

        #if os(iOS)
        sources.append(HealthSleepSource())
        #endif

        if !folderURLs.isEmpty {
            sources.append(ProjectFoldersSource(paths: folderURLs))
            sources.append(GitReposSource(paths: folderURLs))
        }

        return sources
    }

    public static func passiveLocalSources(signalStore: PersonalizationSignalStore) -> [any ScoutSource] {
        [
            DeviceSource(),
            InstalledAppsSource(),
            RunningAppsSource(),
            PersonalizationSignalSource(store: signalStore),
            AppUsageSource(),
            FocusModeSource(),
            CalendarSource(),
            RemindersSource(),
            RecentDocumentsSource(),
        ]
    }
}
