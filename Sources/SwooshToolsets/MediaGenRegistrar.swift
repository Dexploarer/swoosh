// SwooshToolsets/MediaGenRegistrar.swift — 0.4A Media generation tool registrar
//
// Extension on DefaultToolRegistrar that wires media-gen tools into a
// ToolRegistry. Lives separately from `Exports.swift` so the main
// registrar stays under the LOC ceiling and the media-gen seam is
// independent of the self-improvement pillar wiring.
//
// Each tool registers only when its matching provider is wired, so a
// daemon that has the OpenAI key but not the FAL key still exposes
// `media.generate_image` while skipping the video/3D tools — the
// model's catalog reflects what is actually runnable.

import Foundation
import SwooshTools

extension DefaultToolRegistrar {
    static func registerMediaGen(
        into registry: ToolRegistry,
        mediaGen: MediaGenDependencies
    ) async {
        let cacheDir = mediaGen.cacheDir ?? MediaCacheDir.default()
        if let image = mediaGen.imageProvider {
            await registry.register(TypeErasedTool(GenerateImageTool(provider: image, cacheDir: cacheDir)))
        }
        if let video = mediaGen.videoProvider {
            await registry.register(TypeErasedTool(GenerateVideoTool(provider: video, cacheDir: cacheDir)))
        }
        if let threeD = mediaGen.threeDProvider {
            await registry.register(TypeErasedTool(Generate3DTool(provider: threeD, cacheDir: cacheDir)))
        }
        if let music = mediaGen.musicProvider {
            await registry.register(TypeErasedTool(GenerateMusicTool(
                provider: music,
                cacheDir: cacheDir,
                downloader: mediaGen.audioDownloader ?? URLSessionAudioDownloader()
            )))
        }
    }
}
