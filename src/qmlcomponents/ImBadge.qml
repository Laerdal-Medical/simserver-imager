import QtQuick
import QtQuick.Layouts

// Reusable badge component for labels/tags
Rectangle {
    id: root

    // Badge text and accessibility
    property string text: ""
    property string accessibleName: text

    // Predefined color variants
    // Use 'variant' for predefined colors, or set 'color' directly for custom
    property string variant: "default"

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
        font.pixelSize: Style.fontSizeSmall - 1
        font.family: Style.fontFamily
        color: "white"
        Accessible.ignored: true
    }

    Accessible.role: Accessible.StaticText
    Accessible.name: root.accessibleName
}
