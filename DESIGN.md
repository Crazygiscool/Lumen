---
name: Lumen
colors:
  surface: '#0b1326'
  surface-dim: '#0b1326'
  surface-bright: '#31394d'
  surface-container-lowest: '#060e20'
  surface-container-low: '#131b2e'
  surface-container: '#171f33'
  surface-container-high: '#222a3d'
  surface-container-highest: '#2d3449'
  on-surface: '#dae2fd'
  on-surface-variant: '#c6c5d7'
  inverse-surface: '#dae2fd'
  inverse-on-surface: '#283044'
  outline: '#8f8fa0'
  outline-variant: '#454654'
  surface-tint: '#bdc2ff'
  primary: '#bdc2ff'
  on-primary: '#0013a0'
  primary-container: '#1e2ebd'
  on-primary-container: '#a4acff'
  inverse-primary: '#3e4dd7'
  secondary: '#ccbeff'
  on-secondary: '#332664'
  secondary-container: '#4a3d7c'
  on-secondary-container: '#baabf3'
  tertiary: '#ffb4a1'
  on-tertiary: '#611300'
  tertiary-container: '#851d00'
  on-tertiary-container: '#ff967b'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#dfe0ff'
  primary-fixed-dim: '#bdc2ff'
  on-primary-fixed: '#000866'
  on-primary-fixed-variant: '#2131bf'
  secondary-fixed: '#e7deff'
  secondary-fixed-dim: '#ccbeff'
  on-secondary-fixed: '#1e0e4e'
  on-secondary-fixed-variant: '#4a3d7c'
  tertiary-fixed: '#ffdbd2'
  tertiary-fixed-dim: '#ffb4a1'
  on-tertiary-fixed: '#3c0800'
  on-tertiary-fixed-variant: '#881f01'
  background: '#0b1326'
  on-background: '#dae2fd'
  surface-variant: '#2d3449'
typography:
  display-lg:
    fontFamily: Geist
    fontSize: 48px
    fontWeight: '600'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Geist
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Geist
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  headline-md:
    fontFamily: Geist
    fontSize: 24px
    fontWeight: '500'
    lineHeight: 32px
  body-lg:
    fontFamily: Geist
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Geist
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-md:
    fontFamily: Geist
    fontSize: 14px
    fontWeight: '500'
    lineHeight: 20px
    letterSpacing: 0.02em
  code-sm:
    fontFamily: Geist
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  unit: 4px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 48px
  container-max: 900px
  gutter: 24px
---

## Brand & Style

The design system is engineered for a FOSS (Free and Open Source Software) journaling application that prioritizes privacy, introspection, and technical clarity. The brand personality is "Illuminating," acting as a quiet observer that sheds light on the user's inner thoughts without distraction. 

The aesthetic is **Minimalist and Functional**, blending a "developer-tool" precision with a refined editorial focus. It avoids the playful, consumer-oriented trends of social media, opting instead for a systematic and intentional interface. The emotional response should be one of security, focus, and calm—a digital sanctuary for long-form writing and self-reflection.

## Colors

This design system is strictly **Dark Mode**. The palette is centered around deep obsidian and charcoal tones to reduce eye strain during late-night journaling sessions and to provide a high-contrast foundation for "illuminated" content.

- **Primary (#1e2ebd):** A Deep Cobalt Blue used for actionable elements, focus states, and signifying the "light" of the user's data. It provides a more grounded, stable presence than the previous indigo.
- **Secondary (#c4b5fd):** A softer violet used for accents and categorizing content without the intensity of the primary color.
- **Base (Background):** `#0f172a` (Obsidian) for the main application canvas.
- **Surface (Containers):** `#1e293b` (Charcoal) for cards, sidebars, and input areas to create subtle depth.
- **Status/Alerts:** Use muted variations of Emerald (Success) and Rose (Error), keeping with the technical FOSS aesthetic.

## Typography

The typography system leverages **Geist** exclusively. Its monolinear, geometric structure provides a modern, technical feel that aligns with FOSS principles. 

- **Hierarchy:** Use weight (Medium/SemiBold) rather than size to distinguish importance, maintaining a compact and information-dense layout.
- **Rhythm:** Body text is optimized for long-form reading with a generous 1.5x line height. 
- **Character:** Labels and metadata should use slightly increased letter-spacing and Medium weights to ensure legibility against dark backgrounds.

## Layout & Spacing

The layout philosophy follows a **Fixed Grid** approach for the main writing canvas to ensure an editorial feel, while the shell remains fluid.

- **The Writing Column:** Content is centered with a max-width of 900px to maintain comfortable line lengths.
- **Sidebar & Navigation:** A fixed left-hand rail for navigation, utilizing narrow margins to maximize the workspace.
- **Grid:** A 12-column grid is used for the dashboard, but for the journaling experience, a single-column focus mode is the default.
- **Scale:** All spacing is derived from a 4px base unit, favoring `16px (md)` and `24px (lg)` for the majority of structural gaps.

## Elevation & Depth

This design system avoids heavy shadows and physical metaphors. Depth is communicated through **Tonal Layering** and **Low-Contrast Outlines**.

- **Z-Axis:** Instead of shadows, use subtle color shifts. The background is `#0f172a`, and elevated elements (cards, modals) use `#1e293b`.
- **Borders:** Distinguish containers using 1px solid borders in a slightly lighter charcoal (`#334155`). This reinforces the "no-nonsense" FOSS aesthetic.
- **Interaction:** On hover, elements may transition to a slightly lighter surface color or gain a primary-colored thin border, rather than "lifting" off the page.

## Shapes

The shape language is **Soft (0.25rem)**. This provides a modern touch without the "bubbliness" of mainstream social apps.

- **Components:** Buttons, input fields, and tags use a consistent 4px (0.25rem) radius.
- **Containers:** Larger cards or sections may use up to 8px (0.5rem), but never more. 
- **Consistency:** Maintain sharp internal corners for nested elements (like code blocks within a post) to emphasize the technical nature of the application.

## Components

- **Buttons:** Primary buttons are solid `#1e2ebd` with white text. Secondary buttons use a subtle `#1e293b` fill with a `#334155` border.
- **Input Fields:** Minimalist design with only a bottom border or a very subtle ghost-box background. Focus states are indicated by a 1px primary border.
- **Chips/Tags:** Used for entry categorization. Low-contrast background with `#1e2ebd` text to keep them readable but secondary to the journal content.
- **Lists:** Clean, unbordered lists with 16px vertical padding between entries. Use a primary-colored vertical line (the "lumen") to indicate the currently active or selected entry.
- **Journal Entries:** Cards should feel like "sheets" of paper. No shadows, just a 1px border. 
- **Status Indicators:** Small, circular dots for "Synced" or "Encrypted" status, reflecting the app's focus on privacy and data integrity.
