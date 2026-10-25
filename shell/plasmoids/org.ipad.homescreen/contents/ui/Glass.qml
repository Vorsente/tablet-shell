// Liquid Glass surface (iOS 26): a translucent fill, a light rim and a soft highlight along the top
// edge. Content goes on top as children.
//   tone "wallpaper": dark glass straight on the wallpaper (buttons, page dots), white content
//   tone "light":     frosted white glass on the wallpaper (folders)
//   tone "card":      widget / sheet card colours of the current light or dark look
//   tone "fill":      a control on a card or sheet
// tinted: filled with the accent colour (Done, Add).
import QtQuick

Rectangle {
    id: glass

    required property var home
    property string tone: "wallpaper"
    property bool tinted: false
    property bool highlighted: false

    radius: home.pixel ? Math.min(height * 0.26, 28) : height / 2
    color: home.pixel ? (tinted ? home.pal.blue : tone === "wallpaper" ? "#322F3A" : tone === "light" ? home.pal.fill : tone === "fill" ? home.pal.fill : home.pal.card)
         : tinted ? home.pal.blue
         : tone === "card" ? home.pal.card
         : tone === "fill" ? home.pal.fill
         : tone === "light" ? Qt.rgba(1, 1, 1, home.dark ? 0.16 : 0.26)
         : Qt.rgba(0.08, 0.08, 0.1, home.dark ? 0.36 : 0.22)
    border.width: home.pixel ? (highlighted ? 2 : 0) : highlighted ? 1.5 : 1
    border.color: home.pixel ? home.pal.blue : highlighted ? Qt.rgba(1, 1, 1, home.dark ? 0.56 : 0.84)
                : tinted ? Qt.rgba(1, 1, 1, 0.36)
                : tone === "fill" ? home.pal.cardBorder
                : Qt.rgba(1, 1, 1, home.dark ? 0.24 : 0.5)

    GlassSheen {
        home: glass.home
        visible: !home.pixel
    }
}
