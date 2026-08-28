#!/bin/sh
set -eu

grep -Fq 'enum SettlrAppearance' Settlr/Models/AppearancePreference.swift
grep -Fq 'static let accentText' Settlr/Views/Components/DesignSystem.swift
grep -Fq 'struct SignalTraceLoadingView' Settlr/Views/Components/SignalLoadingViews.swift
grep -Fq 'struct SettlrPulseLoadingView' Settlr/Views/Components/SignalLoadingViews.swift
grep -Fq 'struct ActivityShapeLoadingView' Settlr/Views/Components/SignalLoadingViews.swift
grep -Fq '@AppStorage("settlr.appearance")' Settlr/SettlrApp.swift
grep -Fq '.fill(Theme.surface)' Settlr/Views/Components/SectionCard.swift
grep -Fq '.strokeBorder(Theme.line' Settlr/Views/Components/SectionCard.swift
grep -Fq 'static let buttonInk' Settlr/Views/Components/DesignSystem.swift
grep -Fq '.foregroundStyle(Theme.buttonInk)' Settlr/Views/Components/DesignSystem.swift
grep -Fq 'presentation.isSelected ? Theme.accentText' Settlr/Views/Components/DesignSystem.swift
grep -Fq 'case home, activity, savings, cards' Settlr/Views/Components/FloatingTabBar.swift
grep -Fq 'struct QuickActionLauncher' Settlr/Views/Components/QuickActionLauncher.swift
grep -Fq 'Scan and split' Settlr/Views/Components/QuickActionLauncher.swift
