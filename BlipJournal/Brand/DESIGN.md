# Brand

The shared visual language uses the brand spec's ink, violet, sand and paper colours,
rounded system typography, and a lightweight SwiftUI recreation of the stacked-card mark.
The canonical source artwork is `brand/blip-mark.svg`, also shown in the README.
Violet is reserved for the blip and interactive emphasis. The mark is drawn in code so it
works at Dynamic Type and does not add an image-loading dependency.

`blipScreen(_:titleDisplayMode:)` is the single screen-theme boundary: it applies the
navigation title, rounded typography, tint, paper surface, and hides opaque List/Form
canvases. Root tabs explicitly request large titles; pushed and sheet screens keep the
platform's contextual title mode. Native navigation titles use a rounded system fallback
because UIKit's scroll-edge renderer does not reliably draw the bundled variable font;
content headings continue to use Nunito.
