import QtQuick
import QtQuick.Shapes
import qs.Commons

// Proton VPN's mark: a pointy-top hexagon with a vertical keyhole line
// through the middle. Drawn as shapes so it inherits the bar's foreground
// color instead of shipping a fixed-colour asset.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color backgroundColor: Color.background

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    ShapePath {
      fillColor: root.color
      strokeWidth: 0
      startX: root.width * 0.5
      startY: root.height * 0.02

      PathLine { x: root.width * 0.93; y: root.height * 0.27 }
      PathLine { x: root.width * 0.93; y: root.height * 0.73 }
      PathLine { x: root.width * 0.5; y: root.height * 0.98 }
      PathLine { x: root.width * 0.07; y: root.height * 0.73 }
      PathLine { x: root.width * 0.07; y: root.height * 0.27 }
      PathLine { x: root.width * 0.5; y: root.height * 0.02 }
    }

    // The vertical keyhole: a narrow rounded slot down the middle, drawn in
    // the panel background so the hexagon reads as the Proton VPN mark.
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.backgroundColor
      strokeWidth: root.width * 0.13
      strokeStyle: ShapePath.RoundCap
      startX: root.width * 0.5
      startY: root.height * 0.32

      PathLine { x: root.width * 0.5; y: root.height * 0.68 }
    }
  }
}