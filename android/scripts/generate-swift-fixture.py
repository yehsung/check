#!/usr/bin/env python3
"""Generate deterministic reference traces by running the repository's Swift rules.

Requires Swift on macOS. Only Apple UI declarations are stripped; game transitions,
physics, scoring and the RNG execute directly from Sources/CheckCore.
Commit the TSV so Kotlin CI can compare without an Apple SDK.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "Sources/CheckCore"


def remove_block(source, marker):
    start = source.index(marker)
    brace = source.index("{", start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[:start] + source[end:]


timing = (CORE / "TimingBarGame.swift").read_text()
timing = remove_block(timing, "    package enum Verdict:")
timing = remove_block(timing, "    package static func verdict(")
flappy = (CORE / "FlappyGame.swift").read_text()
flappy = "\n".join(line for line in flappy.splitlines() if "package var stage:" not in line)
engine = (CORE / "MiniGameEngine.swift").read_text()
random = engine[engine.index("package struct MiniGameRandom:"):engine.index("/// 프레임 루프가 실제로")]
stubs = """
import Foundation
import CoreGraphics
enum MiniGameCanvas {
    static let logicalWidth: CGFloat = 292
    static let logicalHeight: CGFloat = 302
}
enum MiniGameKind { case flappy; var maxScore: Int { 999 } }
"""
driver = r'''
func emit(_ values: [String]) { print(values.joined(separator: "\t")) }
for seed: UInt64 in [0, 42, 99, 122334] {
    var timing = TimingBarGame(seed: seed)
    for frame in 0..<1200 {
        if frame % 37 == 0 { timing.tap() }
        timing.step(dt: 1.0 / 60)
        if frame % 20 == 0 {
            var finished = false
            if case .finished = timing.phase { finished = true }
            emit(["timing", "\(seed)", "\(frame)", "\(timing.round)", "\(timing.total)",
                  "\(timing.markerPosition)", "\(timing.target.center)", "\(timing.target.width)",
                  "\(timing.isPlaying)", "\(finished)"])
        }
    }
    var flappy = FlappyGame(seed: seed)
    for frame in 0..<3600 {
        if !flappy.isPlaying {
            flappy.flap()
        } else if case .running = flappy.phase {
            let pipe = flappy.pipes.first { $0.x + FlappyGame.pipeWidth >= flappy.bird.x - 12 }
            let target = pipe?.center(at: flappy.elapsed + 0.2) ?? FlappyGame.height / 2
            if flappy.bird.vy > 0 && flappy.bird.y > target { flappy.flap() }
        }
        flappy.step(dt: 1.0 / 60)
        if frame % 60 == 0 {
            var finished = false
            if case .result = flappy.phase { finished = true }
            emit(["flappy", "\(seed)", "\(frame)", "\(flappy.score)", "\(flappy.bird.y)",
                  "\(flappy.bird.vy)", "\(flappy.elapsed)", "\(flappy.pipes.first!.x)",
                  "\(flappy.pipes.first!.center(at: flappy.elapsed))", "\(flappy.isPlaying)", "\(finished)"])
        }
    }
}
'''
source = "\n".join([stubs, timing, flappy, random, driver]).replace("import SwiftUI", "").replace("package ", "")
with tempfile.TemporaryDirectory(prefix="aing-swift-") as directory:
    main = Path(directory) / "main.swift"
    main.write_text(source)
    command = ["swift", "-module-cache-path", str(Path(directory) / "cache")]
    if os.environ.get("SDKROOT"):
        command += ["-sdk", os.environ["SDKROOT"]]
    result = subprocess.run(command + [str(main)], text=True, capture_output=True)
    if result.returncode:
        raise SystemExit(result.stderr[:3000])
    output = result.stdout
target = ROOT / "android/core/src/test/resources/swift-trace.tsv"
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(output)
print(f"Generated {len(output.splitlines())} Swift reference snapshots: {target}")
