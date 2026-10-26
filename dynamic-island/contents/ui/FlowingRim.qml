import QtQuick 2.15

// Animated gradient rim around the pill. Extracted from main.qml (Phase 2).
// Stateless visual: receives the dominant color, hover state and geometry.
Canvas {
    id: rim

    property color dominantColor: Qt.rgba(0.08, 0.08, 0.08, 1.0)
    property bool hovered: false
    property real rimThickness: 5.5
    property real pillWidth: 0
    property real pillHeight: 0
    property bool pillActive: false

    width: pillWidth + rimThickness * 2
    height: pillHeight + rimThickness * 2

    property real gradientShift: 0

    transformOrigin: Item.Center
    scale: hovered ? 1.02 : 1.0
    Behavior on scale {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    function qmlColorToRgba(c, a = 1.0) {
        return `rgba(${Math.round(c.r * 255)}, ${Math.round(c.g * 255)}, ${Math.round(c.b * 255)}, ${a})`
    }

    function blendColors(c1, c2, ratio) {
        return Qt.rgba(
            c1.r * (1 - ratio) + c2.r * ratio,
            c1.g * (1 - ratio) + c2.g * ratio,
            c1.b * (1 - ratio) + c2.b * ratio,
            1
        )
    }

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()

        const w = pillWidth
        const h = pillHeight
        if (w <= 0 || h <= 0)
            return

        const r = h / 2 + 3
        const strokeInset = rimThickness

        ctx.translate(strokeInset, strokeInset)

        const dom = dominantColor
        const bright = qmlColorToRgba(Qt.lighter(dom, 2.2), 1.0)
        const mintAccent = Qt.rgba(0, 1, 0.8, 1)
        const purpAccent = Qt.rgba(0.6, 0.2, 0.9, 1)
        const goldAccent = Qt.rgba(1, 0.85, 0.3, 1)

        // Canvas addColorStop requires CSS color strings, not QColor
        const domMint = qmlColorToRgba(blendColors(dom, mintAccent, 0.2))
        const domPurp = qmlColorToRgba(blendColors(dom, purpAccent, 0.2))
        const domGold = qmlColorToRgba(blendColors(dom, goldAccent, 0.2))
        const mintPurp = qmlColorToRgba(blendColors(blendColors(dom, mintAccent, 0.2), blendColors(dom, purpAccent, 0.2), 0.4))
        const purpGold = qmlColorToRgba(blendColors(blendColors(dom, purpAccent, 0.2), blendColors(dom, goldAccent, 0.2), 0.4))

        const loopWidth = Math.max(w * 8, 1)
        const offset = gradientShift % loopWidth
        const gradient = ctx.createLinearGradient(-loopWidth + offset, 0, offset, 0)

        gradient.addColorStop(0.00, bright)
        gradient.addColorStop(0.15, domMint)
        gradient.addColorStop(0.30, bright)
        gradient.addColorStop(0.40, mintPurp)
        gradient.addColorStop(0.50, domPurp)
        gradient.addColorStop(0.60, purpGold)
        gradient.addColorStop(0.70, bright)
        gradient.addColorStop(0.85, domGold)
        gradient.addColorStop(1.00, bright)

        ctx.save()
        ctx.beginPath()
        ctx.moveTo(r, 0)
        ctx.lineTo(w - r, 0)
        ctx.quadraticCurveTo(w, 0, w, r)
        ctx.lineTo(w, h - r)
        ctx.quadraticCurveTo(w, h, w - r, h)
        ctx.lineTo(r, h)
        ctx.quadraticCurveTo(0, h, 0, h - r)
        ctx.lineTo(0, r)
        ctx.quadraticCurveTo(0, 0, r, 0)
        ctx.closePath()
        ctx.clip()

        ctx.strokeStyle = gradient
        ctx.lineWidth = rimThickness
        ctx.stroke()
        ctx.restore()
    }

    Timer {
        interval: 33
        running: rim.pillActive && rim.pillWidth > 0
        repeat: true
        onTriggered: {
            rim.gradientShift += 6
            rim.requestPaint()
        }
    }
}
