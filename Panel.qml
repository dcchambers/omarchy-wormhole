import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "wormhole-model.js" as WormholeModel

Panel {
  id: root
  moduleName: "dcchambers.omarchy-wormhole"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property string helperPath: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/dcchambers.omarchy-wormhole/helper.sh"

  property string step: "picker"
  property string mode: ""
  property int selectedIndex: 0
  property bool qrEnabled: false
  property string receiveCode: ""
  property string code: ""
  property string statusLine: ""
  property string resultMessage: ""
  property string errorMessage: ""
  property string logText: ""
  property bool expectedStop: false
  readonly property bool transferActive: wormholeProcess.running

  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property color foreground: root.barForeground
  readonly property color borderColor: Color.popups.border
  readonly property color selectedBackground: Style.selectedFillFor(root.foreground, Color.accent)
  readonly property int rowHeight: Math.max(Style.space(58), Style.font.title + Style.font.body + Style.space(12))
  readonly property int desiredWidth: root.qrEnabled
    && (root.step === "run" || root.step === "done" || root.step === "error")
    ? Style.space(560)
    : Style.space(440)
  readonly property int desiredHeight: {
    if (root.step === "picker") return root.rowHeight * 4 + Style.space(52)
    if (root.step === "sendType") return root.rowHeight * 3 + Style.space(52)
    if (root.step === "receiveInput") return Style.space(180)
    if (root.step === "choosing") return Style.space(100)
    if (root.qrEnabled) return Style.space(620)
    return Style.space(420)
  }

  property var modeRows: [
    { modeId: "send", icon: "󰈊", title: "Send files or a folder", description: "Choose what to share" },
    { modeId: "send-clipboard", icon: "󰅇", title: "Send clipboard", description: "Send the current clipboard as text" },
    { modeId: "receive", icon: "󰇚", title: "Receive", description: "Enter a wormhole code" }
  ]

  property var sendRows: [
    { modeId: "files", icon: "", title: "Files", description: "Choose one or more files" },
    { modeId: "folder", icon: "", title: "Folder", description: "Choose one folder" }
  ]

  function open() {
    if (!root.transferActive && (root.step === "done" || root.step === "error"))
      root.reset()
    root.controller.show()
    root.focusCurrentStep()
  }

  function close() {
    root.controller.hide()
  }

  function closeForPopoutSwitch() {
    root.popoutSwitchClosing = true
    root.close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function reset() {
    root.step = "picker"
    root.mode = ""
    root.selectedIndex = 0
    root.receiveCode = ""
    root.code = ""
    root.statusLine = ""
    root.resultMessage = ""
    root.errorMessage = ""
    root.logText = ""
  }

  function focusCurrentStep() {
    Qt.callLater(function() {
      if (!root.opened) return
      if (root.step === "receiveInput") receiveInput.forceActiveFocus()
      else keyCatcher.forceActiveFocus()
    })
  }

  function rowsForStep() {
    return root.step === "sendType" ? root.sendRows : root.modeRows
  }

  function select(delta) {
    var rows = root.rowsForStep()
    root.selectedIndex = (root.selectedIndex + delta + rows.length) % rows.length
  }

  function activateSelected() {
    if (root.step === "picker") {
      var modeId = root.modeRows[root.selectedIndex].modeId
      if (modeId === "send") {
        root.step = "sendType"
        root.selectedIndex = 0
      } else if (modeId === "receive") {
        root.mode = "receive"
        root.step = "receiveInput"
        root.receiveCode = ""
      } else {
        root.mode = modeId
        root.launchHelper(modeId, [])
      }
      root.focusCurrentStep()
      return
    }

    if (root.step === "sendType") {
      var sendMode = root.sendRows[root.selectedIndex].modeId
      root.openChooser(sendMode === "folder")
      return
    }

    if (root.step === "run" && root.code)
      root.copyCommand()
  }

  function goBack() {
    if (root.step === "sendType" || root.step === "receiveInput") {
      root.step = "picker"
      root.selectedIndex = 0
      root.receiveCode = ""
      root.errorMessage = ""
      root.focusCurrentStep()
    } else {
      root.close()
    }
  }

  function openChooser(directory) {
    if (fileChooser.running) return
    root.mode = "send"
    root.step = "choosing"
    var args = [root.omarchyPath + "/bin/omarchy-file-select", "--title",
      directory ? "Send folder with Wormhole" : "Send files with Wormhole"]
    if (directory) args.push("--directory")
    else args.push("--multiple")
    fileChooser.command = args
    // KeyboardPanel is an overlay-layer surface; release it before opening a
    // normal portal window so the chooser can receive pointer and keyboard.
    root.controller.hide()
    fileChooser.running = true
  }

  function handleChooserExit(exitCode) {
    var output = String(chooserStdout.text || "").trim()
    var error = String(chooserStderr.text || "").trim()
    if (exitCode === 1) {
      root.step = "sendType"
      root.selectedIndex = 0
      root.open()
      return
    }
    if (exitCode !== 0) {
      root.showError(error || "The file chooser did not open")
      return
    }
    if (!output) {
      root.step = "sendType"
      root.selectedIndex = 0
      root.open()
      return
    }
    root.launchHelper("send", output.split("\n"))
  }

  function launchHelper(modeId, args) {
    if (root.transferActive) return
    var command = WormholeModel.helperCommand(root.helperPath, modeId, args, root.qrEnabled)
    if (command.length === 0) {
      root.showError("Invalid wormhole command")
      return
    }
    root.code = ""
    root.statusLine = "Starting wormhole..."
    root.resultMessage = ""
    root.errorMessage = ""
    root.logText = ""
    root.expectedStop = false
    root.step = "run"
    wormholeProcess.command = command
    wormholeProcess.running = true
    root.controller.show()
    root.focusCurrentStep()
  }

  function receive() {
    var valid = WormholeModel.validateCode(root.receiveCode)
    if (!valid) {
      root.errorMessage = "Expected a code like 4-projection-alphabet"
      return
    }
    root.errorMessage = ""
    root.launchHelper("receive", [valid])
  }

  function consumeLine(line) {
    if (root.expectedStop) return
    var record = WormholeModel.parseLine(line)
    if (record.key === "code") root.code = record.value
    else if (record.key === "status") root.statusLine = record.value
    else if (record.key === "done") {
      if (record.value !== "complete" || !root.resultMessage)
        root.resultMessage = record.value
    } else if (record.key === "error") root.errorMessage = record.value
    else root.logText = WormholeModel.appendLog(root.logText, record.value, 200)
  }

  function showError(message) {
    root.errorMessage = message
    root.statusLine = ""
    root.step = "error"
    root.controller.show()
    root.focusCurrentStep()
  }

  function copyCommand() {
    if (!root.code) return
    var command = "wormhole receive " + root.code
    Quickshell.execDetached(["wl-copy", command])
    Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-notification-send", "Copied", command])
  }

  function cancelTransfer() {
    if (!root.transferActive) return
    root.expectedStop = true
    root.statusLine = "Cancelling transfer..."
    autoClose.stop()
    wormholeProcess.running = false
  }

  Process {
    id: fileChooser
    stdout: StdioCollector { id: chooserStdout; waitForEnd: true }
    stderr: StdioCollector { id: chooserStderr; waitForEnd: true }
    onExited: function(exitCode) { root.handleChooserExit(exitCode) }
  }

  Process {
    id: wormholeProcess
    stdout: SplitParser {
      onRead: function(line) { root.consumeLine(line) }
    }
    onExited: function(exitCode) {
      root.statusLine = ""
      if (root.expectedStop) {
        root.reset()
        root.focusCurrentStep()
        return
      }
      if (exitCode === 0) {
        root.step = "done"
        if (!root.resultMessage || root.resultMessage === "complete")
          root.resultMessage = "Transfer complete"
        autoClose.start()
      } else {
        root.showError(root.errorMessage || "wormhole exited with status " + exitCode)
      }
    }
  }

  Timer {
    id: autoClose
    interval: 2500
    onTriggered: root.close()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.desiredWidth)
    contentHeight: panel.fittedContentHeight(root.desiredHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.step === "receiveInput" && receiveInput.activeFocus

      onMoveRequested: function(dx, dy) {
        if ((root.step === "picker" || root.step === "sendType") && dy !== 0)
          root.select(dy)
      }
      onActivateRequested: root.activateSelected()
      onCloseRequested: root.goBack()
      onDeleteRequested: if (root.transferActive) root.cancelTransfer()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if ((root.step === "picker" || root.step === "sendType") && text.toLowerCase() === "q")
          root.qrEnabled = !root.qrEnabled
      }

      Column {
        anchors.fill: parent
        spacing: Style.space(8)

        Text {
          width: parent.width
          height: Style.space(36)
          verticalAlignment: Text.AlignVCenter
          text: root.step === "picker" ? "Magic Wormhole"
            : root.step === "sendType" ? "What are you sending?"
            : root.step === "receiveInput" ? "Enter wormhole code"
            : root.step === "choosing" ? "Choose what to send"
            : root.step === "done" ? "Transfer complete"
            : root.step === "error" ? "Transfer failed"
            : root.mode === "receive" ? "Receiving" : "Sending"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }

        Item {
          width: parent.width
          height: parent.height - Style.space(44)

          Column {
            width: parent.width
            visible: root.step === "picker" || root.step === "sendType"
            spacing: Style.space(4)

            Repeater {
              model: root.rowsForStep()

              Rectangle {
                required property int index
                required property var modelData
                width: parent.width
                height: root.rowHeight
                radius: Style.cornerRadius
                color: index === root.selectedIndex ? root.selectedBackground : "transparent"

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(10)

                  Text {
                    width: Style.space(26)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.icon
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    horizontalAlignment: Text.AlignHCenter
                  }

                  Column {
                    width: parent.width - Style.space(36)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      text: modelData.title
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                    }
                    Text {
                      text: modelData.description
                      color: root.foreground
                      opacity: 0.62
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.selectedIndex = index
                  onClicked: {
                    root.selectedIndex = index
                    root.activateSelected()
                  }
                }
              }
            }

            Rectangle {
              width: parent.width
              height: root.rowHeight
              visible: root.step === "picker" || root.step === "sendType"
              radius: Style.cornerRadius
              color: "transparent"
              border.color: root.borderColor
              border.width: Math.max(1, Style.normalBorderWidth)

              Text {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                verticalAlignment: Text.AlignVCenter
                text: "QR code for sends: " + (root.qrEnabled ? "On" : "Off") + "  (Q)"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.qrEnabled = !root.qrEnabled
              }
            }
          }

          Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: Style.space(8)
            visible: root.step === "receiveInput"

            Rectangle {
              width: parent.width
              height: Style.space(58)
              radius: Style.cornerRadius
              color: "transparent"
              border.color: root.borderColor
              border.width: Math.max(1, Style.normalBorderWidth)

              TextInput {
                id: receiveInput
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                verticalAlignment: TextInput.AlignVCenter
                text: root.receiveCode
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                selectByMouse: true
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                onTextEdited: root.receiveCode = text.toLowerCase()
                onAccepted: root.receive()
                Keys.onEscapePressed: function(event) {
                  root.goBack()
                  event.accepted = true
                }
              }

              Text {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                verticalAlignment: Text.AlignVCenter
                visible: !receiveInput.text && !receiveInput.activeFocus
                text: "4-projection-alphabet"
                color: root.foreground
                opacity: 0.4
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
              }
            }

            Text {
              width: parent.width
              text: root.errorMessage || "Received files are saved in ~/Downloads."
              color: root.foreground
              opacity: root.errorMessage ? 1 : 0.62
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }

          Text {
            anchors.centerIn: parent
            visible: root.step === "choosing"
            text: "Waiting for the file chooser..."
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }

          Column {
            anchors.fill: parent
            spacing: Style.space(8)
            visible: root.step === "run" || root.step === "done" || root.step === "error"

            Rectangle {
              width: parent.width
              height: root.code ? Style.space(74) : 0
              visible: root.code !== ""
              radius: Style.cornerRadius
              color: root.selectedBackground

              Column {
                anchors.fill: parent
                anchors.margins: Style.space(8)

                Text {
                  width: parent.width
                  text: "WORMHOLE CODE"
                  color: root.foreground
                  opacity: 0.65
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  width: parent.width
                  text: root.code
                  color: root.foreground
                  font.family: "monospace"
                  font.pixelSize: Style.font.heading
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.copyCommand()
              }
            }

            Text {
              width: parent.width
              height: root.step === "run" ? Style.space(24) : 0
              visible: root.step === "run"
              text: root.statusLine || "Working..."
              color: root.foreground
              opacity: 0.75
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Rectangle {
              width: parent.width
              height: root.step === "run" ? Style.space(42) : 0
              visible: root.step === "run"
              radius: Style.cornerRadius
              color: root.selectedBackground
              border.color: root.foreground
              border.width: Math.max(1, Style.normalBorderWidth)

              Text {
                anchors.centerIn: parent
                text: "Cancel transfer  (X)"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              MouseArea {
                anchors.fill: parent
                enabled: root.transferActive
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cancelTransfer()
              }
            }

            Rectangle {
              width: parent.width
              height: Math.max(Style.space(90), parent.height
                - (root.code ? Style.space(82) : 0)
                - (root.step === "run" ? Style.space(82) : 0)
                - (root.step === "done" || root.step === "error" ? Style.space(48) : 0))
              radius: Style.cornerRadius
              color: "transparent"
              border.color: root.borderColor
              border.width: Math.max(1, Style.normalBorderWidth)

              Flickable {
                anchors.fill: parent
                anchors.margins: Style.space(7)
                contentHeight: transferLog.implicitHeight
                contentY: Math.max(0, contentHeight - height)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Text {
                  id: transferLog
                  width: parent.width
                  text: WormholeModel.tailLog(root.logText, 30)
                  color: root.foreground
                  opacity: 0.7
                  font.family: "monospace"
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WrapAnywhere
                }
              }
            }

            Text {
              width: parent.width
              height: root.step === "done" || root.step === "error" ? Style.space(40) : 0
              visible: root.step === "done" || root.step === "error"
              verticalAlignment: Text.AlignVCenter
              text: root.step === "done"
                ? (root.resultMessage || "Transfer complete")
                : (root.errorMessage || "wormhole failed")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }
  }
}
