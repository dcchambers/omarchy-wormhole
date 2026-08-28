const assert = require("node:assert/strict")
const model = require("../wormhole-model.js")

assert.equal(model.validateCode(" 4-Projection-Alphabet "), "4-projection-alphabet")
assert.equal(model.validateCode("projection-alphabet"), "")

assert.deepEqual(
  model.helperCommand("/plugin/helper.sh", "send", ["/tmp/file one"], true),
  ["bash", "/plugin/helper.sh", "send", "--qr", "/tmp/file one"]
)
assert.deepEqual(
  model.helperCommand("/plugin/helper.sh", "receive", ["4-foo-bar"], false),
  ["bash", "/plugin/helper.sh", "receive", "4-foo-bar"]
)
assert.deepEqual(model.helperCommand("/plugin/helper.sh", "send", [], false), [])

assert.deepEqual(model.parseLine("code=4-foo-bar"), { key: "code", value: "4-foo-bar" })
assert.deepEqual(model.parseLine("unknown=value"), { key: "detail", value: "unknown=value" })
assert.equal(model.tailLog("1\n2\n3", 2), "2\n3")

console.log("wormhole-model tests passed")
