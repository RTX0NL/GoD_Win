# ATX - Animated Texture

ATX is the animated texture format, functioning as a sequence of GTX texture frames played back in order, similar to an animated GIF. It is used for animated UI elements, Pokemon sprite animations in menus, and other looping visual effects.

## Identification

| Property | Value |
|----------|-------|
| Type ID | `0x32` |
| Byte Order | Big-endian |

## Structure

An ATX file contains multiple GTX texture frames stored sequentially. Each frame uses the same underlying texture encoding as standalone GTX files (see GTX format documentation for pixel format details, dimensions, and mipmap handling).

The frames are played back in sequence at a fixed rate to produce the animation effect.

## Usage

- Animated Pokemon icons in party menus and storage boxes
- Animated UI elements (buttons, indicators, status icons)
- Looping background effects in menu screens

## Conversion

ATX files can be converted to and from PNG image sequences, where each frame is exported as a numbered PNG file. On import, the PNG sequence is re-encoded back into sequential GTX frames.

## Runtime

ATX textures are managed by the texture system alongside static GTX textures. The runtime handles frame advancement and looping during rendering.
