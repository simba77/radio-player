# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
make build    # собрать .app bundle (release)
make run      # собрать и запустить
make install  # собрать и скопировать в /Applications/
make clean    # удалить .build/ и RadioPlayer.app
make icon     # перегенерировать Resources/AppIcon.icns из scripts/make_icon.swift
```

Нет Xcode-проекта — только SPM + Makefile. `swift build` напрямую не собирает .app bundle (не копирует Info.plist и иконку), поэтому для тестирования всегда использовать `make run`.

## Архитектура

macOS menu bar приложение на SwiftUI + Swift 6. Все 6 исходников живут в `Sources/RadioPlayer/`.

**Точка входа** — `RadioPlayerApp` (`@main`): два Scene — `MenuBarExtra` (меню в трее) и `Window` (настройки).

**Ключевые классы:**

- `PlayerManager` — единственный `@StateObject` в `RadioPlayerApp`. Владеет `AVPlayer`, управляет воспроизведением, регистрирует remote commands (play/pause/next/prev через `MPRemoteCommandCenter`) и обновляет `MPNowPlayingInfoCenter`. Передаётся в `MenuContentView` через `environmentObject`.
- `StationStore` — хранит список станций в `UserDefaults` (ключ `"savedStations"`), автосохранение через `didSet` на `@Published`. Передаётся в `SettingsView` через `environmentObject(player.store)`.
- `Station` — `Codable` struct с `id: UUID`, `name`, `urlString`, вычисляемым `streamURL: URL?`.

**Поток данных:**
`RadioPlayerApp` → `PlayerManager` (владеет `StationStore`) → UI views через `environmentObject`.

## Swift 6 / Concurrency

Проект компилируется в режиме Swift 6 strict concurrency. Весь UI-код и менеджеры помечены `@MainActor`. Remote command callbacks диспетчеризуют на главный актор через `Task { @MainActor in ... }`.

## Info.plist

- `LSUIElement = true` — только menu bar, нет Dock иконки
- `NSAppTransportSecurity.NSAllowsArbitraryLoads = true` — нужно для HTTP radio stream URL
