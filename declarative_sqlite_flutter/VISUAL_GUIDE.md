# Visual Guide: Sync Status Indicators

## Indicator States

### 1. Local Changes (Unsaved)
```
┌─────────────────────────────────────┐
│ Name                                │
│ ┌─────────────────────────────────┐ │
│ │ John Doe                     ○  │ │  ← Orange hollow circle
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
Tooltip: "Changes not saved"
```

### 2. Saved to Database
```
┌─────────────────────────────────────┐
│ Name                                │
│ ┌─────────────────────────────────┐ │
│ │ John Doe                    ✓○  │ │  ← Blue circle with checkmark
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
Tooltip: "Saved to database 2m ago"
```

### 3. Synced to Server
```
┌─────────────────────────────────────┐
│ Name                                │
│ ┌─────────────────────────────────┐ │
│ │ John Doe                    ✓●  │ │  ← Green filled circle with checkmark
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
Tooltip: "Synced to server by Jane Smith 5m ago"
```

## Form Example with Multiple Fields

```
┌─────────────────────────────────────────────────────────┐
│                    Edit User                            │
├─────────────────────────────────────────────────────────┤
│ Full Name                                               │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ John Doe                                         ○  │ │  ← Local changes
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ Email Address                                           │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ john.doe@example.com                            ✓○  │ │  ← Saved to DB
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ Job Role                                                │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Senior Developer                                ✓●  │ │  ← Synced to server
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ Age                                                     │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ 32                                              ✓●  │ │  ← Synced to server
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│           [Cancel]              [Save]                  │
└─────────────────────────────────────────────────────────┘
```

## Status Progression Animation

```
User starts typing:           ○  (orange)
   ↓
Form is saved:               ✓○  (blue)
   ↓
Server sync completes:       ✓●  (green)
```

## Compact Indicators (for dense layouts)

```
Name: [John Doe        ●] ← Compact filled circle (green)
Email: [john@example   ○] ← Compact hollow circle (orange)  
Role: [Developer      ✓○] ← Compact circle with tick (blue)
```

## Integration with Required Field Indicators

```
┌─────────────────────────────────────┐
│ Name *                              │  ← Asterisk shows required
│ ┌─────────────────────────────────┐ │
│ │ John Doe                   ✓● * │ │  ← Both sync and required indicators
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

## Color Scheme

- **Orange** (#FF9800): Local changes, attention needed
- **Blue** (#2196F3): Saved to database, progress made  
- **Green** (#4CAF50): Fully synchronized, all good

## Icons Used

- **○** (radio_button_unchecked): Hollow circle for local
- **✓○** (check_circle_outline): Circle with tick outline for saved
- **✓●** (check_circle): Filled circle with tick for synced

This visual design follows established patterns from messaging apps like WhatsApp, making it immediately familiar to users.