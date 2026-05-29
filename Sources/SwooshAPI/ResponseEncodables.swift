// SwooshAPI/ResponseEncodables.swift — 0.9S Server-side ResponseEncodable conformances
//
// `SwooshClient` defines the wire-format types but does not import
// Hummingbird (it has to build for iOS). This file is the bridge:
// every response type the API server returns gets a one-liner
// `ResponseEncodable` conformance here so the route handlers can
// `return someResponse` directly.

import Foundation
import Hummingbird
import SwooshClient

extension ChatResponse: ResponseEncodable {}
extension CodexAuthStatus: ResponseEncodable {}
extension TranscriptResponse: ResponseEncodable {}
extension APIErrorBody: ResponseEncodable {}
extension APIVersion: ResponseEncodable {}
extension AgentStatusResponse: ResponseEncodable {}
extension SwooshReadinessReport: ResponseEncodable {}
extension ProvidersResponse: ResponseEncodable {}
extension ProviderStatusResponse: ResponseEncodable {}
extension ProviderMutationResponse: ResponseEncodable {}
extension BoardCardsResponse: ResponseEncodable {}
extension BoardLanesResponse: ResponseEncodable {}
extension MetricsResponse: ResponseEncodable {}
extension AuditEventsResponse: ResponseEncodable {}
extension ApprovalsResponse: ResponseEncodable {}
extension ApprovalResolveResponse: ResponseEncodable {}
extension UsageResponse: ResponseEncodable {}
extension SkillsResponse: ResponseEncodable {}
extension ToolCatalogResponse: ResponseEncodable {}
extension MCPServersResponse: ResponseEncodable {}
extension LaunchpadsResponse: ResponseEncodable {}
extension LaunchpadPlatformResponse: ResponseEncodable {}
extension MemoriesResponse: ResponseEncodable {}
extension RecordsResponse: ResponseEncodable {}
extension MediaGalleryResponse: ResponseEncodable {}
extension ChatAdaptersResponse: ResponseEncodable {}
extension RuntimeConfigResponse: ResponseEncodable {}
extension RuntimeConfigMutationResponse: ResponseEncodable {}
extension WalletDashboardResponse: ResponseEncodable {}
extension PluginsResponse: ResponseEncodable {}
extension PluginDetailResponse: ResponseEncodable {}
extension PluginMutationResponse: ResponseEncodable {}
extension GoalsResponse: ResponseEncodable {}
extension GoalDetailResponse: ResponseEncodable {}
extension GoalMutationResponse: ResponseEncodable {}
extension ManifestationsResponse: ResponseEncodable {}
extension ManifestationDetailResponse: ResponseEncodable {}
extension SkillDetailResponse: ResponseEncodable {}
extension SkillMutationResponse: ResponseEncodable {}
extension MemoryDetailResponse: ResponseEncodable {}
extension MemoryMutationResponse: ResponseEncodable {}
extension ToolExecuteResponse: ResponseEncodable {}
extension MCPServerMutationResponse: ResponseEncodable {}
extension MCPServerToolsResponse: ResponseEncodable {}
extension FirewallResponse: ResponseEncodable {}
extension FirewallMutationResponse: ResponseEncodable {}
extension FirewallCheckResponse: ResponseEncodable {}
extension CronJobsResponse: ResponseEncodable {}
extension CronJobMutationResponse: ResponseEncodable {}
extension CalendarEventsResponse: ResponseEncodable {}
extension DoctorReportResponse: ResponseEncodable {}
extension WalletAccountsResponse: ResponseEncodable {}
extension WalletAccountResponse: ResponseEncodable {}
extension WalletBalanceResponse: ResponseEncodable {}
extension RebateSummaryResponse: ResponseEncodable {}
extension AnchorBatchesResponse: ResponseEncodable {}
