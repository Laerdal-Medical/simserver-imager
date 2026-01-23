import QtQuick
import QtQuick.Layouts
import RpiImager

// Reusable badge component for labels/tags
Rectangle {
    id: root

    readonly property int styleFontSizeSmall: Style.fontSizeSmall
    readonly property string styleFontFamily: Style.fontFamily

    // Badge type - sets both text and variant automatically
    // Supported types: "ci", "release", "spu", "wic", "vsi"
    // Or use text/variant properties directly for custom badges
    property string type: ""

    // Badge text and accessibility (auto-set from type if not specified)
    property string text: {
        switch (type) {
            case "ci":      return qsTr("CI Build")
            case "release": return qsTr("Release")
            case "spu":     return "SPU"
            case "wic":     return "WIC"
            case "vsi":     return "VSI"
            default:        return ""
        }
    }
    property string accessibleName: text

    // Predefined color variants (auto-set from type if not specified)
    // Use 'variant' for predefined colors, or set 'color' directly for custom
    property string variant: {
        switch (type) {
            case "ci":      return "purple"
            case "release": return "green"
            case "spu":     return "indigo"
            case "wic":     return "emerald"
            case "vsi":     return "cyan"
            default:        return "default"
        }
    }

    // Size
    Layout.preferredHeight: badgeText.implicitHeight + 4
    Layout.preferredWidth: badgeText.implicitWidth + 8
    radius: 3

    color: {
        switch (variant) {
            // GitHub-style colors
            case "purple":  return "#6f42c1"  // CI builds, artifacts
            case "green":   return "#28a745"  // Releases, success
            case "blue":    return "#0366d6"  // Info, links
            case "red":     return "#cb2431"  // Errors, critical
            case "yellow":  return "#dbab09"  // Caution
            // Image type colors (Tailwind-inspired)
            case "indigo":  return "#6366f1"  // SPU (firmware updates)
            case "emerald": return "#10b981"  // WIC (disk images)
            case "cyan":    return "#06b6d4"  // VSI (versioned sparse images)
            // Neutral
            case "gray":    return "#6a737d"
            default:        return "#6a737d"
        }
    }

    Text {
        id: badgeText
        anchors.centerIn: parent
        text: root.text
        font.pixelSize: root.styleFontSizeSmall - 1
        font.family: root.styleFontFamily
        color: "white"
        Accessible.ignored: true
    }

    Accessible.role: Accessible.StaticText
    Accessible.name: root.accessibleName
}
