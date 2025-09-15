# Awareness Indicators Visual Guide

This guide shows the visual appearance of the awareness indicators in different configurations.

## Basic Indicator Styles

### Standard Stacked Circles (Microsoft Office Style)
```
┌─────────────────────────────────────┐
│ Edit Document                   ●●● │  ← Standard: 2 visible + "+1"
│                                     │
│ Title: [___________________]        │
│ Content: [________________]         │
│                                     │
│ [Save] [Cancel]                     │
└─────────────────────────────────────┘
```

### Visual Representation of Avatars
```
    JS    JD   +2     ← Initials in colored circles
   ┌──┐  ┌──┐ ┌──┐
   │JS│  │JD│ │+2│    ← John Smith, Jane Doe, +2 others
   └──┘  └──┘ └──┘
    🔵   🔴  🟡     ← Auto-generated vibrant colors
```

## Different Layout Options

### 1. Compact Indicator (24px)
```
App Bar: Document.docx                          ●●+3
```

### 2. Horizontal Layout
```
┌────────────────────────────────────────────────┐
│ Project: Marketing Plan                        │
│                                                │
│ Currently viewing: ● ● ● John, Jane, Bob      │
│                   JS JD BB                     │
└────────────────────────────────────────────────┘
```

### 3. Badge Style (Count Only)
```
┌─────────────────────────┐
│ Active Documents    ③   │  ← Simple count badge
│                         │
│ ● project-plan.docx     │
│ ● budget-2024.xlsx      │
│ ● presentation.pptx     │
└─────────────────────────┘
```

### 4. List Integration
```
┌─────────────────────────────────────────────────┐
│ 📄 Project Report.docx                      ●●  │
│    Last modified 2 hours ago                    │
│ ────────────────────────────────────────────────│
│ 📊 Q4 Budget.xlsx                           ●   │
│    Last modified 1 hour ago                     │
│ ────────────────────────────────────────────────│
│ 📋 Meeting Notes.md                         ●●● │
│    Last modified 5 minutes ago                  │
└─────────────────────────────────────────────────┘
```

## Color Scheme Examples

The system automatically generates vibrant colors based on user names:

```
John Smith  → 🔵 Blue (JS)
Jane Doe    → 🔴 Red (JD)  
Bob Johnson → 🟢 Green (BJ)
Alice Brown → 🟣 Purple (AB)
Mike Wilson → 🟠 Orange (MW)
Sara Davis  → 🟡 Yellow (SD)
```

## Interactive States

### Tooltip on Hover
```
┌─────────────────────────────────────┐
│ Edit Document                   ●●● │
│                     ┌───────────────┤
│ Title: [_________]  │ John Smith,   │
│                     │ Jane Doe and  │
│                     │ 2 others are  │
│                     │ viewing       │
│                     └───────────────┤
│ [Save] [Cancel]                     │
└─────────────────────────────────────┘
```

### Empty State (No Users)
```
┌─────────────────────────────────────┐
│ Edit Document                       │  ← No indicator when no users
│                                     │
│ Title: [___________________]        │
│ Content: [________________]         │
└─────────────────────────────────────┘
```

## Real-world Usage Examples

### 1. Microsoft Word-style Document Editor
```
┌─────────────────────────────────────────────────────────────┐
│ File  Edit  View  Insert  Format  Tools       ●●+1  [×]    │
│ ─────────────────────────────────────────────────────────── │
│ Marketing_Plan_2024.docx - Saved to Cloud                  │
│                                                             │
│ # Marketing Strategy for 2024                               │
│                                                             │
│ ## Executive Summary                                        │
│ This document outlines our comprehensive marketing          │
│ strategy for the upcoming fiscal year...                   │
│                                                             │
│ [Currently editing: John Smith, Jane Doe, +1 other]        │
└─────────────────────────────────────────────────────────────┘
```

### 2. Google Docs-style Collaborative Editing
```
┌─────────────────────────────────────────────────────────────┐
│ 📄 Quarterly Review                         ●●●  Share ▼   │
│ ─────────────────────────────────────────────────────────── │
│                                                             │
│ Q3 Performance Review                                       │
│                                                             │
│ Sales Results:     [●] John is typing...                    │
│ - Target: $1M                                               │
│ - Actual: $1.2M                                             │
│                                                             │
│ Marketing ROI:     [●] Jane is editing...                   │
│ - Campaign A: 15%                                           │
│ - Campaign B: 23%                                           │
│                                                             │
│ Suggestions by team members shown as colored indicators     │
└─────────────────────────────────────────────────────────────┘
```

### 3. Notion-style Database Record
```
┌─────────────────────────────────────────────────────────────┐
│ Project: Website Redesign                              ●●   │
│ ─────────────────────────────────────────────────────────── │
│ Status:        🟡 In Progress                               │
│ Assignee:      John Smith                                   │
│ Due Date:      2024-03-15                                   │
│ Priority:      High                                         │
│                                                             │
│ Description:                                                │
│ Complete redesign of company website with modern UX...     │
│                                                             │
│ ┌─ Currently viewing ────────────────────────────────────┐  │
│ │ ● John Smith (Owner)                                  │  │
│ │ ● Jane Doe (Designer)                                 │  │
│ └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Technical Implementation

### Widget Tree Structure
```
ReactiveAwarenessIndicator
├── StreamBuilder<List<AwarenessUser>>
│   └── AwarenessIndicator
│       ├── Tooltip (optional)
│       └── Stack (for overlapping avatars)
│           ├── Positioned (avatar 1)
│           │   └── Container (colored circle)
│           │       └── Text (initials)
│           ├── Positioned (avatar 2)
│           │   └── Container (colored circle)
│           │       └── Text (initials)
│           └── Positioned (+N indicator)
│               └── Container (gray circle)
│                   └── Text (+N)
```

### Color Generation Algorithm
```
Input: "John Smith"
├── Hash name → 123456789
├── Convert to HSV → H: 123°, S: 0.7, V: 0.9
├── Generate RGB → R: 89, G: 156, B: 255
└── Result: Vibrant blue #599CFF
```

This ensures:
- Consistent colors for the same user across sessions
- High contrast and vibrant appearance
- Good distribution across the color spectrum
- Accessibility-friendly color choices