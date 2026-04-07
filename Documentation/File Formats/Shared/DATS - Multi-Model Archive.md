# DATS — Multi-Model Archive

## Overview

DATS files contain multiple DAT models bundled together in a single file. Used for objects that have numbered visual variants, such as the PokeSnack wheel segments in Pokemon XD.

**File type ID:** `0x10`
**Extension:** `.dats`
**Byte order:** Big-endian

## Structure

A DATS file is essentially multiple DAT model files concatenated sequentially. Each embedded DAT follows the standard HAL/HSD model format (see [DAT - HAL Model Format](DAT%20-%20HAL%20Model%20Format.md)).

The individual models are typically numbered variants of the same base object (e.g., different rotation states or visual configurations).

## Identification

No magic bytes — identified by FSYS file type ID `0x10`. Distinguished from single DAT files (`0x04`) by the type ID.

## References

- See [DAT - HAL Model Format](DAT%20-%20HAL%20Model%20Format.md) for the individual model format
- Runtime: GSmodel system loads individual models from the archive
