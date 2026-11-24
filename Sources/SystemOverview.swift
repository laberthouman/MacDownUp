import Foundation

extension SystemRelease {
    var supportsIPSW: Bool { (Int(id) ?? 0) >= 11 }
    var overview: String {
        if let text = remote?.overview { return text }
        switch id {
        case "27": return "Golden Gate продолжает развитие Liquid Glass и системных инструментов искусственного интеллекта. Эта версия предназначена для Mac с Apple silicon."
        case "26": return "Tahoe представляет оформление Liquid Glass, обновлённый Spotlight и приложение «Телефон». Это последнее основное поколение macOS с поддержкой отдельных Intel Mac."
        case "15": return "Sequoia добавляет зеркалирование iPhone, удобное размещение окон и приложение «Пароли». Возможности Apple Intelligence зависят от чипа, языка и региона."
        case "14": return "Sonoma переносит интерактивные виджеты на рабочий стол, добавляет видеозаставки и веб-приложения Safari. Игровой режим доступен на Mac с Apple silicon."
        case "13": return "Ventura добавляет Stage Manager для организации окон, Continuity Camera для использования iPhone как камеры и обновлённые Системные настройки."
        case "12": return "Monterey приносит Команды, режимы фокусирования, AirPlay на Mac и универсальное управление совместимыми Mac и iPad."
        case "11": return "Big Sur обновляет оформление macOS, добавляет Центр управления и становится первой системой для Mac с Apple silicon."
        case "10.15": return "Catalina разделяет iTunes на Музыку, Подкасты и TV. Sidecar позволяет использовать совместимый iPad как второй экран. Поддерживаются только 64-битные приложения."
        case "10.14": return "Mojave добавляет тёмный режим, динамический рабочий стол, стопки файлов и обновлённый Mac App Store. Это последнее поколение macOS с поддержкой 32-битных приложений."
        case "10.13": return "High Sierra вводит файловую систему APFS, поддержку HEVC и Metal 2. Изменения сосредоточены на технологиях хранения, графики и видео."
        case "10.12": return "Sierra впервые приносит Siri на Mac, общий буфер обмена и синхронизацию рабочего стола и документов через iCloud Drive."
        case "10.11": return "El Capitan улучшает скорость и удобство Yosemite: Split View, обновлённый Mission Control, поиск Spotlight и графическая технология Metal."
        case "10.10": return "Yosemite меняет оформление OS X и объединяет Mac с iPhone через Continuity, Handoff и звонки с компьютера."
        case "10.9": return "Mavericks становится первой бесплатной версией OS X. В системе появляются Карты, iBooks, вкладки Finder и технологии экономии энергии."
        case "10.8": return "Mountain Lion добавляет Центр уведомлений, Сообщения, Напоминания и более тесную интеграцию с iCloud."
        case "10.7": return "Lion приносит Launchpad, Mission Control, полноэкранные приложения и новые жесты Multi-Touch. PowerPC-приложения через Rosetta больше не запускаются."
        case "10.6": return "Snow Leopard сосредоточена на производительности, 64-битных технологиях и Grand Central Dispatch. Это первая Mac OS X, предназначенная только для Intel Mac."
        case "10.5": return "Leopard представляет Time Machine, Spaces, Quick Look и новый Dock. Это последняя Mac OS X, которая работает и на PowerPC, и на Intel."
        case "10.4": return "Tiger добавляет Spotlight, Dashboard и Automator. Retail-диски рассчитаны на PowerPC; первые Intel Mac поставлялись с отдельными модельными установщиками."
        case "10.3": return "Panther приносит Exposé, быстрое переключение пользователей и FileVault. Система рассчитана на совместимые PowerPC Mac."
        case "10.2": return "Jaguar развивает интерфейс Aqua и добавляет Quartz Extreme, iChat, Адресную книгу и Rendezvous для обнаружения устройств в сети."
        case "10.1": return "Puma улучшает производительность первого выпуска Mac OS X, расширяет поддержку устройств и добавляет воспроизведение DVD."
        default: return "Cheetah — первый публичный выпуск Mac OS X. Интерфейс Aqua, Dock и UNIX-основа заложили фундамент следующих поколений системы."
        }
    }
}
