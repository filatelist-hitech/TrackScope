# BPM Radar — Design Handoff for Claude Code
**Version:** 1.0 · May 2026  
**Purpose:** Implement redesigned screens into the existing iOS/Android codebase

---

## 1. Design Changes Summary

### Screen 1 — Main Radar (Real-time BPM)

| Element | Before | After | Priority |
|---|---|---|---|
| BPM number size | Small, hidden | **64–72px hero**, center of card | 🔴 Critical |
| BPM empty state | White rectangle `#ffffff` | `— — —` dim text `#1e3530` | 🔴 Critical |
| Confidence bar height | 2px | **7px** with color thresholds | 🔴 Critical |
| Confidence color | Single color | Red <30% · Yellow 30–70% · Teal >70% | 🔴 Critical |
| Waveform zone height | 190px (too tall) | **120px** compact | 🟡 Medium |
| Section labels contrast | CR ~1.2:1 (invisible) | CR ≥ 3:1, icons added | 🟡 Medium |
| "Break" button | Tiny, no label | Full button: icon + "Зафиксировать брейк" | 🟡 Medium |
| Listening indicator | None | Animated dot + "слушаю" label | 🟢 Low |

### Screen 2 — Upgrade to Pro (Paywall)

| Element | Before | After | Priority |
|---|---|---|---|
| Table column headers | None | "Free" / "Pro" headers | 🔴 Critical |
| Value headline | None | "Читай любой трек. Без ограничений." | 🔴 Critical |
| Primary CTA | Same style as secondary | Filled + "Best value" badge | 🔴 Critical |
| Secondary CTA | Same as primary | Outline style (border only) | 🔴 Critical |
| "Debug Screen" row | "Debug Screen" label | **"Signal Analyzer"** | 🟡 Medium |
| Widget card (duplicate) | Duplicates table row | **Roadmap card** "Coming to Pro" | 🟡 Medium |

### Screen 3 — History (New)
New screen. See design in prototype.

### Screen 4 — Settings (New)  
New screen. See design in prototype.

### Screen 5 — Signal Analyzer (New Pro screen)
New Pro-only screen accessible from main radar.

---

## 2. Color Tokens

```swift
// iOS — add to Assets.xcassets or Color+Extensions.swift
extension Color {
    static let bpmBackground    = Color(hex: "#050807")
    static let bpmSurface       = Color(hex: "#0c1410")
    static let bpmSurface2      = Color(hex: "#0d1712")
    static let bpmAccent        = Color(hex: "#00dfb0")
    static let bpmAmber         = Color(hex: "#c8a020")
    static let bpmAmberText     = Color(hex: "#ffe090")
    static let bpmAmberBg       = Color(hex: "#c8a020").opacity(0.18)
    static let bpmRed           = Color(hex: "#e04040")
    static let bpmYellow        = Color(hex: "#e0b020")
    static let bpmTextPrimary   = Color(hex: "#c8dcd8")
    static let bpmTextSecondary = Color(hex: "#3a6858")
    static let bpmTextMuted     = Color(hex: "#1a3028")
    static let bpmBorder        = Color(hex: "#182820")
}
```

```kotlin
// Android — res/values/colors.xml
<color name="bpm_background">#050807</color>
<color name="bpm_surface">#0c1410</color>
<color name="bpm_surface2">#0d1712</color>
<color name="bpm_accent">#00dfb0</color>
<color name="bpm_amber">#c8a020</color>
<color name="bpm_amber_text">#ffe090</color>
<color name="bpm_red">#e04040</color>
<color name="bpm_yellow">#e0b020</color>
<color name="bpm_text_primary">#c8dcd8</color>
<color name="bpm_text_secondary">#3a6858</color>
<color name="bpm_text_muted">#1a3028</color>
```

---

## 3. Typography

Font: **IBM Plex Mono** (already in use)

| Role | Size | Weight | Usage |
|---|---|---|---|
| BPM Hero | 64–72pt | SemiBold (600) | Main BPM number |
| Nav title | 8pt | Regular | Top nav labels |
| Section label | 7pt | Regular | Zone labels (WAVEFORM etc) |
| Stats value | 11pt | Regular | Data values in card |
| Stats label | 6.5pt | Regular | `letter-spacing: 0.12em` |
| Button | 8.5pt | Regular | Break button, settings rows |
| CTA | 10pt | SemiBold | Paywall buttons |

---

## 4. Confidence Bar Logic

```swift
// ConfidenceBar.swift
func confidenceColor(_ confidence: Double) -> Color {
    switch confidence {
    case ..<30:  return .bpmRed     // Unreliable — red
    case 30..<70: return .bpmYellow  // Uncertain — yellow
    default:     return .bpmAccent  // Reliable — teal
    }
}

// ConfidenceBarView
struct ConfidenceBarView: View {
    let confidence: Double  // 0–100
    var body: some View {
        HStack(spacing: 9) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(hex:"#111916")).frame(height: 7)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(confidenceColor(confidence))
                        .frame(width: geo.size.width * confidence / 100, height: 7)
                }
            }.frame(height: 7)
            Text("\(Int(confidence))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(confidenceColor(confidence))
                .frame(width: 36, alignment: .trailing)
        }
    }
}
```

---

## 5. BPM Empty State

