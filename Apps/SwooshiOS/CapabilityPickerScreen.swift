// Apps/SwooshiOS/CapabilityPickerScreen.swift
// Version: 0.9R
//
// Modality picker mirroring the layout of VoicePickerScreen. One section
// per modality (Vision, Translation, Embeddings, Image generation) with
// a local/cloud badge, current provider, and a row per available choice.

import SwiftUI
import SwooshCapabilities

struct CapabilityPickerScreen: View {

    @State private var router = CapabilityRouter.shared

    var body: some View {
        List {
            visionSection
            translationSection
            embeddingSection
            imageGenSection
            videoGenSection
            threeDGenSection
            availabilityFooterSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Capabilities")
    }

    // MARK: - Video generation

    private var videoGenSection: some View {
        Section {
            ForEach(CapabilityRouter.VideoChoice.allCases) { choice in
                CapabilityChoiceRow(
                    title: choice.displayName,
                    isLocal: choice.isLocal,
                    isSelected: router.currentVideoChoice == choice
                ) {
                    router.currentVideoChoice = choice
                }
            }
        } header: {
            CapabilitySectionHeader(
                title: "Video generation",
                systemImage: "film",
                detail: "Text/image-to-video via FAL.ai (Veo 3, Kling, Hunyuan, Luma)."
            )
        } footer: {
            if !router.isVideoConfigured {
                Text("Add a FAL.ai API key in Settings → Voice → Provider keys (account 'fal') to enable video generation.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - 3D generation

    private var threeDGenSection: some View {
        Section {
            ForEach(CapabilityRouter.ThreeDChoice.allCases) { choice in
                CapabilityChoiceRow(
                    title: choice.displayName,
                    isLocal: choice.isLocal,
                    isSelected: router.currentThreeDChoice == choice
                ) {
                    router.currentThreeDChoice = choice
                }
            }
        } header: {
            CapabilitySectionHeader(
                title: "3D generation",
                systemImage: "cube.transparent",
                detail: "Text/image-to-3D via FAL.ai (Tripo3D, Trellis, TripoSR, Hunyuan3D)."
            )
        } footer: {
            if !router.isThreeDConfigured {
                Text("Add a FAL.ai API key in Settings → Voice → Provider keys (account 'fal') to enable 3D generation.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Vision

    private var visionSection: some View {
        Section {
            ForEach(CapabilityRouter.VisionChoice.allCases) { choice in
                CapabilityChoiceRow(
                    title: choice.displayName,
                    isLocal: choice.isLocal,
                    isSelected: router.currentVisionChoice == choice
                ) {
                    router.currentVisionChoice = choice
                }
            }
        } header: {
            CapabilitySectionHeader(
                title: "Vision",
                systemImage: "eye",
                detail: "OCR, depth, subject lift, document layout, face detection."
            )
        } footer: {
            Text("Apple Vision is on-device and free. No API keys required.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Translation

    private var translationSection: some View {
        Section {
            ForEach(CapabilityRouter.TranslationChoice.allCases) { choice in
                CapabilityChoiceRow(
                    title: choice.displayName,
                    isLocal: choice.isLocal,
                    isSelected: router.currentTranslationChoice == choice
                ) {
                    router.currentTranslationChoice = choice
                }
            }
        } header: {
            CapabilitySectionHeader(
                title: "Translation",
                systemImage: "character.bubble",
                detail: "Apple Translation on-device; cloud fallback for unsupported pairs."
            )
        } footer: {
            if !CapabilityAvailability.appleTranslationAvailable {
                Text("Apple Translation needs iOS 18 or newer.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Embeddings

    private var embeddingSection: some View {
        Section {
            ForEach(CapabilityRouter.EmbeddingChoice.allCases) { choice in
                CapabilityChoiceRow(
                    title: choice.displayName,
                    isLocal: choice.isLocal,
                    isSelected: router.currentEmbeddingChoice == choice
                ) {
                    router.currentEmbeddingChoice = choice
                }
            }
        } header: {
            CapabilitySectionHeader(
                title: "Embeddings",
                systemImage: "square.stack.3d.up",
                detail: "Semantic vectors for routing, dedup, and RAG."
            )
        } footer: {
            Text("Apple NaturalLanguage produces ~256-dim vectors locally. OpenAI provides 1536-dim vectors for higher fidelity.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Image generation

    private var imageGenSection: some View {
        Section {
            ForEach(CapabilityRouter.ImageGenChoice.allCases) { choice in
                CapabilityChoiceRow(
                    title: choice.displayName,
                    isLocal: choice.isLocal,
                    isSelected: router.currentImageGenChoice == choice
                ) {
                    router.currentImageGenChoice = choice
                }
            }
        } header: {
            CapabilitySectionHeader(
                title: "Image generation",
                systemImage: "paintpalette",
                detail: "Apple Image Playground on-device; OpenAI gpt-image-1 in the cloud."
            )
        } footer: {
            if !CapabilityAvailability.imagePlaygroundAvailable {
                Text("Image Playground needs iOS 18.2 or newer.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Availability footer

    private var availabilityFooterSection: some View {
        Section {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cloud fallback").font(.subheadline.weight(.semibold))
                    Text("Cloud providers only run when you've added an OpenAI key in Settings → Voice → Provider keys. The local-first router uses Apple frameworks when available and falls through to cloud automatically. Keys are stored in the iOS Keychain and rotate hot — replacing the key takes effect on the next call.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Helpers

struct CapabilitySectionHeader: View {
    let title: String
    let systemImage: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
    }
}

struct CapabilityChoiceRow: View {
    let title: String
    let isLocal: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(isLocal ? "On-device" : "Cloud")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if isLocal {
                    Text("LOCAL")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.green.opacity(0.15), in: Capsule())
                } else {
                    Text("CLOUD")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: Capsule())
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
