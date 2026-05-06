# CLAUDE.md

## Подход к разработке

- **Состояния, а не только happy path.** Каждая фича требует обработки ошибок, загрузки и граничных случаев. Если добавляется воспроизведение — нужны `isLoading` и `errorMessage`. Если добавляется список — нужно состояние «пусто».
- **Консистентность состояния.** Если `isPlaying = true`, что-то обязано играть. Наблюдение за реальным состоянием плеера (`timeControlStatus`, `item.status`) важнее оптимистичных флагов.
- **Жизненный цикл ресурсов.** Каждый observer, output, notification — должен сниматься явно. Паттерн: `stopObserving()` перед любым `play()` и в `stop()`.
- **Попутные баги — фиксить.** Если при работе над задачей обнаружен баг — исправить и указать в описании.

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

**Ключевые классы:**

- `PlayerManager` — единственный `@StateObject` в `RadioPlayerApp`. Владеет `AVPlayer`, управляет воспроизведением, регистрирует remote commands (play/pause/next/prev через `MPRemoteCommandCenter`) и обновляет `MPNowPlayingInfoCenter`. Передаётся в `MenuContentView` через `environmentObject`.
- `StationStore` — хранит список станций в `UserDefaults` (ключ `"savedStations"`), автосохранение через `didSet` на `@Published`. Передаётся в `SettingsView` через `environmentObject(player.store)`.
- `Station` — `Codable` struct с `id: UUID`, `name`, `urlString`, вычисляемым `streamURL: URL?`.

**Поток данных:**
`RadioPlayerApp` → `PlayerManager` (владеет `StationStore`) → UI views через `environmentObject`.

## Swift 6 / Concurrency

- Когда нужно передать non-Sendable тип Apple (например `AVMetadataItem`) через границу изоляции — оборачиваем в `private struct SendableMetadataItem: @unchecked Sendable`. Это безопасно для read-only объектов.
- Для свойств-замыканий, которые задаются один раз в `init` и не меняются — `nonisolated(unsafe) var`.
- KVO через `NSKeyValueObservation`: коллбек захватывает только `Sendable`-значения (enum, Error), результат диспетчеризуется через `Task { @MainActor [weak self] in ... }`. Наблюдатели хранятся как `NSKeyValueObservation?`-свойства — присвоение `nil` автоматически инвалидирует наблюдение.

## Обработка состояний AVPlayer

`PlayerManager` наблюдает за двумя KVO-свойствами после каждого `play()`:

- `AVPlayer.timeControlStatus` → управляет `isLoading` (`.waitingToPlayAtSpecifiedRate` = буферизация, `.playing` = готов)
- `AVPlayerItem.status` → при `.failed` сбрасывает `isPlaying = false` и выставляет `errorMessage`

Перед каждым `play()` и в `stop()` вызывается `stopObserving()` (обнуляет оба наблюдателя) и `remove(metadataOutput)` с текущего item'а. Это обязательно — `AVPlayerItemOutput` может быть привязан только к одному item одновременно.

## Info.plist

- `LSUIElement = true` — только menu bar, нет Dock иконки
- `NSAppTransportSecurity.NSAllowsArbitraryLoads = true` — нужно для HTTP radio stream URL
