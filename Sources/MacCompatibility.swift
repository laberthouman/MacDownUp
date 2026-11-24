import Foundation

struct CompatibleMac: Identifiable, Codable, Hashable {
    let family: String
    let models: String
    var id: String { family }
    var symbol: String {
        if family.contains("Book") { return "laptopcomputer" }
        if family.contains("iMac") { return "desktopcomputer" }
        return "macpro.gen3"
    }
}

struct MacCompatibility: Codable, Hashable {
    let models: [CompatibleMac]
    let note: String
    let reference: URL
    var notebookSummary: String { models.filter { $0.family.contains("Book") }.map { "\($0.family): \($0.models)" }.joined(separator: "\n") }
}

extension SystemRelease {
    var compatibility: MacCompatibility { remote?.compatibility ?? CompatibilityCatalog.forRelease(id) }
}

enum CompatibilityCatalog {
    private static func entry(_ rows: [(String, String)], _ article: String, note: String = "Указаны семейства и минимальные поколения. Mac не поддерживает систему старше той, с которой он поставлялся; для более поздних моделей нужен соответствующий выпуск этой macOS.") -> MacCompatibility {
        MacCompatibility(models: rows.map { CompatibleMac(family: $0.0, models: $0.1) }, note: note,
                         reference: URL(string: "https://support.apple.com/\(article)")!)
    }

