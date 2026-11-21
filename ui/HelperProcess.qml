import QtQuick
import Quickshell.Io

QtObject {
  id: root

  property int deadlineMs: 10000
  property int exitCode: -1
  property bool exited: false
  property bool streamDone: false
  property bool active: false
  readonly property bool busy: active

  signal finished(bool ok, string output)

  function start(command) {
    if (active) return false
    active = true
    exited = false
    streamDone = false
    exitCode = -1
    process.command = command
    process.running = true
    watchdog.restart()
    return true
  }

  function complete() {
    if (!exited || !streamDone) return
    watchdog.stop()
    active = false
    finished(exitCode === 0, process.stdout.text)
  }

  property Process process: Process {
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.streamDone = true
        root.complete()
      }
    }
    onExited: function(code) {
      root.exitCode = code
      root.exited = true
      root.complete()
    }
  }

  property Timer watchdog: Timer {
    interval: root.deadlineMs
    onTriggered: root.process.signal(9)
  }
}
