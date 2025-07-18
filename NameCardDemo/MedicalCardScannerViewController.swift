import UIKit
import AVFoundation
import Vision
import Accelerate
import AudioToolbox

class MedicalCardScannerViewController: UIViewController, /*AVCapturePhotoCaptureDelegate,*/ AVCaptureVideoDataOutputSampleBufferDelegate {
    // SwiftUIへデータを返す
    let delegate: MyDataReceiverDelegate
    init(delegate d: MyDataReceiverDelegate) {
        self.delegate = d
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // カメラ関連
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    // ビジョン関連
    private var visionSequenceHandler = VNSequenceRequestHandler()
    private var lastMatchTimestamp: Date?
    private var matchingStartTime: Date?
    private var isMatched = false
    
    // オーバーレイビュー
    private var overlayView: OverlayView!
    
    // 定数
    private let matchThresholdSeconds: TimeInterval = 1.0
    private let matchPercentageThreshold: CGFloat = 0.05 // 5%
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if #available(iOS 13.0, *) {
            setupCamera()
        } else {
            // Fallback on earlier versions
        }
        setupOverlayView()
        
        // キャンセルボタン設定
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("キャンセル", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)
        
        NSLayoutConstraint.activate([
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startCamera()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopCamera()
    }
    
    @available(iOS 13.0, *)
    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high
        
        guard let backCamera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: backCamera) else {
            return
        }
        
        if captureSession?.canAddInput(input) == true {
            captureSession?.addInput(input)
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        
        if captureSession?.canAddOutput(videoOutput) == true {
            captureSession?.addOutput(videoOutput)
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = view.layer.bounds
        view.layer.addSublayer(previewLayer!)
    }
    
    private func setupOverlayView() {
        overlayView = OverlayView(frame: view.bounds)
        view.addSubview(overlayView)
        
        // 名刺の標準的なアスペクト比 (横:縦 = 約1.65:1)
        let cardAspectRatio: CGFloat = 91.0 / 55.0
        
        // 画面幅の95%を枠の幅とする
        let frameWidth = view.bounds.width * 0.95
        let frameHeight = frameWidth / cardAspectRatio
        
        // 枠のサイズと位置を計算
        let frameRect = CGRect(
            x: (view.bounds.width - frameWidth) / 2,
            y: (view.bounds.height - frameHeight) / 2,
            width: frameWidth,
            height: frameHeight
        )
        
        overlayView.setupCardFrame(frameRect: frameRect, cornerRadius: frameHeight*(2.0/54.0)) // 約3mmの角丸
    }
    
    private func startCamera() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }
    
    private func stopCamera() {
        captureSession?.stopRunning()
    }
    
    @objc private func cancelButtonTapped() {
        stopCamera()
        dismiss(animated: true)
    }
    
    // カメラからのフレーム処理
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // 画像方向の修正
        connection.videoOrientation = .portrait
        
        // 検出リクエスト作成
        let request = VNDetectRectanglesRequest { [weak self] request, error in
            guard let self = self,
                  let results = request.results as? [VNRectangleObservation],
                  !results.isEmpty else { return }
            
            // すべての検出された四角形から最適なものを選択
            if let bestMatch = self.findBestRectangleMatch(results) {
                DispatchQueue.main.async {
                    // 検出された四角形をオーバーレイに描画
                    self.overlayView.updateDetectedRect(bestMatch.boundingBox)
                    
                    // マッチング状態をチェック
                    self.checkForMatch(bestMatch, pixelBuffer: pixelBuffer)
                }
            } else {
                DispatchQueue.main.async {
                    self.overlayView.clearDetectedRect()
                    self.resetMatchingState()
                }
            }
        }
        
        // 最小信頼度設定
        request.minimumConfidence = 0.1
        request.minimumAspectRatio = 1.4 // 横長の四角形を優先
        request.maximumAspectRatio = 2.3
        request.quadratureTolerance = 5.0
        
