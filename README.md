# setlog-post

好きな動画を、Android エミュレータのカメラを通して [setlog](https://setlog.kr/) の自分のルームへ投稿する。
この PC 上の他のプログラムから呼び出す共通部品。

setlog はその場でカメラを回して撮る 2 秒 Vlog アプリで、ギャラリーの動画を投稿する機能がない。そこで PC の
Android エミュレータ（自分のアカウントでログイン済み）のカメラに動画を流し込み、setlog にそれを「撮影」させて送る。
何を流すか（画面収録、加工した動画、新たに作った映像など）は呼び出す側が決める。setlog-post はエミュレータの操作と
ルームの選択を受け持ち、投稿を1件ずつ順に処理する。

*Post any video to your own setlog rooms through an Android emulator's camera. A shared part for other
programs on the same PC: they hand it a video, a caption and rooms; it owns the emulator signed in to your
account, plays the video into its camera, records a Log, pastes the caption, ticks the rooms and sends, one
post at a time.*

```
呼び出し側 ──setlog-post post video.mp4 --room vlog --caption 一言──▶ queue/ ──▶ worker.sh ──▶ post.sh
                                                                         動画をカメラの枠に合わせる
                                                                         → AVD 起動 → setlog で撮影 → 一言を貼る
                                                                         → ルームにチェック → 送信 → 電源オフ
```

## 使う前に（重要）

- setlog の利用規約（第3条）は、運営会社の許可なく自動化プログラムやスクリプトを使うことを禁じている。
  この仕組みは setlog の撮影・送信をスクリプトで操作するので、**使う前に運営会社（New Chat）の許可を得ること**。
  作者は自分の利用については許可を得ているが、その許可はあなたの利用には及ばない。
- setlog は「その場で撮る」アプリ。事前に用意した動画を送るのはアプリの趣旨から外れるおそれがあるので、友人がいる
  ルームに送るときは、そのような Log であることを相手に伝えておくこと。
- 作者が個人で作った道具で、setlog・New Chat とは無関係。無保証。

## 使い方

コマンドはどれも JSON を1行だけ出す。

```sh
setlog-post post <動画> [--room 名前]... [--caption 一言] [--dry] [--lead 秒] [--from 呼び出し側の名前] [--move] [--wait [--timeout 秒]]
setlog-post status <job>       # {"state": "queued" | "running" | "done", "ok": ..., "error": ...}
setlog-post wait <job> [--timeout 秒]
setlog-post rooms              # {"default": "vlog", "rooms": ["vlog", ...]}
setlog-post info               # 動画の推奨サイズなど
```

- `post` はジョブをキューに入れて worker を起動し、すぐ `{"ok": true, "job": "..."}` を返す。`--wait` を付けると
  投稿が終わるまで待ってから結果を返す（終了コード 0 は送信成功）。
- `--room` は、繰り返し指定するか、カンマ区切りで複数指定できる。省略すると `DEFAULT_ROOM` になる。`rooms/` に登録されていないルームはその場でエラーになる。
- `--dry` は、送信画面まで進んでキャンセルする。動作確認用。
- 動画はコピーして預かる（`--move` を付けると移動する）。呼び出し側は、`post` が返った後なら元のファイルを削除してよい。
- エミュレータは1台しか動かせないので、setlog-post の投稿は必ず1件ずつ順番に処理される。
  setlog-post を通さずにエミュレータを動かす別のプログラムがある場合は、そのロックファイルを `EXTRA_LOCKS` に書く。

### 動画について

| | |
|---|---|
| 大きさ | **1710×962**（エミュレータのカメラ 1710×1280 のうち setlog が使う上端 16:9 の帯）ならそのまま全面に映る。それ以外のサイズは、長辺を合わせて収め、余白は暗い灰色にする |
| 長さ | Log は動画の **0 秒目から始まり、2 秒強**が残る。20 秒より後は使わない |
| 向き | 枠は横長。縦長の動画は小さく収まるので、回転や切り抜きは呼び出し側で行う |
| 音 | 使わない |

setlog がカメラを開いてから撮り始めるまでの約 5 秒は、先頭フレームの静止（`LEAD`、既定 5 秒）でしのいでいる。
見え方を細かく調整したいときは、呼び出し側で 1710×962 に仕上げてから渡すとよい。

## 仕組み

| ファイル | 役割 |
|---|---|
| `setlog-post` | 呼び出し側の入口（CLI）。ジョブをキューに入れる、状態を返す、ルーム一覧を返す |
| `worker.sh` | キューのジョブを1件ずつ `post.sh` に渡し、`done/<job>/result.json` と `post.log` を残す（直近 20 件を保持し、動画は直近 5 件だけ残す） |
| `post.sh` | 1件ぶんの投稿処理。動画をカメラ用の枠に合わせて AVD を起動し、setlog で撮影して送信し、電源を切る |
| `find_room.py` / `rooms.py` | 送信画面で、アバター画像を手がかりにルームを探す（`rooms/<ルーム名>.png`） |
| `lib/clip.py` | 一言を X のクリップボード経由でエミュレータに渡す（日本語は `adb shell input text` では入力できないため） |
| `bin/` | SDK の準備、エミュレータの作成・起動・安全な電源オフ、ルームの登録、点検 |

常駐はしない。`post` のたびに worker が起動し、キューが空になれば終了する。エミュレータも投稿ごとに起動して停止する。

## 必要なもの

- Linux の PC（X11 のデスクトップと KVM）
- Android SDK の emulator / platform-tools / cmdline-tools と `system-images;android-35;google_apis_playstore;x86_64`、
  JDK。`bin/setup-sdk.sh` が `sdk/` `jdk/` に入れる（すでにある場合は、シンボリックリンクでもよい）
- Python 3.10 以上（Pillow / python-xlib）と `ffmpeg`: `sudo apt install python3-pil python3-xlib ffmpeg`
- setlog（エミュレータ内の Google Play から入れるか、自分の端末から取り出した APK を `apk/` に置く）

## セットアップ

1. `settings.conf.example` を `settings.conf` にコピーして編集する（初回は自動でコピーされる）。
2. `bin/setup-sdk.sh` → `bin/doctor.sh` で、不足しているものを確認する。
3. AVD を作って setlog を入れる: `bin/make-avd.sh`。開いた setlog に**スマホと同じ方法で**サインインし、
   「Transfer from another device」を選んでスマホで承認し、暗号鍵を移す。既存のアカウントで
   「Create a new encryption key」は押さないこと（古い Log が読めなくなるおそれがある）。
   終わったら `bin/stop-emu.sh` で止める（`adb emu kill` を使うと、直前の書き込みが失われる）。
4. 送り先のルームを登録する: `bin/add-rooms.sh`（何も送信せずに、送信画面のルームの行を切り出す）→
   `state/rooms-new/sheet.png` を見て `bin/name-room.sh <番号> "<ルーム名>"`。
5. 動作を確認する: `./setlog-post post 動画.mp4 --room vlog --caption テスト --dry --wait`

## 記録

```sh
tail state/worker.log                 # 各ジョブの開始と結果
cat done/<job>/post.log               # 1件ぶんの詳しい経過
tail state/posts.jsonl                # 送信した Log（時刻・ルーム・一言・送信量）
DRY_RUN=1 ./post.sh done/<job>        # 手動でやり直す（送信画面まで進み、送信はしない）
```

各段階の画面は `state/last-send.png`（一言を貼った直後）、`state/last-room.png`（ルームを選んだ直後）、
`state/last-sent.png`、失敗時は `state/last-fail.png`。

## 作者・ライセンス

作: [horiyu](https://github.com/horiyu)。[MIT License](LICENSE)。
