// Pure logic for the wormhole panel: helper command construction, protocol
// parsing, code validation, and the log ring buffer. Kept QML-free so it can
// be tested with node like the stock ReminderFlowModel.js.

function pluginDir(home) {
  return String(home || "") + "/.config/omarchy/plugins/dcchambers.omarchy-wormhole"
}

// Build the bash command for one of the helper's subcommands. Returns [] when
// the arguments are not usable (e.g. an invalid receive code).
function helperCommand(helperPath, mode, args, qrEnabled) {
  var command = ["bash", helperPath]

  if (mode === "send-clipboard") {
    command.push("send-clipboard")
    if (qrEnabled) command.push("--qr")
    return command
  }

  if (mode === "send") {
    var paths = args || []
    if (paths.length === 0) return []
    command.push("send")
    if (qrEnabled) command.push("--qr")
    return command.concat(paths)
  }

  if (mode === "receive") {
    var code = validateCode(args && args[0])
    if (!code) return []
    command.push("receive")
    command.push(code)
    return command
  }

  return []
}

// A wormhole code looks like "4-projection-alphabet": a number followed by
// dash-separated words. Squash case and whitespace before checking.
function validateCode(value) {
  var code = String(value || "").trim().toLowerCase()
  return /^[0-9]+(-[a-z0-9]+)+$/.test(code) ? code : ""
}

// Parse one helper protocol line into { key, value }. Unknown keys degrade to
// detail so the log still shows them.
function parseLine(line) {
  var text = String(line || "")
  var eq = text.indexOf("=")
  if (eq <= 0) return { key: "detail", value: text }
  var key = text.slice(0, eq)
  if (["code", "status", "done", "error", "confirm", "collision", "detail"].indexOf(key) === -1) {
    return { key: "detail", value: text }
  }
  return { key: key, value: text.slice(eq + 1) }
}

function appendLog(log, line, maxLines) {
  var lines = log ? log.split("\n") : []
  lines.push(line)
  var limit = maxLines || 200
  while (lines.length > limit) lines.shift()
  return lines.join("\n")
}

function tailLog(log, maxLines) {
  if (!log) return ""
  var lines = log.split("\n")
  var limit = maxLines || 8
  return lines.slice(Math.max(0, lines.length - limit)).join("\n")
}

if (typeof module !== "undefined") {
  module.exports = {
    pluginDir: pluginDir,
    helperCommand: helperCommand,
    validateCode: validateCode,
    parseLine: parseLine,
    appendLog: appendLog,
    tailLog: tailLog
  }
}
