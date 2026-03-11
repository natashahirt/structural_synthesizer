# Engineering Reports

> ```julia
> engineering_report(design)                    # print to stdout
> engineering_report(design; io = open("report.txt", "w"))  # write to file
> ```

## Overview

The engineering report module generates formatted text reports summarizing the complete design results. Reports include slab sizing, column adequacy, beam adequacy, foundation sizing, material takeoffs, and pass/fail status for all code checks. Reports are intended for engineering review and documentation.

**Source:** `StructuralSynthesizer/src/postprocess/engineering_report.jl`, `report_tables.jl`

## Functions

```@docs
engineering_report
```

## Implementation Details

### Report Structure

`engineering_report(design::BuildingDesign; io = stdout)` produces the following sections:

| Section | Content |
|:--------|:--------|
| Header | Building name, date, design parameters summary |
| Slab Results | Thickness, reinforcement, deflection ratio, punching shear status per slab |
| Column Results | Section size, axial ratio, interaction ratio, pass/fail per column |
| Beam Results | Section, flexure ratio, shear ratio, pass/fail per beam |
| Foundation Results | Footing dimensions, bearing ratio, pass/fail per foundation group |
| Material Takeoff | Total concrete volume, steel weight, rebar weight, timber volume |
| Embodied Carbon | Total kgCO₂e and breakdown by element type |
| Status | Overall pass/fail, critical element, critical demand/capacity ratio |

### Report Sections

- **`_report_header`** — prints the design name, timestamp, floor type, materials, fire rating, and analysis method
- **`_report_slabs`** — tabulates slab results: thickness, M₀, deflection L/n ratio, punching shear ratio, convergence status
- **`_report_columns`** — tabulates column results: section size (c1 × c2 or W shape), axial/interaction ratios
- **`_report_foundations`** — tabulates foundation results: plan dimensions, depth, bearing/punching/flexure ratios
- **`_report_takeoff`** — material quantities summary
- **`_report_status`** — overall pass/fail determination

### Table Formatting

The `report_tables.jl` module provides utilities for formatted ASCII tables:

| Function | Description |
|:---------|:------------|
| `table_divider(widths; char)` | Horizontal divider line |
| `table_header(labels, widths; indent)` | Column header row |
| `table_title(title; width)` | Centered section title |
| `section_break(title; width)` | Section separator |
| `fv(x; d)` | Format value with `d` decimal places |
| `fv_pct(x; d)` | Format as percentage |
| `safe_ratio(num, den)` | Compute ratio with zero-denominator protection |
| `pass_fail(ok::Bool)` | "PASS" or "**FAIL**" string |

## Options & Configuration

| Parameter | Description | Default |
|:----------|:------------|:--------|
| `io` | Output stream | `stdout` |
| `du` | `DisplayUnits` for formatting | `imperial` |

## Limitations & Future Work

- Reports are plain text only; HTML and PDF output are planned.
- Detailed reinforcement schedules (bar sizes, spacing, cut lengths) are not included in the current report format.
- Graphical output (section drawings, interaction diagrams) is available through the visualization package but not integrated into the text report.