        do {
            try visionSequenceHandler.perform([request], on: pixelBuffer)
        } catch {
            NSLog("Vision request failed: \(error)")
        }
    }
    
    private func findBestRectangleMatch(_ rectangles: [VNRectangleObservation]) -> VNRectangleObservation? {
        // 理想的なアスペクト比に最も近い四角形を探す
        let idealAspectRatio: CGFloat = 91.0 / 55.0 // 診察券の標準的なアスペクト比
        
        return rectangles.min(by: { rect1, rect2 in
            let aspectRatio1 = rect1.boundingBox.width / rect1.boundingBox.height
            let aspectRatio2 = rect2.boundingBox.width / rect2.boundingBox.height
            
            return abs(aspectRatio1 - idealAspectRatio) < abs(aspectRatio2 - idealAspectRatio)
        })
    }
    
    private func checkForMatch(_ rectangle: VNRectangleObservation, pixelBuffer: CVPixelBuffer) {
        // 基準となるフレームのサイズ (オーバーレイの枠)
        let frameRect = overlayView.cardFrameRect
        let normalizedFrameRect = CGRect(
            x: frameRect.origin.x / view.bounds.width,
            y: 1.0 - (frameRect.origin.y + frameRect.height) / view.bounds.height, // Vision座標系に変換
            width: frameRect.width / view.bounds.width,
            height: frameRect.height / view.bounds.height
        )
        
        // 検出された四角形と基準フレームのサイズ比較
        let widthDifference = abs(rectangle.boundingBox.width - normalizedFrameRect.width) / normalizedFrameRect.width
        let heightDifference = abs(rectangle.boundingBox.height - normalizedFrameRect.height) / normalizedFrameRect.height
        
        // サイズが閾値内に収まっているか確認
        let isWithinSizeThreshold = widthDifference <= matchPercentageThreshold ||
        heightDifference <= matchPercentageThreshold
        
        if isWithinSizeThreshold {
            // 初めてマッチした時間を記録
            if matchingStartTime == nil {
                matchingStartTime = Date()
                overlayView.setMatchStatus(true)
            }
            
            // マッチ継続時間をチェック
            if let startTime = matchingStartTime,
               Date().timeIntervalSince(startTime) >= matchThresholdSeconds,
               !isMatched {
                isMatched = true
                
                // 画像を取得して処理完了
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                
                let topLeft = self.scaled(point: rectangle.topLeft, size: ciImage.extent.size)
                let topRight = self.scaled(point: rectangle.topRight, size: ciImage.extent.size)
                let bottomLeft = self.scaled(point: rectangle.bottomLeft, size: ciImage.extent.size)
                let bottomRight = self.scaled(point: rectangle.bottomRight, size: ciImage.extent.size)
                
                let croppedImage = ciImage.applyingFilter("CIPerspectiveCorrection",
                                                          parameters:
                                                            ["inputTopLeft": CIVector.init(cgPoint: topLeft),
                                                             "inputTopRight": CIVector.init(cgPoint: topRight),
                                                             "inputBottomLeft": CIVector.init(cgPoint: bottomLeft),
                                                             "inputBottomRight": CIVector.init(cgPoint: bottomRight),])
                
                let context = CIContext()
                if let cgImage = context.createCGImage(croppedImage/*ciImage*/, from: croppedImage/*ciImage*/.extent) {
                    let image = UIImage(cgImage: cgImage)
                    let whites = detectBlownHighlightsByLuminance(in: image)
                    if CGFloat(whites.count) / (image.size.width * image.size.height) < 0.005 {
                        AudioServicesPlaySystemSound(1011)
                        delegate.imageReceived(data: image)
                        stopCamera()
                        ocrRequest(image)
                    } else {
                        let snackbar = SnackbarView(message: "白飛びが検出されました", actionTitle: "再検出") {
                            print("元に戻す処理を実行！")
                            self.matchingStartTime = nil
                            self.isMatched = false
                            // ここで元に戻すロジックを実装
                        }
                        snackbar.show(in: self.view)
                    }
                }
            }
        } else {
            overlayView.setMatchStatus(false)
            resetMatchingState()
        }
    }
    
    func scaled(point: CGPoint, size: CGSize) -> CGPoint {
        return CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
    
    private func resetMatchingState() {
        matchingStartTime = nil
        isMatched = false
    }
    
    func detectBlownHighlightsByLuminance(in image: UIImage, luminanceThreshold: Double = 250.0) -> [CGPoint] {
        guard let cgImage = image.cgImage else { return [] }
        
        guard let dataProvider = cgImage.dataProvider,
              let pixelData = dataProvider.data else { return [] }
        
        let data = CFDataGetBytePtr(pixelData)
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = cgImage.bytesPerRow
        
        var blownOutPoints: [CGPoint] = []
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                
                let r = Double(data![offset])       // R
                let g = Double(data![offset + 1])   // G
                let b = Double(data![offset + 2])   // B
                // let a = data![offset + 3]        // alpha（必要なら）
                
                let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                
                if luminance >= luminanceThreshold {
                    blownOutPoints.append(CGPoint(x: x, y: y))
                }
            }
        }
        
        return blownOutPoints
    }

    func ocrRequest(_ image: UIImage) {
        let request = VNRecognizeTextRequest { (request, error) in
            if let results = request.results as? [VNRecognizedTextObservation] {
                let recognizedStrings = results.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                DispatchQueue.main.async {
                    for str in recognizedStrings {
                        NSLog(str)
                    }
                    
                    var strings = ""
                    recognizedStrings.forEach { char in
                        strings += char
                    }
                    
                    Task {
                        await {
                            var response: String = ""
                            response = await self.callGemini(original: strings)
                            
                            if response != "" {
                                var lines = response.split(separator: "\n")
                                if lines.count < 3 {
                                    NSLog("Quality of the image is too low")
                                    self.dismiss(animated: true)
                                    return
                                }
                                lines.removeLast()
                                lines.removeFirst()
                                var json = lines.joined(separator: "\n")
                                json = json.replacingOccurrences(of: "null", with: "\"\"")
                                guard let res = self.jsonDecoder(json: json) else {
                                    json = "{\"company\": \"\",\"division\": \"\",\"title\": \"\",\"zipcode\": \"\",\"address\": \"\",\"tel\": \"\",\"ext\": \"\",\"mobile\": \"\",\"fax\": \"\",\"url\": \"\",\"email\": \"\"";
                                    let res = self.jsonDecoder(json: json)
                                    if res == nil {
                                        NSLog("Failed to decode json: \(json)")
                                    } else {
                                        // メイン画面を更新
                                        let cards: [Card] = [
                                            .init(name: "会社名", value: ""),
                                            .init(name: "部署名", value: ""),
                                            .init(name: "役職名", value: ""),
                                            .init(name: "郵便番号", value: ""),
                                            .init(name: "住所", value: ""),
                                            .init(name: "電話番号", value: ""),
                                            .init(name: "内線番号", value: ""),
                                            .init(name: "携帯番号", value: ""),
                                            .init(name: "FAX番号", value: ""),
                                            .init(name: "URL", value: ""),
                                            .init(name: "メールアドレス", value: "")
                                        ]
                                        self.delegate.mapReceived(data: cards) // Warning is silenced
                                        self.dismiss(animated: true)
                                    }
                                    return
                                }
                                // メイン画面を更新
                                let cards: [Card] = [
                                    .init(name: "会社名", value: res["company"] ?? ""),
                                    .init(name: "部署名", value: res["division"] ?? ""),
                                    .init(name: "役職名", value: res["title"] ?? ""),
                                    .init(name: "郵便番号", value: res["zipcode"] ?? ""),
                                    .init(name: "住所", value: res["address"] ?? ""),
                                    .init(name: "電話番号", value: res["tel"] ?? ""),
                                    .init(name: "内線番号", value: res["ext"] ?? ""),
                                    .init(name: "携帯番号", value: res["mobile"] ?? ""),
                                    .init(name: "FAX番号", value: res["fax"] ?? ""),
                                    .init(name: "URL", value: res["url"] ?? ""),
                                    .init(name: "メールアドレス", value: res["email"] ?? "")
                                ]
                                self.delegate.mapReceived(data: cards) // Warning is silenced
                                self.dismiss(animated: true)
                            } else {
                                NSLog("LLM returned empty string")
                                self.dismiss(animated: true)
                            }
                        }()
                    }
                }
            }
        }
        request.recognitionLanguages = ["ja-jp"]
        request.recognitionLevel = .accurate  // 高精度モード
        request.usesLanguageCorrection = true
        guard let cgImage = image.cgImage else {
            NSLog("Can't get cgImage from UIImage")
            self.dismiss(animated: true)
            return
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global().async {
            do {
                try handler.perform([request])
            } catch {
                NSLog(error.localizedDescription)
                self.dismiss(animated: true)
            }
        }
    }
    
    func callGemini(original: String) async -> String {
        // Access your API key from your on-demand resource .plist file
        // (see "Set up your API key" above)
        // The Gemini 1.5 models are versatile and work with most use cases
        let model = GenerativeModel(name: "gemini-1.5-flash", apiKey: APIKey.default)
        //let model = GenerativeModel(name: "gemini-2.0-flash-ext", apiKey: APIKey.default)

        let prompt = "以下の文字列は日本語の名刺をOCRで読み取った結果です。\n" +
            "文字列には、'会社名'、'部署名'、'役職名'、'郵便番号'、'住所'、'電話番号'、'内線番号'、'携帯番号'、'FAX番号'、'URL'、'メールアドレス'が含まれています。\n" +
            "'郵便番号'は先頭に'〒'がついている場合があります。\n" +
            "'電話番号'、'携帯番号'、'FAX番号'は数字で、区切り記号として' '、'-'、'('、')'が使われることがあります。\n" +
            "'電話番号'で検出された'b'は'6'に変換してください。\n" +
            "'電話番号'で検出された'D'は'0'に変換してください。\n" +
            "'電話番号'で検出された'S'は'5'に変換してください。\n" +
            "'携帯番号'で検出された'b'は'6'に変換してください。\n" +
            "'携帯番号'で検出された'D'は'0'に変換してください。\n" +
            "'携帯番号'で検出された'S'は'5'に変換してください。\n" +
            "'FAX番号'で検出された'b'は'6'に変換してください。\n" +
            "'FAX番号'で検出された'D'は'0'に変換してください。\n" +
            "'FAX番号'で検出された'S'は'5'に変換してください。\n" +
            "抽出された項目をJSON文字列に変換してください。\n" +
            "JSONの項目名を、'会社名'は'company'、'部署名'は'division'、'役職名'は'title'、'郵便番号'は'zipcode'、'住所'は'address'、'電話番号'は'tel'、'内線番号'は'ext'、'携帯番号'は'mobile'、'FAX番号'は'fax'、'URL'は'url'、'メールアドレス'は'email'にしてください。" +
            "\n'''\n" +
            original +
            "\n'''\n"
        do {
          let response = try await model.generateContent(prompt)
          return response.text ?? ""
        } catch {
          // エラーが発生した場合の処理
          NSLog("MyApi.callGemini: \(error.localizedDescription)")
          return ""
        }
    }

    func jsonDecoder(json: String) -> Dictionary<String, String>? {
        struct User: Decodable {
            var company: String
            var division: String
            var title: String
            var zipcode: String
            var address: String
            var tel: String
            var ext: String
            var mobile: String
            var fax: String
            var url: String
            var email: String
        }
        let jsonData = json.data(using: .utf8)!
        guard let user = try? JSONDecoder().decode(User.self, from: jsonData)
        else {
            return nil
        }
        // Flutter側連携するデータ作成
        let res: Dictionary<String, String> = [
             "company": user.company,
             "division": user.division,
             "title": user.title,
             "zipcode": user.zipcode,
             "address": user.address,
             "tel": user.tel,
             "ext": user.ext,
             "mobile": user.mobile,
             "fax": user.fax,
             "url": user.url,
             "email": user.email
         ]
         return res
     }
}

