# OldPhoneDeck · Agent Panel — Tasarım

**Tarih:** 2026-11-04
**Durum:** Review bekliyor
**Sahip:** Ali İhsan Separ
**Temel:** [GLAUCOMA82/OldPhoneDeck](https://github.com/GLAUCOMA82/OldPhoneDeck) (MIT) fork'u
**Hedef cihaz:** iPhone 8 Plus (iOS 16.7.x), yatay 736×414 pt, Mac'e Wi-Fi ile bağlı; kablo yalnızca şarj için.

---

## 1. Niyet

Kullanıcının günlük telefonu olan iPhone 8 Plus, masada şarjda dururken tek ekranda iki iş görsün:

1. **Deck:** 7 uygulama + “Take note” tuşu; dokununca Mac'te uygulama açılsın.
2. **Agent paneli:** Claude Code, Codex ve OpenCode oturumlarının hangi projede, ne durumda ve en son ne zaman aktif olduğu görünsün.

Amaç, agent'lara bakmak için terminale/pencereye geçme ihtiyacını azaltmak. Telefonda uygulama kurulmayacak, jailbreak yok, bulut yok, agent'ların çalışma biçimi değişmeyecek.

---

## 2. Bugünkü durum

OldPhoneDeck tek bir Swift executable'ı (bağımlılık yok) ve tek bir ES5 HTML sayfasından oluşuyor.

- `Sources/oldphonedeck/main.swift` — rotalar, token, açılış.
- `HTTPServer.swift` — Network.framework tabanlı minimal HTTP/1.1 sunucu.
- `Control.swift` — uygulama listeleme/açma, Claude deep link'i, sentetik tuş.
- `Music.swift`, `Stats.swift`, `PhoneMedia.swift`, `TLS.swift`.
- `web/index.html` — 797 satır; 8 tuş, now playing, internet, batarya, Phone sekmesi.
- Portlar: HTTP 8045, HTTPS 8047, WSS 8048. Sunucu tüm arayüzleri dinler; her istek `?k=<token>` ister.
- Token: `~/.oldphonedeck/token`; uygulama listesi: `~/.oldphonedeck/launcher.json`.
- iPhone 8 Plus'ta `modern` algılanır (`'isSecureContext' in window`), yatayda stage 568×320'ye ölçeklenir.
- Build doğrulandı: `swift build -c release` → 11 sn, hatasız (macOS 27, Swift 6.2.4).

Mevcut sayfa `/stats`'ı 2 sn'de bir polling ediyor. Uygulama açma, müzik kontrolü, kamera/mikrofon akışı çalışıyor; biz deck davranışını bozmayacağız.

---

## 3. Hedefler / Hedef olmayanlar / Anti-hedefler

### Hedefler

- **G1:** iPhone 8 Plus yatayda, tek ekranda 8 tuş + 5 agent satırı; taşma yok, okunabilir.
- **G2:** Agent paneli 2–3 sn'de bir güncellenir; deck tuşları ve now playing bundan etkilenmez.
- **G3:** Veri yalnızca yerelden, salt-okunur kaynaklardan gelir: Claude Code JSONL, Codex rollout JSONL, OpenCode SQLite.
- **G4:** v1'de hook, plugin, agent ayarı değişikliği yok. Kurulum yalnızca repo + çalıştırma + telefonda Home Screen.
- **G5:** Bir kaynak yoksa/bozuksa deck çalışmaya devam eder; panel “veri yok” durumunu açıkça gösterir.
- **G6:** Tek binary; yeni bir servis/port yok. SQLite için sistemdeki `libsqlite3` kullanılır (`import SQLite3` doğrulandı).
- **G7:** Token korumalı, LAN'a kapalı, port-forward gerektirmeyen kurulum; login'de otomatik başlatma opsiyonu.

### Hedef olmayanlar (v1)

- Telefondan tool çağrısı **onaylamak/reddetmek**.
- Agent'a prompt/komut göndermek.
- Terminaldeki tam sekmeye dönmek (v1'de proje klasörünü açar).
- Kamera/mikrofon/sesli not (Phone sekmesi kod olarak kalır; kurulumu yapılmaz).
- Windows/Linux desteği.
- Scrum rolleri (PM/coder/QA) veya `docs/board.md` panosu.
- Telefonda tam transcript/chat görünümü.
- Native iOS uygulaması.

### Anti-hedefler

- Bulut servisi, API anahtarı veya telemetri.
- Varsayılan olarak ham prompt/kod göstermek (proje adı + kısa aksiyon yeterli).
- Agent polling'i yüzünden deck'in gecikmesi veya telefonun pilinin hızlı tükenmesi.
- Open Island veya başka bir üçüncü parti uygulamaya bağımlı olmak.
- Çalışan deck'i yeniden yazmak.

---

## 4. Kısıtlar

- macOS 14+ (kullanıcıda macOS 27), Swift 6.2.4, Xcode kurulu.
- iPhone 8 Plus: 414×736 pt, yatay 736×414; iOS 16.7.x Safari; Home Screen standalone; çentik yok.
- Veri Wi-Fi'dan gider; kablo yalnızca güç. Mac ve telefon aynı LAN'da olmalı.
- Mac IP'si değişebilir; `.local` (Bonjour) yedeği faydalı olur.
- Mevcut UI ES5; yeni UI de ES5 uyumlu kalmalı (build step yok, eski iPhone uyumu korunur).
- Agent dosya formatları gayriresmî ve sürümle değişebilir; her adapter hata durumunda susmalı.
- Mac uyursa telefon bağlantıyı kaybeder; kurulumda uyku davranışı bilinçli seçilmeli.
- iPhone 8 Plus'ta sistem status bar'ı (≈20 pt) standalone modda deck'in kendi saatine çarpabilir; cihazda test edilecek.

---

## 5. Değerlendirilen yaklaşımlar

### A. OldPhoneDeck'i fork'la, içine ekle — **seçilen**

Swift sunucuya `Agents.swift` + `GET /agents`; HTML'e sağ agent kolonu. Mevcut launcher/music/stats korunur, tek binary kalır.

- **Artı:** En az yeni hareketli parça; hazır özellikler korunur; tek port/token; hızlı.
- **Eksi:** ES5 HTML dosyası büyür; agent ayrıştırma Swift'te yazılır.

### B. Deck aynı kalsın, ayrı agent servisi

Node/Python küçük bir dashboard; telefonda iki sayfa veya iframe.

- **Artı:** Agent mantığı izole, modern stack, hızlı iterasyon.
- **Eksi:** İki servis/port, ayrı token/CORS, telefonda geçiş; “yanında” hissi zayıf; iki ayrı hata modu.
- **Neden değil:** 3 kaynak için ek servis maliyeti faydasından büyük.

### C. Sıfırdan tek web app

React/Next + küçük backend; launcher, icon render, music, stats yeniden yazılır.

- **Artı:** En temiz mimari ve UI.
- **Eksi:** 1–2 hafta; mevcut çalışan davranışları port etme riski; kullanıcıya ek fayda yok.
- **Neden değil:** Problem mimari değil, panelin varlığı.

### Alt karar: agent verisi

v1'de **dosya/DB okuma** (hook yok). v2'de gerçek “onay bekliyor” ve telefondan approve/deny için hook/plugin push eklenir. v1'in `/agents` sözleşmesi v2'ye hazır tasarlanır (status alanı genişletilebilir).

---

## 6. Mimari

```
iPhone 8 Plus (Safari PWA)
  ├─ GET  /              deck HTML (mevcut)
  ├─ GET  /stats        2 sn (mevcut)
  ├─ GET  /agents       3 sn (yeni)
  ├─ POST /launch       (mevcut)
  ├─ POST /claude       (mevcut)
  └─ POST /media        (mevcut)

Mac: oldphonedeck (tek Swift binary)
  ├─ HTTPServer (Network.framework, token)
  ├─ Agents.swift
  │   ├─ ClaudeSource   ~/.claude/projects/**/*.jsonl      (tail)
  │   ├─ CodexSource    ~/.codex/sessions/**/rollout-*.jsonl (tail)
  │   └─ OpenCodeSource ~/.local/share/opencode/opencode.db (SQLite readonly)
  ├─ Stats / Music / PhoneMedia (mevcut)
  └─ ~/.oldphonedeck/{token, launcher.json, agents.json}
```

### 6.1 Yeni dosyalar

- `Sources/oldphonedeck/Agents.swift` — model, store, kaynak protokolü, üç adapter, JSON üretimi.
- `Sources/oldphonedeck/AgentSources/ClaudeSource.swift`
- `Sources/oldphonedeck/AgentSources/CodexSource.swift`
- `Sources/oldphonedeck/AgentSources/OpenCodeSource.swift`
- `Tests/` veya `--dump-agents` (aşağıda test bölümü).
- `scripts/install-launchd.sh`, `scripts/uninstall-launchd.sh` (opsiyonel ama önerilir).
- `docs/` kullanıcı kurulum notu.

Dosya bölünmesi zorunlu değil; `Agents.swift` tek dosyada da kalabilir. Builder'ın kararı.

### 6.2 HTTP sözleşmesi

`GET /agents?k=<token>` → 200, `application/json`:

```json
{
  "updated": 1793822052,
  "refreshSeconds": 3,
  "sources": {
    "claude": "ok",
    "codex": "missing",
    "opencode": "ok"
  },
  "agents": [
    {
      "id": "opencode:ses_e711bbf6",
      "provider": "opencode",
      "project": "kresim",
      "path": "/Users/aliihsansepar/projects/kresim",
      "title": "Dosya içeriğini inceleme",
      "status": "working",
      "lastActivity": 1793822438,
      "ageSeconds": 12,
      "sessionId": "ses_e711bbf6",
      "detail": "read · main.swift"
    }
  ]
}
```

- `sources`: `"ok" | "missing" | "error"`; UI “veri yok” durumunu buna göre gösterir.
- `agents`: en fazla 20 döner; UI 5 gösterir. Sıra: `working` → `idle` → `stale`, sonra `lastActivity` azalan.
- `title` ve `detail` kısa (≤60 karakter), ham kod/prompt içermez.
- Token yoksa/yanlışsa mevcut davranış: 403.

`POST /focus?k=<token>` (v1):

- Body: `id=<agent id>`.
- v1 davranışı: ilgili `path`'i Finder'da açar (`NSWorkspace.activateFileViewerSelecting`); bilinmeyen id → 404.
- v2: terminal sekmesine hassas dönüş; Open Island varsa onun jump-back'i değerlendirilir.

### 6.3 Agent modeli

```swift
struct AgentSession {
    let id: String            // "claude:<sessionId>"
    let provider: String      // claude | codex | opencode
    let project: String       // path'in son bileşeni
    let path: String          // cwd / directory
    let title: String?        // ajan üretimi başlık veya kısa aksiyon
    let detail: String?       // "Edit · main.swift" gibi
    let status: AgentStatus   // working | idle | stale | unknown
    let lastActivity: Date
    let sessionID: String
    let sourcePath: String
}
```

`AgentStatus`:
- `working`: son 120 sn içinde aktivite var **ve** son olay bir turun sürdüğünü gösteriyor (assistant tool_use, user tool_result, assistant mesajı).
- `idle`: son olay tur sonu (`turn_duration`, `away_summary`, `last-prompt`, `cost-state`, Codex `task_complete`) veya 10 dk'dan eski.
- `stale`: 1 saatten eski.
- `unknown`: format çözülemedi.

UI'da `working` yeşil, `idle` gri, `stale` koyu gri. “Onay bekliyor” v1'de yok; amber durum v2 hook'larıyla gelir. Bu yüzden satırda durum noktasından çok **“son aktivite”** metni güvenilir kaynak olarak öne çıkar.

### 6.4 Kaynak adapter'ları

#### ClaudeSource

- Glob: `~/.claude/projects/*/*.jsonl`.
- Filtre: mtime son 24 saat; dosya boyutu > 0.
- Okuma: dosyanın son 64 KB'ı (tam dosyayı okuma); satır satır JSON parse; son geçerli satırlar.
- Çıkarım:
  - `sessionId` (satırda veya dosya adında).
  - `cwd` (varsa; yoksa proje klasörü adından).
  - `timestamp`.
  - Son olay tipi: `assistant` + `tool_use`, `user` + `tool_result`, `assistant` + `text`, `system` (`turn_duration`, `stop_hook_summary`, `away_summary`), `last-prompt`, `cost-state`, `ai-title`.
  - `message.content` içinden son tool adı (`Edit`, `Bash`, `Read`…) veya kısa metin.
  - `title`: transcript'teki son `ai-title` kaydı (`{"type":"ai-title","aiTitle":"…"}`). Yoksa `nil`; ham kullanıcı prompt'u varsayılan olarak gönderilmez.
  - `detail`: son tool adı + dosya adı (varsa), ≤60 karakter.
- Sidechain (`isSidechain: true`) satırları ana oturum durumunu belirlemede kullanılmaz; ileride “2 subagent” rozeti için sayılabilir.
- `working` kuralı: son olay `assistant/tool_use` veya `user/tool_result` ve `age < 120 sn`.
- `idle` kuralı: son olay `system/turn_duration`, `system/away_summary`, `last-prompt`, `cost-state` veya `age > 10 dk`.
- Not: Claude Code “Notification” (onay bekliyor) durumu transcript'e yazılmaz; v1'de gösterilemez.

#### CodexSource

- Glob: `~/.codex/sessions/**/rollout-*.jsonl`.
- Filtre: mtime son 24 saat.
- Okuma: son 64 KB; `session_meta` (cwd, id), `event_msg` (`task_started`, `task_complete`, `agent_message`), `response_item` (message/tool çağrısı).
- `working`: son lifecycle `task_started` ve `task_complete` yok; `idle`: son `task_complete`.
- `title`: `session_meta`'daki başlık/originator; yoksa `nil`. Ham kullanıcı prompt'u varsayılan olarak gönderilmez.
- `detail`: son tool adı / `item_completed`.

#### OpenCodeSource

- DB: `~/.local/share/opencode/opencode.db`, `SQLITE_OPEN_READONLY`, `busy_timeout=100ms`.
- **Şema seçimi:** `sqlite_master`'da `session_v2` + `session_message` varsa **v2** kullanılır (kurulu OpenCode 2.2.5 bunu yazıyor); yoksa eski `session` + `message` tablolarına düşülür. v2 önceliklidir.
- v2 sorgusu:
  ```sql
  select s.id, s.parent_id, s.directory, s.title,
         s.time_created, s.time_updated, s.time_archived,
         s.time_busy, s.time_idle, p.name as project_name
  from session_v2 s
  left join project p on p.id = s.project_id
  where s.time_archived is null
  order by s.time_updated desc
  limit 20;
  ```
- `parent_id` dolu olan child/subagent oturumları ana listeye alınmaz; ana satırda “+N” rozeti için sayılır (opsiyonel).
- Durum v2: `time_idle` boş **veya** `time_busy > time_idle` → `working`; aksi halde `idle`; `time_updated` > 1 saat → `stale`.
- `title`: `session_v2.title` (OpenCode'un ürettiği başlık); `detail`: son `session_message` (`type=assistant`/tool) içinden tool adı veya `agent`; ham içerik gönderilmez.
- Legacy sorgusu: `session` + `message`; `data` JSON'unda `role`, `time.completed`, `finish`; aynı durum kuralları (`time.completed` yoksa working, doluysa idle).
- `project`: `project.name` doluysa o; değilse `directory` basename. `directory` bilinen bir workspace köküyse (`projects`, `Desktop`, `Documents`, ev dizini) `session_v2.title`'ın kısaltılmışı proje etiketi olur.
- Şema değişirse adapter `error` döner; deck çalışmaya devam eder. Alternatif yedek: `opencode api` / yerel server API; v1'de DB yeterli.

### 6.5 Store ve performans

- `AgentStore` ayrı bir utility queue'da `DispatchSourceTimer` ile 3 sn'de bir tarar.
- Sonuç `NSLock` ile korunan tek bir snapshot'ta tutulur; HTTP route sadece snapshot'ı JSON'a çevirir (hızlı).
- Dosya başına `(path, mtime, size)` cache: değişmeyen dosya yeniden okunmaz.
- Aynı proje etiketinde birden fazla oturum varsa: en son aktif olan satırda gösterilir; UI'da “+N” rozeti (opsiyonel).
- Child/subagent oturumları (Claude `isSidechain`, OpenCode `parent_id`) ana listeye alınmaz; ana satırda “+N” olarak sayılır.
- Proje etiketi: cwd/directory basename; bilinen workspace kökünde (`projects`, `Desktop`, `Documents`, ev dizini) oturum başlığı (≤28 karakter); git repo varsa repo kökü adı tercih edilir.
- İlk açılışta tarama bir kez hemen çalışır; sonra 3 sn.
- CPU hedefi: boşta < %2; `/agents` cache'ten < 50 ms.

---

## 7. UI / yerleşim (seçilen A)

### 7.1 Stage

iPhone 8 Plus yatay: 736×414 pt. Mevcut `fit()` mantığı stage'i 568×320 yapar ve 1.29× ölçekler. Yeni layout `W >= 520` olduğunda “wide landscape” dalına girer; dar ekranlarda eski layout korunur.

### 7.2 Wide landscape yerleşimi

```
┌──────────────────────────────────────────────────────────────┐
│ 21:42  ÇAR 4 KASIM                    ● MacBook Pro  🔋 72%  │  status 24
│ ┌──────────────────────────────┐  ┌────────────────────────┐ │
│ │  [Safari] [Terminal] [VS Code] [Spotify]                 │ │
│ │  [Finder] [Claude]   [Notlar]  [Take note]               │ │  keys 2×4
│ │                                                          │ │
│ │  ♪  Kış Güneşi — Tarkan        ⏮ ⏸ ⏭                    │ │  music 56
│ └──────────────────────────────┘  │ AGENTS      2 ÇALIŞIYOR│ │
│                                   │ ● Claude · mmxss  12sn │ │
│                                   │ ● OpenCode · media 1dk │ │
│                                   │ ○ Codex · bist-bot 3dk │ │
│                                   │ ○ Claude · amed   22dk │ │
│                                   │ ○ Codex · 3d-tour  1sa │ │
│                                   └────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

Ölçüler (stage 568×320):
- Sol kolon: `left 14`, `top 46`, `width 312`.
- Tuşlar: 4 sütun; cap 66×66, sütun arası 10, satır arası 10; 2 satır. Label 10 pt. Toplam yükseklik ≈ 190.
- Now playing: `left 14`, `top 242`, `width 312`, `height 58`; art 38, başlık/artist, progress, 3 kontrol.
- Sağ kolon: `right 14`, `top 46`, `width 218`, `height 258`; agent kartı.
  - Header: “AGENTS” + yeşil pill “2 ÇALIŞIYOR”.
  - 5 satır × ~42 pt: sol status dot, üstte `provider · project`, altta `detail`, sağda `12 sn`.
  - Footer: “dokun → projeyi aç” (v1) veya “son 24 saat”.
- Status bar: mevcut `#status`; Mac adı, link dot, telefon bataryası. Net/batarya detayları ikinci “Sistem” görünümüne taşınır.
- “Sistem” görünümü: mevcut internet/batarya kartları; status bar'daki saate veya küçük bir ⌄'ye dokununca açılır. Deck ve agent paneli ana ekranda kalır.
- Telefon dikey çevrilirse: mevcut portrait layout; agent paneli tuşların altına 3 satır olarak iner (fallback, detay builder'a).

### 7.3 Görsel dil

- Mevcut koyu tema, 18 pt radius, ince inner stroke korunur.
- Status renkleri: `#30d158` çalışıyor, `#8e8e93` boşta, `#636366` stale; amber `#ffd60a` yalnızca v2 “onay bekliyor”.
- Agent satırında provider ikonu yerine renkli küçük harf rozeti (C/X/O) kullanılabilir; marka ikonları gerekmez.
- Uzun proje adları ellipsis; satır yüksekliği sabit; taşma yok.
- Dokunma hedefleri ≥ 40 pt.

### 7.4 Davranış

- `/agents` poll: 3 sn; sadece deck görünümü aktifken ve `document.hidden === false` iken.
- Bağlantı koparsa: son snapshot grileşir, status bar'daki link dot kırmızı; 2 sn'de bir yeniden dene.
- Boş durum: “Agent verisi yok — Claude/Codex/OpenCode klasörlerini kontrol et.”
- Tek kaynak bozuksa: diğer satırlar görünür; footer'da “Codex: veri yok”.
- Satıra dokunma (v1): `POST /focus` → Finder'da proje klasörü. Uzun basma: detay sheet (session id, path, son aksiyon).
- Tuş davranışı mevcut gibi kalır: tap = aç, long-press = uygulama seç.
- “Take note” mevcut Claude deep link'ini korur.

### 7.5 ES5 uyumu

- Yeni JS'de `var`, `function`, `XMLHttpRequest`; arrow/let/template literal yok.
- CSS'te `display:flex` kullanılabilir; `gap` kullanılmaz (iOS 9 uyumu için margin). iPhone 8 Plus iOS 16'da zaten sorun değil; eski telefon desteği bozulmasın.
- `fetch` kullanılmaz; mevcut `xhr()` yardımcısı kullanılır.

---

## 8. Konfigürasyon ve işletim

### 8.1 `~/.oldphonedeck/agents.json`

```json
{
  "enabled": true,
  "maxRows": 5,
  "refreshSeconds": 3,
  "lookbackHours": 24,
  "redactTitles": false,
  "sources": {
    "claude": { "enabled": true },
    "codex": { "enabled": true },
    "opencode": { "enabled": true }
  },
  "excludeProjects": ["scratchpad"]
}
```

- Dosya yoksa varsayılanlar kullanılır; sıfır konfigürasyonla çalışır.
- `refreshSeconds` 2–10 arası sınırlandırılır.
- `redactTitles: true` → `title`/`detail` yerine yalnızca proje adı gösterilir.

### 8.2 Çalıştırma

```bash
git clone <fork> oldphonedeck-agents
cd oldphonedeck-agents
swift build -c release
.build/release/oldphonedeck
```

- Çıktı: `http://<mac-ip>:8045/#k=<token>` ve `http://<hostname>.local:8045/#k=<token>`.
- Telefonda Safari → Share → Add to Home Screen.
- Auto-Lock: Never; Guided Access açık; parlaklık sabit.
- Mac'te Accessibility (Take note için) ve Automation (Spotify/Music) izinleri mevcut akıştaki gibi.

### 8.3 launchd (önerilir)

- `~/Library/LaunchAgents/com.aliihsan.oldphonedeck.plist`
- `RunAtLoad=true`, `KeepAlive=true`, `StandardOutPath=~/Library/Logs/oldphonedeck.log`.
- Opsiyonel `--keep-awake`: `caffeinate -i` ile sarılır veya Swift'te `ProcessInfo.beginActivity`. Varsayılan kapalı; kullanıcı isterse açılır.
- `scripts/install-launchd.sh` idempotent; `uninstall-launchd.sh` temizler.

### 8.4 Ağ

- Sunucu tüm arayüzleri dinler; token zorunlu.
- IP değişirse `.local` adresi veya router'da DHCP reservation önerilir.
- `lanAddress()` şu an yalnızca `en0` IP'sini yazdırıyor; `.local` ve tüm `en*` adreslerini yazdırmak küçük bir iyileştirme (özellikle USB tethering gerekmez, ama faydalı).
- QR kod opsiyonel; v1'de terminale URL yazmak yeterli.

---

## 9. Güvenlik ve gizlilik

- Token her API çağrısında; token dosyası `chmod 600`.
- LAN'daki token'ı bilen biri uygulama açabilir; URL password gibi davranılır, port-forward yapılmaz.
- Agent paneli varsayılan olarak yalnızca proje adı + kısa aksiyon gösterir; ham kod/prompt gösterilmez. `redactTitles` ile daha da kısılabilir.
- Veri Mac'ten dışarı çıkmaz; üçüncü parti servis yok.
- Open Island/CodexBar gibi uygulamalara bağımlılık yok; isteğe bağlı zenginleştirme ileride.
- Loglarda token/agent içeriği yazdırılmaz.

---

## 10. Hata modları ve geri dönüşler

| Durum | Davranış |
|---|---|
| Kaynak klasörü yok | `sources.<x>="missing"`; diğerleri gösterilir |
| JSONL yarım yazılmış | Son tamamlanmamış satır atlanır; parse hatası yutulur |
| DB kilitli | `busy_timeout=100ms`; olmazsa son snapshot korunur |
| Dosya çok büyük | Son 64 KB okunur; `(mtime,size)` cache |
| Agent 24 saatten eski | Listeye alınmaz |
| Telefon Wi-Fi koptu | Son snapshot gri; link dot kırmızı; 2 sn retry |
| Sunucu çöktü | launchd `KeepAlive` yeniden başlatır |
| Mac uyudu | Telefon “bağlantı yok” gösterir; `--keep-awake` opsiyonu |
| Aynı projede çok oturum | En son aktif gösterilir; “+N” rozeti opsiyonel |
| OpenCode şema değişti | Adapter `error`; deck çalışır; yedek olarak `opencode api` |

---

## 11. Test ve kabul kriterleri

### Otomatik / CLI

- `swift build -c release` temiz.
- `curl -s 'http://localhost:8045/agents?k=<token>' | jq` geçerli JSON; `sources` ve `agents` alanları var.
- Token'sız istek 403.
- `POST /focus` doğru klasörü Finder'da açar; bilinmeyen id → 404.
- `--dump-agents` (önerilir): fixture klasörleriyle üç adapter'ın çıktısını JSON olarak basar; CI/manual test kolay.
- Performans: boşta CPU < %2; `/agents` cache yanıtı < 50 ms.
- 10 dakika açık kalma: bellek artışı yok, dosya tanıtıcısı sızıntısı yok.

### Cihaz (iPhone 8 Plus)

- Home Screen'den açılış < 2 sn; tam ekran; döndürmede bozulma yok.
- 8 tuş doğru uygulamayı açıyor; long-press seçici çalışıyor.
- Agent paneli 5 satır; uzun proje adları ellipsis; dokunma hedefleri rahat.
- Wi-Fi kapat/aç → panel yeniden bağlanıyor; deck donmuyor.
- Telefon kilitlenip açıldığında sayfa kaldığı yerden devam ediyor (PWA reload olursa kabul edilebilir).
- 30 dakika şarj + açık ekran: cihaz aşırı ısınmıyor; batarya yüzdesi makul.
- Status bar çakışması yok (varsa 20 pt offset).

### Fixture'lar

- Claude: sonu `turn_duration` ile biten ve sonu `tool_use` ile biten iki örnek.
- Codex: `task_started` ve `task_complete` örnekleri.
- OpenCode: kopya DB veya v2 (`session_v2`/`session_message`) ve legacy (`session`/`message`) satırları içeren minimal SQLite fixture.

---

## 12. Efor ve riskler

### Efor (tek geliştirici, tanıdık codebase)

| İş | Tahmin |
|---|---|
| Fork + derleme + iskelet | 0.5 gün |
| Üç adapter + `/agents` + cache | 1 gün |
| UI wide layout + polling + durumlar | 1 gün |
| Cihaz testi + launchd + dokümantasyon | 0.5–1 gün |
| **Toplam v1** | **3–4 gün** |
| v2 hook/approve/jump-back | +5–7 gün |

### Riskler

- **Durum heuristic'i:** “çalışıyor/boşta” yanlış olabilir; UI'da “son aktivite” ana bilgi, dot ikincil. Gerçek “onay bekliyor” v2.
- **OpenCode şeması:** sürümle değişebilir; adapter izole, hata durumunda susar.
- **Claude/Codex formatları:** gayriresmî; tail parser kırılgan olabilir; fixture testleri şart.
- **iPhone 8 Plus status bar / safe area:** cihazda test; 20 pt offset gerekebilir.
- **Wi-Fi IP değişimi:** `.local` ve DHCP reservation.
- **7/24 şarj:** batarya sağlığı; havalandırmalı stand, mümkünse akıllı priz; iOS Optimized Charging.
- **Mac uykusu:** panel kopar; `--keep-awake` opsiyonu.
- **Gizlilik:** proje adları ekranda; `redactTitles` ve ekran kilidi.
- **Hook çakışması:** v1'de hook yok; v2'de mevcut Open Island hook'larıyla uyum test edilmeli.

---

## 13. Builder'a bırakılanlar

- `Agents.swift`'in tek dosya mı, `AgentSources/` klasörü mü olacağı.
- Test için ayrı SwiftPM test target'ı mı, `--dump-agents` + fixture mı.
- Wide layout'un tam piksel ayarları (cap 64–68, satır yüksekliği 40–44).
- “Sistem” görünümünün adı ve geçiş yeri (saat, ⌄ veya küçük ikon).
- launchd etiketi ve log yolu.
- QR kod / `.local` URL gösterimi (opsiyonel).
- Portrait fallback'in agent satır sayısı.

---

## 14. Konuşmada verilen kararlar

- **A yaklaşımı** seçildi: OldPhoneDeck fork'u, içine agent paneli.
- **A yerleşimi** seçildi: deck solda, agentlar sağda, now playing alt şeritte.
- Veri **Wi-Fi**'dan; kablo yalnızca şarj.
- v1 **salt görüntüleme**; onay/komut yok.
- Hedef cihaz **iPhone 8 Plus**, yatay.
- Kamera/mikrofon/sesli not v1 kapsamı dışı.

---

## 15. Review sonrası verilen kararlar

Builder review'unda çıkan beş soru şöyle kapatıldı:

- **OpenCode şeması:** v2 (`session_v2` + `session_message`) öncelikli; eski `session`/`message` tabloları fallback. Kurulu 2.2.5 v2 yazıyor; v1 adapter'ı ikisini de tanır.
- **Child/subagent oturumları:** ana listeye alınmaz; `parent_id`/`isSidechain` ile ayrılır, ana satırda “+N” olarak sayılır.
- **Proje etiketi:** workspace kökünde (`projects`, `Desktop`, `Documents`, ev dizini) oturum başlığı; aksi halde klasör/repo adı.
- **Başlık gizliliği:** `title` ajan üretimi başlık (Claude `ai-title`, OpenCode `session.title`); ham kullanıcı prompt'u varsayılan olarak gönderilmez, `redactTitles` başlığı da gizler.
- **Tap davranışı:** `/focus` v1 kapsamında; Finder'da proje klasörünü açar, terminal jump v2.

---

## 16. Onay kapısı

Bu doküman onaylanmadan kod yazılmayacak. Onaydan sonra sıradaki adım: implementation plan (`writing-plans`), sonra küçük dilimlerle geliştirme.
