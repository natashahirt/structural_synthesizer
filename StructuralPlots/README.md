# StructuralPlots

A Makie theme and utility module for structural engineering visualizations.

> **Acknowledgment:** This module is explicitly inspired by [kjlMakie](https://github.com/keithjlee/kjlMakie) by Keith J. Lee. The structure, utility functions, and theme architecture follow the patterns established in that excellent package.

## Installation

```julia
using Pkg
Pkg.develop(path="path/to/StructuralPlots")
```

## Usage

```julia
using StructuralPlots

# Apply a theme
set_theme!(sp_light)

# Create a figure with journal-ready sizing
fig = Figure(size = halfwidth(0.8))
ax = Axis(fig[1,1])

# Use the color palette
scatter!(ax, rand(10), rand(10), color = sp_magenta)
lines!(ax, 1:10, rand(10), color = sp_ceruleanblue)

# Apply structural visualization style
asapstyle!(ax; ground = true)
```

## Color Palette (色)

| Name | Color | Hex |
|------|-------|-----|
| `sp_powderblue` | ![#aeddf5](https://via.placeholder.com/15/aeddf5/aeddf5.png) | `#aeddf5` |
| `sp_skyblue` | ![#70cbfd](https://via.placeholder.com/15/70cbfd/70cbfd.png) | `#70cbfd` |
| `sp_gold` | ![#df7e00](https://via.placeholder.com/15/df7e00/df7e00.png) | `#df7e00` |
| `sp_magenta` | ![#dc267f](https://via.placeholder.com/15/dc267f/dc267f.png) | `#dc267f` |
| `sp_orange` | ![#e04600](https://via.placeholder.com/15/e04600/e04600.png) | `#e04600` |
| `sp_ceruleanblue` | ![#00AEEF](https://via.placeholder.com/15/00AEEF/00AEEF.png) | `#00AEEF` |
| `sp_charcoalgrey` | ![#3e3e3e](https://via.placeholder.com/15/3e3e3e/3e3e3e.png) | `#3e3e3e` |
| `sp_irispurple` | ![#4c2563](https://via.placeholder.com/15/4c2563/4c2563.png) | `#4c2563` |
| `sp_darkpurple` | ![#130039](https://via.placeholder.com/15/130039/130039.png) | `#130039` |
| `sp_lilac` | ![#A678B5](https://via.placeholder.com/15/A678B5/A678B5.png) | `#A678B5` |

Colors are also accessible via the `色` dictionary:
```julia
色[:magenta]  # returns sp_magenta
```

## Themes

| Theme | Description |
|-------|-------------|
| `sp_light` | Light theme with transparent background |
| `sp_dark` | Dark theme with near-black background |
| `sp_light_mono` | Light theme with JetBrains Mono font |
| `sp_dark_mono` | Dark theme with JetBrains Mono font |

## Gradients

**Structural-specific:**
- `tension_compression` — blue ↔ white ↔ magenta
- `stress_gradient` — skyblue → gold → orange

**General purpose:**
- `blue2gold`, `purple2gold`, `magenta2gold`
- `white2blue`, `white2purple`, `white2magenta`, `white2black`
- `trans2blue`, `trans2purple`, `trans2magenta`, `trans2black`, `trans2white`

## Utility Functions

- `discretize(n; colormap)` — Discretize a colormap into n colors
- `labelize!(axis)` — Toggle label visibility
- `labelscale!(axis, factor)` — Scale font sizes
- `changefont!(axis, font)` — Change axis fonts
- `gridtoggle!(axis)` — Toggle grid visibility
- `simplifyspines!(axis)` — Simplify 3D axis spines
- `linkaxes!(parent, child)` — Link 3D axis rotation
- `mirrorticks!(axis)` — Toggle mirrored ticks
- `fixlimits!(axis)` — Fix axis limits to current state

## Axis Styles

- `graystyle!(axis)` — Gray background with white grid
- `structurestyle!(axis)` — Clean structural visualization
- `cleanstyle!(axis)` — Minimal 3D style
- `asapstyle!(axis)` — ASAP structural visualization style
- `blueprintstyle!(axis)` — Blueprint-style (blue grid on dark)

## Figure Sizes

For journal-ready figures (default: Elsevier guidelines):

```julia
fullwidth(ratio)      # Full text width
halfwidth(ratio)      # Half text width
thirdwidth(ratio)     # One-third text width
quarterwidth(ratio)   # Quarter text width
customwidth(factor, ratio)  # Custom width factor
```

## License

MIT