// オーバーレイビュー
class OverlayView: UIView {
    private var shapeLayer = CAShapeLayer()
    private var detectedRectLayer = CAShapeLayer()
    private var cardFramePath = UIBezierPath()
    
    var cardFrameRect: CGRect = .zero
    private var cornerRadius: CGFloat = 3.0
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = .clear
        
        // 半透明のオーバーレイ用シェイプレイヤー
        shapeLayer.fillRule = .evenOdd
        shapeLayer.fillColor = UIColor(white: 0, alpha: 0.5).cgColor
        layer.addSublayer(shapeLayer)
        
        // 検出された長方形用のレイヤー
        detectedRectLayer.strokeColor = UIColor.systemRed.cgColor
        detectedRectLayer.fillColor = nil
        detectedRectLayer.lineWidth = 3.0
        layer.addSublayer(detectedRectLayer)
    }
    
    func setupCardFrame(frameRect: CGRect, cornerRadius: CGFloat) {
        self.cardFrameRect = frameRect
        self.cornerRadius = cornerRadius
        
        // 全画面を覆うパス
        let path = UIBezierPath(rect: bounds)
        
        // 枠の形状を作成（角丸長方形）
        cardFramePath = UIBezierPath(roundedRect: frameRect, cornerRadius: cornerRadius)
        
        // 全体から枠の形状を切り抜く
        path.append(cardFramePath.reversing())
        
        // シェイプレイヤーに適用
        shapeLayer.path = path.cgPath
    }
    
    func updateDetectedRect(_ normalizedRect: CGRect) {
        // VisionのNormalized座標系をUIViewの座標系に変換
        let viewRect = CGRect(
            x: normalizedRect.origin.x * bounds.width,
            y: (1 - normalizedRect.origin.y - normalizedRect.height) * bounds.height,
            width: normalizedRect.width * bounds.width,
            height: normalizedRect.height * bounds.height
        )
        
        let path = UIBezierPath(roundedRect: viewRect, cornerRadius: cornerRadius)
        detectedRectLayer.path = path.cgPath
        detectedRectLayer.isHidden = false
    }
    
    func clearDetectedRect() {
        detectedRectLayer.path = nil
    }
    
    func setMatchStatus(_ isMatching: Bool) {
        detectedRectLayer.strokeColor = isMatching ? UIColor(red: 118.0/255.0, green: 203.0/255.0, blue: 253.0/255.0, alpha:1.0).cgColor : UIColor.systemRed.cgColor
    }
}

