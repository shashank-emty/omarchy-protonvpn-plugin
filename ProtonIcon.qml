import QtQuick
import QtQuick.Shapes
import qs.Commons

// The official Proton VPN mark, drawn as monochrome vector paths so it takes
// the bar's foreground colour instead of the brand gradient, plus a small
// lock badge that shows the tunnel state (locked = connected, unlocked =
// disconnected).
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property bool locked: false
  property bool showBadge: true
  property string fontFamily: Style.font.family
  property color badgeColor: Color.background

  // The source logo lives in a viewBox of x -26.7..984.4, y -8.1..887.3
  // (width 1011.1, height 895.4). Fit to the icon by width and centre the
  // leftover height.
  readonly property real s: root.iconSize / 1011.1

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Shape {
    id: mark
    width: root.iconSize
    height: root.iconSize
    x: 26.7 * root.s
    y: 8.1 * root.s + (root.iconSize - 895.4 * root.s) / 2
    transform: Scale {
      xScale: root.s
      yScale: root.s
      origin.x: 0
      origin.y: 0
    }
    smooth: true
    antialiasing: true

    ShapePath {
      fillColor: root.color
      strokeColor: "transparent"
      PathSvg { path: "M385.6 818.1c36.5 65.6 130.2 69.2 171.6 6.6l386.3-583.9c40.9-61.9 1.7-144.9-72.4-153.3L111.9 1.1C30.9-8.1-26.7 77.3 12.7 148l3.1 5.5 338.7 232-4.1 369.1z" }
    }

    ShapePath {
      fillColor: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.55)
      strokeColor: "transparent"
      PathSvg { path: "M407.4 757l34.2-51.1L702 312.7c22.8-34.3 1.1-80.4-40.1-85.2L15.7 153.4l334.7 601.5c12.2 21.5 43.1 22.7 57 2.1z" }
    }
  }

  Item {
    id: badge
    visible: root.showBadge && root.iconSize >= 12
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    width: root.iconSize * 0.5
    height: width

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: root.badgeColor
    }

    Text {
      anchors.centerIn: parent
      text: root.locked ? "\uF033E" : "\uF033F"
      color: root.color
      font.family: root.fontFamily
      font.pixelSize: parent.height * 0.72
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }
  }
}