    static func forRelease(_ id: String) -> MacCompatibility {
        switch id {
        case "27": return entry([
            ("MacBook Pro", "Все модели с Apple silicon, начиная с M1 (2020)"),
            ("MacBook Air", "Все модели с Apple silicon, начиная с M1 (2020)"),
            ("MacBook Neo", "13″, A18 Pro"),
            ("iMac", "24″ с Apple silicon (2021 и новее)"),
            ("Mac mini", "Apple silicon (2020 и новее)"),
            ("Mac Studio", "2022 и новее"), ("Mac Pro", "Apple silicon (2023)")
        ], "127255", note: "Golden Gate поддерживает Mac с Apple silicon. Модели с процессорами Intel не поддерживаются. Точный список и новые модели — на сайте Apple.")
        case "26": return entry([
            ("MacBook Pro", "Apple silicon; Intel: 16″ (2019), 13″ (2020, четыре порта Thunderbolt 3)"),
            ("MacBook Air", "Apple silicon: M1 (2020) и новее"), ("MacBook Neo", "13″, A18 Pro"),
            ("iMac", "24″ с Apple silicon; Retina 5K 27″ (2020)"),
            ("Mac mini", "Apple silicon: M1 (2020) и новее"),
            ("Mac Studio", "2022, 2023, 2025"), ("Mac Pro", "2019, 2023")
        ], "122867", note: "Intel MacBook Air и MacBook Pro 13″ 2020 с двумя портами Thunderbolt 3 не поддерживаются. Возможности Apple Intelligence требуют Apple silicon. Для новых моделей смотрите точный список Apple.")
        case "15": return entry([
            ("MacBook Pro", "2018–2024"), ("MacBook Air", "2020–2025 (Intel и Apple silicon)"),
            ("iMac", "2019–2024"), ("iMac Pro", "2017"), ("Mac mini", "2018–2024"),
            ("Mac Studio", "2022–2025"), ("Mac Pro", "2019, 2023")
        ], "120282")
        case "14": return entry([
            ("MacBook Pro", "2018–2023"), ("MacBook Air", "2018–2024"), ("iMac", "2019–2023"),
            ("iMac Pro", "2017"), ("Mac mini", "2018–2023"), ("Mac Studio", "2022, 2023"), ("Mac Pro", "2019, 2023")
        ], "105113")
        case "13": return entry([
            ("MacBook Pro", "2017–2023"), ("MacBook Air", "2018–2023"), ("MacBook", "Retina 12″ (2017)"),
            ("iMac", "2017–2021"), ("iMac Pro", "2017"), ("Mac mini", "2018–2023"),
            ("Mac Studio", "2022, 2023"), ("Mac Pro", "2019, 2023")
        ], "102861")
        case "12": return entry([
            ("MacBook Pro", "Начало 2015–2022"), ("MacBook Air", "Начало 2015–2022"), ("MacBook", "Начало 2016–2017"),
            ("iMac", "Конец 2015–2021"), ("iMac Pro", "2017"), ("Mac mini", "Конец 2014–2020"),
            ("Mac Studio", "2022"), ("Mac Pro", "Конец 2013, 2019")
        ], "103260")
        case "11": return entry([
            ("MacBook Pro", "Конец 2013–2020"), ("MacBook Air", "2013–2020"), ("MacBook", "2015–2017"),
            ("iMac", "2014–2021"), ("iMac Pro", "2017"), ("Mac mini", "2014–2020"), ("Mac Pro", "2013, 2019")
        ], "103111")
        case "10.15": return entry([
            ("MacBook Pro", "Середина 2012–2020, только Intel"), ("MacBook Air", "Середина 2012–2020, только Intel"),
            ("MacBook", "Начало 2015–2017"), ("iMac", "Конец 2012–2020"), ("iMac Pro", "2017"),
            ("Mac mini", "Конец 2012–2018"), ("Mac Pro", "Конец 2013, 2019")
        ], "102765", note: "Catalina работает только на Intel Mac и не запускает 32-битные приложения. Для моделей 2019–2020 требуется подходящая сборка 10.15; Apple silicon не поддерживается.")
        case "10.14": return entry([
            ("MacBook Pro", "Середина 2012–2019 (до моделей, поставлявшихся с Catalina)"),
            ("MacBook Air", "Середина 2012–2019"), ("MacBook", "Начало 2015–2017"),
            ("iMac", "Конец 2012–2019"), ("iMac Pro", "2017"), ("Mac mini", "Конец 2012–2018"),
            ("Mac Pro", "Конец 2013; середина 2010 и 2012 с видеокартой Metal")
        ], "112009")
        case "10.13", "10.12": return entry([
            ("MacBook Pro", id == "10.13" ? "Середина 2010–2017" : "Середина 2010–2016"),
            ("MacBook Air", id == "10.13" ? "Конец 2010–2017" : "Конец 2010–2015"),
            ("MacBook", id == "10.13" ? "Конец 2009–2017" : "Конец 2009–2016"),
            ("iMac", id == "10.13" ? "Конец 2009–2017" : "Конец 2009–2015"),
            ("Mac mini", "Середина 2010–2014"), ("Mac Pro", "Середина 2010, 2012, конец 2013")
        ] + (id == "10.13" ? [("iMac Pro", "2017")] : []), id == "10.13" ? "111944" : "111988")
        case "10.8", "10.9", "10.10", "10.11":
            let year = ["10.8": "2013", "10.9": "2014", "10.10": "2015", "10.11": "2016"][id]!
            return entry([
                ("MacBook Pro", "Середина / конец 2007–\(year)"), ("MacBook Air", "Конец 2008–\(year)"),
                ("MacBook", "Алюминиевый: конец 2008; белый: начало 2009 и новее"),
                ("iMac", "Середина 2007–\(year)"), ("Mac mini", "Начало 2009 и новее"),
                ("Mac Pro", "Начало 2008 и новее; для El Capitan также 2007"), ("Xserve", "Начало 2009")
            ], ["10.8": "112002", "10.9": "111960", "10.10": "111991", "10.11": "111989"][id]!,
            note: "Поддерживаются перечисленные поколения Intel Mac, выпущенные до следующей системы. MacBook Retina 12″ (2015) работает с Yosemite и El Capitan; модель 2016 — с El Capitan. Точная сборка зависит от модели.")
        case "10.7": return entry([
            ("MacBook Pro", "Конец 2006–середина 2012, Core 2 Duo / Core i5 / Core i7"),
            ("MacBook Air", "2008–середина 2012"), ("MacBook", "Конец 2006–2010, Core 2 Duo"),
            ("Другие Intel Mac", "Core 2 Duo, Core i3/i5/i7 или Xeon; модели, поставлявшиеся с Lion или более ранней системой")
        ], "112035", note: "Lion требует 64-битный процессор Intel и 2 ГБ памяти. Первые MacBook и MacBook Pro с Core Duo, а также PowerPC Mac не поддерживаются.")
        case "10.6": return entry([
            ("MacBook Pro", "2006–начало 2011"), ("MacBook Air", "2008–конец 2010"), ("MacBook", "2006–2010"),
            ("Другие Intel Mac", "Intel iMac, Mac mini, Mac Pro и Xserve, выпущенные до Lion")
        ], "112016", note: "Snow Leopard требует Intel Mac и 1 ГБ памяти. PowerPC и Apple silicon не поддерживаются. Для моделей 2010–2011 нужен подходящий диск / обновление; Retail 10.6.3 подходит не всем.")
        case "10.5": return entry([
            ("MacBook Pro", "2006–2009"), ("MacBook Air", "2008–середина 2009"), ("MacBook", "2006–середина 2009"),
            ("PowerBook / iBook", "G4 от 867 МГц"), ("Другие Mac", "PowerPC G4 от 867 МГц, G5 или Intel; модели до Snow Leopard")
        ], "112015", note: "Leopard требует 512 МБ памяти. Последняя версия Mac OS X для PowerPC. Для новых моделей эпохи Leopard может потребоваться модельный диск.")
        case "10.4": return entry([
            ("MacBook Pro", "Intel, 2006–середина 2007: только соответствующий модельный диск"),
            ("MacBook", "Intel, 2006–середина 2007: только соответствующий модельный диск"),
            ("PowerBook / iBook", "Совместимые G3 / G4 с встроенным FireWire"),
            ("Другие Mac", "PowerPC G3 / G4 / G5 с встроенным FireWire; Intel — с диском для своей модели")
        ], "112014", note: "Retail-образ Tiger предназначен для PowerPC. Для Intel Mac нужен оригинальный модельный установщик. MacBook Air появился после Tiger и не поддерживается.")
        default: return entry([
            ("MacBook / Pro / Air", "Не поддерживаются: эти системы вышли до перехода на Intel"),
            ("PowerBook / iBook", "Совместимые PowerPC G3 / G4"),
            ("Другие Mac", id == "10.3" ? "PowerPC G3 / G4 / G5 с встроенным USB; Beige G3 и PowerBook G3 Kanga не поддерживаются" : "Совместимые PowerPC G3 / G4; Beige Power Mac G3 поддерживается, PowerBook G3 Kanga — нет")
        ], "102662", note: "Это системы для PowerPC Mac. Для Jaguar модельные сборки также поддерживают ранний Power Mac G5. Сверяйте конкретный Mac и версию носителя: более новый компьютер не запускает более старую систему.")
        }
    }
}