class SnackbarView: UIView {

    // MARK: - Properties

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 14)
        label.numberOfLines = 0 // 複数行対応
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var actionButton: UIButton?
    private var dismissTimer: Timer?
    private var action: (() -> Void)?

    // Constants
    private let duration: TimeInterval
    private let bottomPadding: CGFloat = 20 // SafeAreaからの距離など

    // MARK: - Initialization

    init(message: String, duration: TimeInterval = 3.0, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.duration = duration
        self.action = action
        super.init(frame: .zero)

        setupView()
        messageLabel.text = message

        // アクションボタンの設定 (もしあれば)
        if let title = actionTitle {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.setTitleColor(.yellow, for: .normal) // 色は適宜調整
            button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 14)
            button.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
            self.actionButton = button
        }

        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupView() {
        backgroundColor = UIColor.darkGray.withAlphaComponent(0.9)
        layer.cornerRadius = 8
        alpha = 0 // 最初は非表示
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageLabel)
    }

    private func setupLayout() {
        var constraints = [
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ]

        if let button = actionButton {
            // ボタンがある場合
            constraints.append(contentsOf: [
                messageLabel.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -12),
                button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                button.centerYAnchor.constraint(equalTo: centerYAnchor),
                // ボタンのサイズを制約 (任意)
                button.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
            ])
            // ボタンの横幅が文字量に依存するように
             button.setContentHuggingPriority(.required, for: .horizontal)
             button.setContentCompressionResistancePriority(.required, for: .horizontal)
        } else {
            // ボタンがない場合
            constraints.append(messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16))
        }

        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - Presentation / Dismissal

    func show(in view: UIView) {
        // 既存のSnackbarがあれば削除 (簡易的な実装)
        view.subviews.filter { $0 is SnackbarView }.forEach { $0.removeFromSuperview() }

        view.addSubview(self)

        // Auto Layoutで配置 (画面下部、左右中央)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -bottomPadding) // 下からのpadding
            // もし上部に表示したい場合:
            // topAnchor.constraint(equalTo: guide.topAnchor, constant: bottomPadding)
        ])

        // アニメーションで表示
        self.transform = CGAffineTransform(translationX: 0, y: 50) // 少し下から登場
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut], animations: {
            self.alpha = 1.0
            self.transform = .identity
        }) { [weak self] _ in
            guard let self = self else { return }
            // タイマー開始
            self.startDismissTimer()
        }
    }

    private func dismiss() {
        dismissTimer?.invalidate() // タイマー停止
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseIn], animations: { [weak self] in
            guard let self = self else { return }
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: 0, y: 50) // 下に消える
        }) { [weak self] _ in
             self?.removeFromSuperview()
        }
    }

    private func startDismissTimer() {
        dismissTimer?.invalidate() // 念のため既存タイマーを停止
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    // MARK: - Actions

    @objc private func actionButtonTapped() {
        action?() // 設定されたアクションを実行
        dismiss() // アクション実行後、すぐに非表示
    }

    // ビューが表示されている間、タイマーが止まるように (任意)
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Snackbar上のタップであればタイマーをリセットするなど
        if self.point(inside: point, with: event) {
            // dismissTimer?.invalidate() // 一時停止する場合
            // startDismissTimer()      // 再開する場合
        }
        return super.hitTest(point, with: event)
    }
}

