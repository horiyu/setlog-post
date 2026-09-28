# setlog-post

好きな動画を、Android エミュレータのカメラ越しに [setlog](https://setlog.kr/) の自分のルームへ投稿する。
この PC の他のプログラムから呼ぶ共通部品。

setlog はその場でカメラを回して撮る 2 秒 Vlog アプリで、ギャラリーからの投稿機能がない。そこで PC の
Android エミュレータ（自分のアカウントでログイン済み）のカメラに動画を流し込み、setlog にそれを「撮影」させて送る。
何を流すか（画面収録、加工した動画、描き起こした映像…）は呼ぶ側が決める。setlog-post はエミュレータと
ルームの判別を受け持ち、投稿を1件ずつ順に処理する。

*Post any video to your own setlog rooms through an Android emulator's camera. A shared part for other
programs on the same PC: they hand it a video, a caption and rooms; it owns the emulator signed in to your
account, plays the video into its camera, records a Log, pastes the caption, ticks the rooms and sends, one
post at a time.*

```
呼ぶ側 ──setlog-post post video.mp4 --room vlog --caption 一言──▶ queue/ ──▶ worker.sh ──▶ post.sh
                                                                         動画をカメラの枠に嵌める
                                                                         → AVD 起動 → setlog で撮影 → 一言を貼る
                                                                         → ルームにチェック → 送信 → 電源オフ
```

## 使う前に（重要）

- setlog の利用規約（第3条）は、運営会社の許可なく自動化プログラムやスクリプトを使うことを禁じている。
  この仕組みは setlog の撮影・送信をスクリプトで操作するので、**使う前に運営会社（New Chat）の許可を得ること**。
  作者は自分の利用について許可を得ているが、それはあなたの利用を許可するものではない。
- setlog は「その場で撮る」アプリ。事前に用意した動画を送るのはアプリの趣旨から外れうるので、友人のいる
  ルームに送るときは、そういう Log だと相手に伝えておくこと。
- 作者の個人的な道具で、setlog・New Chat とは無関係。無保証。

## 呼び方

コマンドはどれも JSON を1行だけ出す。

```sh
setlog-post post <動画> [--room 名前]... [--caption 一言] [--dry] [--lead 秒] [--from 呼ぶ側の名前] [--move] [--wait [--timeout 秒]]
setlog-post status <job>       # {"state": "queued" | "running" | "done", "ok": ..., "error": ...}
setlog-post wait <job> [--timeout 秒]
setlog-post rooms              # {"default": "vlog", "rooms": ["vlog", ...]}
setlog-post info               # 動画の推奨サイズなど
```

- `post` はキューに入れて worker を起こし、すぐ `{"ok": true, "job": "..."}` を返す。`--wait` を付けると
  投稿が終わるまで待って結果を返す（終了コード 0 = 送れた）。
- `--room` は繰り返すか、カンマ区切りで複数。無ければ `DEFAULT_ROOM`。`rooms/` に無いルームはその場でエラー。
- `--dry` は送信画面まで進んでキャンセルする。試験用。
- 動画はコピーして預かる（`--move` なら移動）。呼ぶ側は `post` が返ったら元のファイルを消してよい。
- エミュレータは1台しか動かせないので、setlog-post 自身の投稿は必ず1件ずつ順番に処理される。
  setlog-post を通さずにエミュレータを動かすプログラムがあれば、そのロックファイルを `EXTRA_LOCKS` に書く。

### 動画について

| | |
|---|---|
| 大きさ | **1710×962**（エミュレータのカメラ 1710×1280 のうち setlog が使う上端 16:9 の帯）ならそのまま全面に映る。他の大きさは長辺を合わせて収め、余白は暗い灰色 |
| 長さ | Log は動画の **0 秒目から始まり、2 秒ちょっと**残る。20 秒より後は使わない |
| 向き | 横長の枠。縦長の動画は小さく収まるので、倒す・切るなどは呼ぶ側で |
| 音 | 使わない |

setlog がカメラを開いてから撮り始めるまでの約 5 秒は、先頭フレームの静止（`LEAD`、既定 5 秒）で吸収している。
見え方を作り込みたいなら、呼ぶ側で 1710×962 に描いてから渡すとよい。

## 仕組み

| ファイル | 役割 |
|---|---|
| `setlog-post` | 呼ぶ側の入口（CLI）。キューに入れる、状態を返す、ルーム一覧 |
| `worker.sh` | キューを1件ずつ `post.sh` に渡し、`done/<job>/result.json` と `post.log` を残す（直近 20 件、動画は 5 件） |
| `post.sh` | 1件の投稿。動画をカメラ用の枠にして AVD を起動し、setlog で撮って送り、電源を切る |
| `find_room.py` / `rooms.py` | 送信画面でルームをアバター画像で探す（`rooms/<ルーム名>.png`） |
| `lib/clip.py` | 一言を X のクリップボード経由でエミュレータに渡す（日本語は `adb shell input text` を通らない） |
| `bin/` | SDK の用意、エミュレータの作成・起動・正しい電源オフ、ルームの登録、点検 |

常駐はしない。`post` のたびに worker が起き、キューが空になれば終わる。エミュレータも投稿ごとに起動して止める。

## 必要なもの

- Linux の PC（X のデスクトップと KVM）
- Android SDK の emulator / platform-tools / cmdline-tools と `system-images;android-35;google_apis_playstore;x86_64`、
  JDK。`bin/setup-sdk.sh` が `sdk/` `jdk/` に入れる（既にあるならシンボリックリンクでいい）
- Python 3.10 以上（Pillow / python-xlib）と `ffmpeg`: `sudo apt install python3-pil python3-xlib ffmpeg`
- setlog（エミュレータの中で Google Play から、または自分の端末から抜いた APK を `apk/` に）

## セットアップ

1. `settings.conf.example` を `settings.conf` にコピーして編集する（初回は自動でコピーされる）。
2. `bin/setup-sdk.sh` → `bin/doctor.sh` で足りないものを確かめる。
3. AVD を作って setlog を入れる: `bin/make-avd.sh`。開いた setlog に**スマホと同じ方法で**サインインし、
   「Transfer from another device」を選んでスマホで承認し、暗号鍵を移す。既存のアカウントで
   「Create a new encryption key」は押さないこと（古い Log が読めなくなりうる）。
   終わったら `bin/stop-emu.sh`（`adb emu kill` は直前の書き込みを失う）。
4. 送り先のルームを登録する: `bin/add-rooms.sh`（何も送らずに送信画面の行を切り出す）→
   `state/rooms-new/sheet.png` を見て `bin/name-room.sh <番号> "<ルーム名>"`。
5. 試す: `./setlog-post post 動画.mp4 --room vlog --caption テスト --dry --wait`

## 記録

```sh
tail state/worker.log                 # 各ジョブの開始と結果
cat done/<job>/post.log               # 1件ぶんの詳しい経過
tail state/posts.jsonl                # 送った Log（時刻・ルーム・一言・送った量）
DRY_RUN=1 ./post.sh done/<job>        # 手でやり直す（送らずに送信画面まで）
```

各段の画面は `state/last-send.png`（一言を貼った直後）、`state/last-room.png`（ルームを選んだ直後）、
`state/last-sent.png`、失敗時は `state/last-fail.png`。

## 作者・ライセンス

作: [horiyu](https://github.com/horiyu)。[MIT License](LICENSE)。