```swift
// BPMDisplayView.swift
struct BPMDisplayView: View {
    let bpm: Double?
    let mode: DetectionMode  // .idle, .detecting, .unstable
    
    var displayText: String {
        guard let bpm = bpm else { return "— — —" }
        return String(format: "%.1f", bpm)
    }
    
    var textColor: Color {
        guard bpm != nil else { return Color(hex: "#1e3530") }
        return mode == .unstable ? Color(hex: "#ffe090") : .bpmAccent
    }
    
    var fontSize: CGFloat { bpm == nil ? 58 : 68 }
    
    var body: some View {
        VStack(spacing: 5) {
            Text(displayText)
                .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                .foregroundColor(textColor)
                .kerning(-2)
                .contentTransition(.numericText())
            HStack(spacing: 12) {
                Text("BPM")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.bpmTextSecondary)
                    .kerning(4)
                if mode == .unstable {
                    StatusPill(text: "нестабильно", style: .amber)
                }
                Text("155–230 · Hitech")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.bpmTextMuted)
            }
        }
    }
}
```

---

## 6. Navigation Structure

```
TabBar
├── Radar (Main)
│   ├── push → Signal Analyzer  [tap "Лучший кандидат"]
│   └── push → Paywall          [tap PRO badge]
├── History
└── Settings
    ├── push → Signal Analyzer
    ├── push → History
    └── push → Paywall
```

### Tab Bar Items
```swift
enum Tab: String, CaseIterable {
    case radar    = "РАДАР"
    case history  = "ИСТОРИЯ"
    case settings = "НАСТРОЙКИ"
    
    var icon: String {
        switch self {
        case .radar:    return "scope"         // SF Symbol or custom
        case .history:  return "house.fill"
        case .settings: return "clock"
        }
    }
    var accentColor: Color { .bpmAccent }
    var inactiveColor: Color { Color(hex: "#1a3028") }
}
```

---

## 7. Signal Analyzer Screen (New — Pro)

**Entry point:** tap on "Лучший кандидат" value on main screen  
**Pro gate:** show paywall if user is Free tier

**Components:**
1. **FFT Spectrum** — real-time frequency chart (existing audio processing, new visualization)
2. **BPM Candidates list** — top 4 candidates from autocorrelation with confidence bars
3. **Algorithm Metrics** — Onset Detection %, Autocorrelation %, Spectral Flux %, SNR dB, Input Level dBFS

```swift
// BPMCandidate model
struct BPMCandidate {
    let bpm: Double
    let confidence: Double  // 0–100
    let isTopCandidate: Bool
}

// SignalAnalyzerViewModel
@Observable class SignalAnalyzerViewModel {
    var fftData: [Float] = []          // Raw FFT bins
    var candidates: [BPMCandidate] = []
    var onsetDetection: Double = 0
    var autocorrelation: Double = 0
    var spectralFlux: Double = 0
    var snr: Double = 0
    var inputLevel: Double = 0
}
```

---

## 8. History Screen (New — Pro)

**Data model:**
```swift
struct BPMSession: Identifiable {
    let id: UUID
    let date: Date
    let avgBPM: Double
    let peakBPM: Double
    let duration: TimeInterval
    let avgConfidence: Double
    let waveformThumbnail: [Float]  // Downsampled for mini-chart
}
```

**Features:**
- Group by day (today / yesterday / older)
- Summary header: session count, avg BPM, total time
- Export: CSV + JSON
- Row: BPM number (large, left) + time + confidence bar + mini waveform thumbnail

---

## 9. Settings Screen (New)

**New settings to add:**

| Setting | Type | Default | Notes |
|---|---|---|---|
| BPM Range | Segmented (Free: 170–230 / Pro: 155–230) | Free tier: 170–230 | Gated by tier |
| Input Sensitivity | Slider (–6 to +6 dB) | 0 dB | |
| BPM Smoothing | Picker (None / Light / Moderate / Heavy) | Moderate | |
| Show Waveform | Toggle | true | |
| Show Spectrum | Toggle | true | |
| Keep Screen On | Toggle | true | Calls `UIApplication.shared.isIdleTimerDisabled` |

---

## 10. Implementation Priority

### Sprint 1 — Critical (Radar screen fixes)
1. [ ] BPM number: 64–72pt, semibold, centered
2. [ ] BPM empty state: `— — —` instead of blank rect
3. [ ] Confidence bar: 7px height + color thresholds
4. [ ] Paywall: add column headers + value headline
5. [ ] Paywall: CTA hierarchy (primary + secondary)

### Sprint 2 — Medium (Paywall + Break button)
1. [ ] Rename "Debug Screen" → "Signal Analyzer"  
2. [ ] Break button: icon + label + proper placement
3. [ ] Waveform zone height: reduce to 120pt
4. [ ] Section label contrast: increase to ≥ 3:1
5. [ ] Replace widget card with Roadmap card

### Sprint 3 — New Screens
1. [ ] History screen + data persistence
2. [ ] Settings screen + UserDefaults binding
3. [ ] Signal Analyzer screen + FFT visualization
4. [ ] Tab bar navigation

---

## 11. Files to Change

| File (guessed) | Change |
|---|---|
| `BPMDisplayView.swift` | BPM hero size, empty state, confidence bar |
| `MainRadarViewController.swift` | Waveform height, listening indicator |
| `PaywallViewController.swift` | Headlines, table headers, CTA hierarchy |
| `BreakButtonView.swift` | Icon + label, repositioning |
| `SettingsViewController.swift` | New settings rows |
| Add: `HistoryViewController.swift` | New screen |
| Add: `SignalAnalyzerViewController.swift` | New screen |
| Add: `BPMSession.swift` | Data model |
| `Color+Extensions.swift` | Token additions |

---

*Interactive prototype:* `BPM Radar Prototype.html`  
*Before/After reference:* `BPM Radar Redesign.html`  
*Design audit:* `BPM Radar Design Audit.html`