extension CVPixelBuffer {
    func crop(to rect: CGRect) -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(self, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(self) else {
            return nil
        }
        
        let inputImageRowBytes = CVPixelBufferGetBytesPerRow(self)
        
        let imageChannels = 4
        let startPos = Int(rect.origin.y) * inputImageRowBytes + imageChannels * Int(rect.origin.x)
        let outWidth = UInt(rect.width)
        let outHeight = UInt(rect.height)
        let croppedImageRowBytes = Int(outWidth) * imageChannels
        
        var inBuffer = vImage_Buffer()
        inBuffer.height = outHeight
        inBuffer.width = outWidth
        inBuffer.rowBytes = inputImageRowBytes
        
        inBuffer.data = baseAddress + UnsafeMutableRawPointer.Stride(startPos)
        
        guard let croppedImageBytes = malloc(Int(outHeight) * croppedImageRowBytes) else {
            return nil
        }
        
        var outBuffer = vImage_Buffer(data: croppedImageBytes, height: outHeight, width: outWidth, rowBytes: croppedImageRowBytes)
        
        let scaleError = vImageScale_ARGB8888(&inBuffer, &outBuffer, nil, vImage_Flags(0))
        
        guard scaleError == kvImageNoError else {
            free(croppedImageBytes)
            return nil
        }
        
        return croppedImageBytes.toCVPixelBuffer(pixelBuffer: self, targetWith: Int(outWidth), targetHeight: Int(outHeight), targetImageRowBytes: croppedImageRowBytes)
    }
    
