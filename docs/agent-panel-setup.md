# Agent Panel Kurulumu

Bu fork, OldPhoneDeck'in 8 tuşlu deck'inin yanına Claude Code, Codex ve OpenCode oturumlarını gösteren salt-okunur bir panel ekler. Telefonda uygulama kurulmaz; iPhone 8 Plus Safari'de Home Screen uygulaması olarak çalışır.

## Gereksinimler

- macOS 14+ ve Xcode Command Line Tools (`xcode-select --install`).
- iPhone 8 Plus (iOS 16.x) ve Mac aynı Wi-Fi ağında.
- Mac'te repo: `~/projects/oldphonedeck-agents`.
- Kablo yalnızca şarj içindir; veri Wi-Fi'dan gider.

## İlk çalıştırma

```bash
cd ~/projects/oldphonedeck-agents
swift build -c release
.build/release/oldphonedeck
```

Terminalde şuna benzer bir adres yazar:

```
http://192.168.x.x:8045/#k=<token>
```

Telefonda Safari'de aç, **Share → Add to Home Screen** yap. Home Screen'den açınca tam ekran çalışır.

İlk açılışta tuşlar boş olabilir. **Herhangi bir tuşa uzun bas** ve 7 uygulamanı seç. Seçim `~/.oldphonedeck/launcher.json` dosyasına yazılır.

## Telefon ayarları

- **Settings → Display & Brightness → Auto-Lock → Never.**
- **Settings → Accessibility → Guided Access** aç; deck açıkken yan tuşa üç kez basıp kilitle. Böylece yanlışlıkla çıkmaz.
- Şarjda ve havalandırmalı bir standta tut. 7/24 %100 şarj batarya sağlığını zamanla etkiler.

## Agent paneli

Panel 3 sn'de bir yenilenir; son 24 saatteki oturumlardan en fazla 5 satır gösterir. Satırda sağlayıcı + proje, kısa son aksiyon ve son aktivite süresi vardır. Satıra dokununca proje klasörü Finder'da açılır.

Veri kaynakları (hepsi salt-okunur):

- Claude Code: `~/.claude/projects/**/*.jsonl`
- Codex: `~/.codex/sessions/**/rollout-*.jsonl`
- OpenCode: `~/.local/share/opencode/opencode.db` (v2 `session_v2`/`session_message`; eski `session`/`message` fallback)

### `~/.oldphonedeck/agents.json`

Dosya yoksa varsayılanlar kullanılır. Örnek:

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
  "excludeProjects": ["scratch"]
}
```

- `redactTitles: true` → proje adı kalır, başlık/aksiyon gizlenir.
- `maxRows` 1–10 arası; panelde en fazla o kadar satır gösterilir.
- `refreshSeconds` 2–10 arası.
- `excludeProjects` tam proje adıyla eşleşir.

### Durumlar

- Yeşil: son 2 dakikada aktif.
- Gri: boşta.
- Koyu gri: 1 saatten eski.
- Amber “onay bekliyor” v1'de yok; hook tabanlı v2'de gelecek.

Durum tahminidir; kesin bilgi için satırdaki “son aktivite” süresine bak. Claude Code'da tool onayı bekleyen oturum transcript'e yazılmadığı için v1'de “onay bekliyor” görünmez.

## Otomatik başlatma (launchd)

```bash
bash scripts/install-launchd.sh
```

Log: `~/Library/Logs/oldphonedeck.log`.
Durdurmak için:

```bash
bash scripts/uninstall-launchd.sh
```

Script, `.build/release/oldphonedeck` yoksa hata verir; önce build et.

Mac uyursa telefon bağlantıyı kaybeder. Masada sürekli açık kalacaksa:

```bash
caffeinate -i
```

veya launchd çalıştırırken `caffeinate` ile sarmalayabilirsin (v2'de `--keep-awake` opsiyonu).

## Güvenlik

- URL'deki `k=<token>` bir şifredir. Aynı Wi-Fi'daki token'ı bilen biri Mac'te uygulama açabilir.
- Port-forward yapma; internete açma.
- Token'ı değiştirmek için `~/.oldphonedeck/token` dosyasını sil, sunucuyu yeniden başlat.
- Agent paneli varsayılan olarak ham kod/prompt göstermez; yalnızca proje ve kısa aksiyon.

## Sorun giderme

| Belirti | Çözüm |
|---|---|
| Telefon sayfayı açmıyor | Aynı Wi-Fi'da mı? Mac IP'si değişti mi? Terminaldeki yeni adresi kullan. |
| Panel boş | `--dump-agents` çalıştır; `sources` alanında hangi kaynağın `missing/error` olduğuna bak. |
| Panel eski veri gösteriyor | Sağ üstteki bağlantı noktası kırmızıysa sunucu/Mac uyumuştur; sunucuyu yeniden başlat. |
| macOS firewall | İlk bağlantıda “Allow incoming connections” sorarsa izin ver. |
| Tuşlar boş | Bir tuşa uzun bas, 7 uygulamayı seç. |
| Kamera/mikrofon | Bu fork'un v1 kapsamı değil; HTTPS sertifikası kurulumu gerekir. |
