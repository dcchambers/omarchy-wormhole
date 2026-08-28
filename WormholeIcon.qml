import QtQuick
import QtQuick.Shapes

Item {
  id: root

  property color iconColor: "white"
  readonly property real size: Math.min(width, height)

  Shape {
    anchors.fill: parent
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer

    // One continuous line curls from the outer rim into the singularity.
    ShapePath {
      strokeWidth: Math.max(1.5, root.size * 0.11)
      strokeColor: root.iconColor
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      startX: root.width * 0.88
      startY: root.height * 0.48

      PathCubic {
        control1X: root.width * 0.86
        control1Y: root.height * 0.18
        control2X: root.width * 0.68
        control2Y: root.height * 0.10
        x: root.width * 0.48
        y: root.height * 0.10
      }
      PathCubic {
        control1X: root.width * 0.22
        control1Y: root.height * 0.10
        control2X: root.width * 0.10
        control2Y: root.height * 0.28
        x: root.width * 0.10
        y: root.height * 0.50
      }
      PathCubic {
        control1X: root.width * 0.10
        control1Y: root.height * 0.74
        control2X: root.width * 0.27
        control2Y: root.height * 0.87
        x: root.width * 0.50
        y: root.height * 0.87
      }
      PathCubic {
        control1X: root.width * 0.70
        control1Y: root.height * 0.87
        control2X: root.width * 0.79
        control2Y: root.height * 0.70
        x: root.width * 0.79
        y: root.height * 0.52
      }
      PathCubic {
        control1X: root.width * 0.79
        control1Y: root.height * 0.34
        control2X: root.width * 0.66
        control2Y: root.height * 0.26
        x: root.width * 0.50
        y: root.height * 0.26
      }
      PathCubic {
        control1X: root.width * 0.36
        control1Y: root.height * 0.26
        control2X: root.width * 0.30
        control2Y: root.height * 0.38
        x: root.width * 0.30
        y: root.height * 0.50
      }
      PathCubic {
        control1X: root.width * 0.30
        control1Y: root.height * 0.61
        control2X: root.width * 0.39
        control2Y: root.height * 0.68
        x: root.width * 0.50
        y: root.height * 0.68
      }
      PathCubic {
        control1X: root.width * 0.60
        control1Y: root.height * 0.68
        control2X: root.width * 0.65
        control2Y: root.height * 0.60
        x: root.width * 0.65
        y: root.height * 0.51
      }
      PathCubic {
        control1X: root.width * 0.65
        control1Y: root.height * 0.44
        control2X: root.width * 0.59
        control2Y: root.height * 0.40
        x: root.width * 0.52
        y: root.height * 0.40
      }
    }
  }
}