    func flip() -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(self, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(self) else {
            return nil
        }
        
        let width = UInt(CVPixelBufferGetWidth(self))
        let height = UInt(CVPixelBufferGetHeight(self))
        let inputImageRowBytes = CVPixelBufferGetBytesPerRow(self)
        let outputImageRowBytes = inputImageRowBytes
        
        var inBuffer = vImage_Buffer(
            data: baseAddress,
            height: height,
            width: width,
            rowBytes: inputImageRowBytes)
        
        guard let targetImageBytes = malloc(Int(height) * outputImageRowBytes) else {
            return nil
        }
        var outBuffer = vImage_Buffer(data: targetImageBytes, height: height, width: width, rowBytes: outputImageRowBytes)
        
        // See https://developer.apple.com/documentation/accelerate/vimage/vimage_operations/image_reflection for other transformations
        let reflectError = vImageHorizontalReflect_ARGB8888(&inBuffer, &outBuffer, vImage_Flags(0))
        // let reflectError = vImageVerticalReflect_ARGB8888(&inBuffer, &outBuffer, vImage_Flags(0))
        
        guard reflectError == kvImageNoError else {
            free(targetImageBytes)
            return nil
        }
        
        return targetImageBytes.toCVPixelBuffer(pixelBuffer: self, targetWith: Int(width), targetHeight: Int(height), targetImageRowBytes: outputImageRowBytes)
    }
    
}

extension UnsafeMutableRawPointer {
    // Converts the vImage buffer to CVPixelBuffer
    func toCVPixelBuffer(pixelBuffer: CVPixelBuffer, targetWith: Int, targetHeight: Int, targetImageRowBytes: Int) -> CVPixelBuffer? {
        let pixelBufferType = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let releaseCallBack: CVPixelBufferReleaseBytesCallback = {mutablePointer, pointer in
            if let pointer = pointer {
                free(UnsafeMutableRawPointer(mutating: pointer))
            }
        }

        var targetPixelBuffer: CVPixelBuffer?
        let conversionStatus = CVPixelBufferCreateWithBytes(nil, targetWith, targetHeight, pixelBufferType, self, targetImageRowBytes, releaseCallBack, nil, nil, &targetPixelBuffer)

        guard conversionStatus == kCVReturnSuccess else {
            free(self)
            return nil
        }

        return targetPixelBuffer
    }
}
