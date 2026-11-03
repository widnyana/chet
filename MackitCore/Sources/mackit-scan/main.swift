// Read-only scan benchmark: per-step wall time, files seen, peak RSS, GPU buffer time.
// Exits 1 over the limits: peak RSS > 1.5 GB, longest GPU command buffer > 50 ms.
import Darwin
import Foundation
import MackitCore

func peakRSS() -> Int64 {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Int64(usage.ru_maxrss)  // macOS: bytes
}

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSHomeDirectory()
let home = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
let session = ScanSession(home: home)
let start = Date()
var stepStart = Date()
var stepTimes: [(String, TimeInterval)] = []

for await event in session.events() {
    switch event {
    case .started: stepStart = Date()
    case .finished(let step): stepTimes.append((step.title, Date().timeIntervalSince(stepStart)))
    default: break
    }
}

let total = Date().timeIntervalSince(start)
let rss = peakRSS()
let gpuSeconds = GPUContext.shared?.maxGPUSeconds ?? 0
let limitRSS: Int64 = 1_500_000_000
let limitGPU = 0.05

print("Mackit scan benchmark over \(home.path)")
for (title, seconds) in stepTimes {
    print(String(format: "  %-40s %6.2fs", (title as NSString).utf8String!, seconds))
}
print(
    String(
        format: "Total %6.2fs, files seen %d, bytes seen %@", total, session.progress.files,
        session.progress.bytes.formatted(.byteCount(style: .file))))
print("Peak RSS: \(rss.formatted(.byteCount(style: .file))) (limit \(limitRSS.formatted(.byteCount(style: .file))))")
print("Longest GPU command buffer: \(String(format: "%.1f", gpuSeconds * 1000)) ms (limit 50 ms)")
if rss > limitRSS {
    print("FAIL: peak RSS over limit")
    exit(1)
}
if gpuSeconds > limitGPU {
    print("FAIL: GPU command buffer over limit")
    exit(1)
}
