# Brand

The shared visual language uses the brand spec's ink, violet, sand and paper colours,
rounded system typography, and a lightweight SwiftUI recreation of the stacked-card mark.
The canonical source artwork is `brand/blip-mark.svg`, also shown in the README.
Violet is reserved for the blip and interactive emphasis. The mark is drawn in code so it
works at Dynamic Type and does not add an image-loading dependency.

`blipScreen(_:titleStyle:)` is the single screen-theme boundary: it applies the
navigation title, rounded typography, tint, paper surface, and hides opaque List/Form
canvases. Pushed and sheet screens retain native contextual or inline titles. Root tabs
use a shared SwiftUI large heading below an inline navigation bar, bypassing the native
large-title host because it produces a zero-height render surface on the current target.
Content headings use Nunito.
