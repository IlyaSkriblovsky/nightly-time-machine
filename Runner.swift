import Foundation
import Darwin

// This executable accepts no command or script path from its caller.
let installedBundle = "/Library/PrivilegedHelperTools/local.nightly-time-machine/Nightly Time Machine.app"
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
if CommandLine.arguments.contains("--version") {
    print("Nightly Time Machine 1.0")
    exit(0)
}
guard CommandLine.arguments.count == 1 else { fail("No arguments are supported.") }
guard geteuid() == 0 else { fail("Run this application through its installed system service.") }
guard Bundle.main.bundlePath == installedBundle else { fail("Unexpected application location.") }

func securePath(_ path: String) -> Bool {
    var current = path
    while current != "/" {
        var s = stat()
        guard lstat(current, &s) == 0, s.st_uid == 0,
              (s.st_mode & 0o022) == 0,
              (s.st_mode & S_IFMT) != S_IFLNK else { return false }
        current = (current as NSString).deletingLastPathComponent
    }
    return true
}
let script = installedBundle + "/Contents/Resources/backup.sh"
guard securePath(script) else { fail("Application resources must be root-owned and not writable by other users.") }
let marker = "/var/db/local.nightly-time-machine/run-once-manual"
var args = [script]
if FileManager.default.fileExists(atPath: marker) {
    // /var is a standard macOS symlink, use the canonical path for validation.
    guard securePath("/private" + marker) else { fail("Insecure manual-run marker.") }
    do { try FileManager.default.removeItem(atPath: marker) }
    catch { fail("Cannot consume manual-run marker: \(error)") }
    args.append("--manual")
}
let child = Process()
child.executableURL = URL(fileURLWithPath: "/bin/bash")
child.arguments = args
child.currentDirectoryURL = URL(fileURLWithPath: "/")
// In particular, never inherit BASH_ENV, ENV or shell-function exports.
child.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"]
do { try child.run() } catch { fail("Cannot start backup: \(error)") }
child.waitUntilExit()
exit(child.terminationReason == .exit ? child.terminationStatus : 1)
