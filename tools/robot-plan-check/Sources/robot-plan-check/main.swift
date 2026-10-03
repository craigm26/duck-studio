// Runs a duck-intent-plan on Pollen's real robotd over its Unix socket, through StudioKit's own
// LinePeer and RobotPlanRunner: the same code the app's "Run it on the duck" uses, minus the bridge.
//
//   scripts/duck-sim                                   # in a pollen-robotics/microduck checkout
//   swift run robot-plan-check ~/.cache/duck-sim/duck-a.sock plans/plan-walk-kick.json
//
// Linux only (Glibc sockets). It sends robot.enable first, as the pad's Start would; the app does
// not, and a duck whose policy is not driving refuses robot.do with that reason.
// First run 2026-10-03 against robotd 0.15.1: both plans finished, robotd logged each skill.
import Foundation
import Glibc
import StudioKit

let args = CommandLine.arguments
let path = args[1]
let plan = try DuckIntentPlan.read(Data(contentsOf: URL(fileURLWithPath: args[2])))

let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &addr.sun_path) { buf in
    for (i, b) in path.utf8.enumerated() { buf[i] = b }
}
let ok = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard ok == 0 else { print("connect failed: \(errno)"); exit(1) }

let inbound = AsyncStream<Data> { cont in
    Thread.detachNewThread {
        var buf = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { cont.finish(); return }
            cont.yield(Data(buf[0..<n]))
        }
    }
}
let log = FileHandle(forWritingAtPath: "/dev/stderr")!
let peer = LinePeer(identity: DuckIdentity(name: "duck-a (MuJoCo)", kind: .sim),
                    over: .bridge, inbound: inbound) { frame in
    let line = frame.line
    if let s = String(data: line, encoding: .utf8), !s.contains("robot.move") {
        log.write(Data("-> \(s)".utf8))
    }
    _ = line.withUnsafeBytes { send(fd, $0.baseAddress, line.count, 0) }
}
Task { await peer.read() }

let hello = try await peer.call(.hello)
print("hello:", String(data: hello.result ?? Data(), encoding: .utf8) ?? "?")
let skills = try await peer.call(.skills)
print("skills:", String(data: skills.result ?? Data(), encoding: .utf8) ?? "?",
      skills.failure?.says ?? "")
let enable = try await peer.call(.enable)
print("enable:", String(data: enable.result ?? Data(), encoding: .utf8) ?? "?", enable.failure?.says ?? "")
try await Task.sleep(nanoseconds: 4_000_000_000)

let robotPlan = try RobotPlan(plan)
for b in robotPlan.beats { print("beat:", RobotPlan.spelled(b)) }
let started = Date()
do {
    let outcome = try await RobotPlanRunner.run(
        robotPlan, on: peer, interval: 0.1,
        sleep: { try await Task.sleep(nanoseconds: UInt64($0 * 1e9)) },
        event: { e in print(String(format: "%6.2f s", Date().timeIntervalSince(started)), e) })
    print("outcome:", outcome)
} catch let r as RobotPlanRunner.Refusal {
    print("refused before moving:", r.message)
}
exit(0)
