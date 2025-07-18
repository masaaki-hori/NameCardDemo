# NameCardDemo

📱 **SwiftUI製名刺読み取りアプリ**

Vision Framework と Google Gemini API を活用した、名刺の自動読み取り・データ化アプリケーションです。

## 🎯 機能

- **📸 名刺読み取り**: カメラを使用したリアルタイム名刺スキャン
- **🔍 自動検出**: Vision Framework による名刺の輪郭自動認識
- **📝 文字認識**: Vision Framework の OCR 機能による文字抽出
- **🤖 AI解析**: Google Gemini API による名刺情報の構造化
- **💾 結果表示**: 読み取った名刺画像と抽出データの表示

## 🚀 使用方法

1. **アプリ起動**: トップページの「名刺読み取り」ボタンをタップ
2. **名刺スキャン**: カメラ画面で名刺を読み取り位置に配置
3. **自動認識**: 名刺の外枠に赤いラインが表示されます
4. **位置調整**: 適切な位置に配置すると、ラインが水色に変化
5. **撮影完了**: 1秒後に自動撮影され、デバイスがバイブレーション
6. **結果確認**: トップページに戻り、名刺画像と抽出データを確認

## 🛠 技術スタック

- **フレームワーク**: SwiftUI
- **画像処理**: Vision Framework
  - 名刺検出 (Rectangle Detection)
  - 文字認識 (OCR)
- **AI連携**: Google Gemini API
- **開発言語**: Swift
- **対応OS**: iOS

## 📋 必要な設定

### 1. Google Gemini API キー

Google AI Studio でAPIキーを取得し、プロジェクトに設定してください。

```swift
// APIキーの設定方法
let apiKey = "YOUR_GEMINI_API_KEY"
```

### 2. 権限設定

`Info.plist` にカメラ使用権限を追加してください：

```xml
NSCameraUsageDescription
名刺を読み取るためにカメラを使用します
```

## 🎨 UI/UX 特徴

- **フルスクリーンカメラ**: 没入感のあるスキャン体験
- **オーバーレイ UI**: 読み取り領域以外を暗く表示
- **視覚的フィードバック**: 
  - 赤いライン: 名刺検出中
  - 水色ライン: 撮影準備完了
- **触覚フィードバック**: 撮影完了時のバイブレーション

## 📊 データ処理フロー

```
カメラ撮影 → Vision検出 → 画像切り出し → OCR処理 → Gemini解析 → JSON構造化 → 結果表示
```

## 🔧 インストール方法

1. リポジトリをクローン
```bash
git clone https://github.com/masaaki-hori/NameCardDemo.git
```

2. Xcodeでプロジェクトを開く
```bash
cd NameCardDemo
open NameCardDemo.xcodeproj
```

3. Google Gemini APIキーを設定

4. iOS デバイスでビルド・実行

## 📱 動作環境

- **iOS**: 14.0以上
- **Xcode**: 12.0以上
- **Swift**: 5.0以上

## 🔐 プライバシー

- 撮影された名刺画像は端末内でのみ処理されます
- 文字認識結果のみがGoogle Gemini APIに送信されます
- 個人情報の取り扱いには十分注意してください

## 🤝 コントリビューション

1. このリポジトリをフォーク
2. 機能ブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. Pull Request を作成

## 📄 ライセンス

このプロジェクトは MIT ライセンスの下で公開されています。詳細は [LICENSE](LICENSE) ファイルを参照してください。

## 📧 お問い合わせ

プロジェクトに関するご質問やご提案がございましたら、[Issues](https://github.com/masaaki-hori/NameCardDemo/issues) よりお気軽にお声がけください。

---

**Built with ❤️ using SwiftUI, Vision Framework, and Google Gemini API**