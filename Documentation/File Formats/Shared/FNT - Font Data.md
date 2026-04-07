# FNT - Font Data

FNT is the font definition format containing character glyph data for text rendering. It is used by the GSmsg message system to display all in-game text including dialogue, menus, item descriptions, and battle messages.

## Identification

| Property | Value |
|----------|-------|
| Type ID | `0x0C` |
| Byte Order | Big-endian |

## Overview

FNT files contain bitmap glyph data and metric information for a character set. The games use a custom character encoding (GSchar) with conversion support for Shift-JIS (SJIS) for the Japanese versions.

## Runtime System (XD)

The GSmsg system in XD exposes 31 functions for text handling:

### Font Management

| Function | Description |
|----------|-------------|
| `GSmsgFontOpen` | Load and initialize a font from an FNT file |
| `GSmsgFontClose` | Release a loaded font |

### Text Rendering

| Function | Description |
|----------|-------------|
| `GSmsgPrint2` | Render text at a position |
| `GSmsgPrintRect` | Render text within a bounding rectangle (with wrapping) |
| `GSmsgPrintRight` | Render right-aligned text |

### Character Encoding

The games use a GS-specific character encoding (GSchar) rather than standard ASCII or Unicode. Conversion functions exist for mapping between GSchar and SJIS encoding. The MSG string table format stores text using this encoding, and the FNT file provides the corresponding glyphs.

## Current Status

The internal binary layout of FNT files has not been fully reverse-engineered. The glyph bitmap format, character metric tables, and encoding mapping tables within the file remain to be documented. The runtime API is known from XD disassembly and symbol maps.
