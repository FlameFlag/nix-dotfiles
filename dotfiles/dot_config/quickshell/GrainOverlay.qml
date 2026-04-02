import QtQuick

// Grain texture overlay — ported from flameflag-site's repeating-conic-gradient.
// Renders a 4×4 px dot grid via Canvas that mimics the CSS pattern:
//   repeating-conic-gradient(rgba(0,0,0,0.03) 0% 25%, transparent 0% 50%)
// Layered with a top-to-bottom lighting gradient for depth.
Canvas {
    id: grain
    anchors.fill: parent

    property real dotOpacity: Theme.grainOpacity

    renderStrategy: Canvas.Cooperative
    onPaint: {
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        // Dot grid — 4px tiles, top-left quadrant filled
        ctx.fillStyle = Qt.rgba(0, 0, 0, dotOpacity);
        for (var y = 0; y < height; y += 4) {
            for (var x = 0; x < width; x += 4) {
                ctx.fillRect(x, y, 2, 2);
            }
        }

        // Lighting gradient — bright top, dark bottom (depth cue)
        var grad = ctx.createLinearGradient(0, 0, 0, height);
        grad.addColorStop(0, Qt.rgba(1, 1, 1, 0.08));
        grad.addColorStop(0.5, "transparent");
        grad.addColorStop(1, Qt.rgba(0, 0, 0, 0.06));
        ctx.fillStyle = grad;
        ctx.fillRect(0, 0, width, height);
    }

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
}
