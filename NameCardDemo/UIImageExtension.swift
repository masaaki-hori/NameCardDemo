import Foundation
import UIKit

extension UIImage {
    func toCIImage() -> CIImage? {
        if let ciImage = self.ciImage {
            return ciImage
        }
        if let cgImage = self.cgImage {
            return CIImage(cgImage: cgImage)
        }
        return nil
    }

    func convertToBuffer() -> CVPixelBuffer? {

        let attributes =
            [
                kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
            ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, Int(self.size.width),
            Int(self.size.height),
            kCVPixelFormatType_32ARGB,
            attributes,
            &pixelBuffer)

        guard status == kCVReturnSuccess else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()

        let context = CGContext(
            data: pixelData,
            width: Int(self.size.width),
            height: Int(self.size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

        context?.translateBy(x: 0, y: self.size.height)
        context?.scaleBy(x: 1.0, y: -1.0)

        UIGraphicsPushContext(context!)
        self.draw(in: CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height))
        UIGraphicsPopContext()

        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

        return pixelBuffer
    }

    func rotatedBy(degree: CGFloat) -> UIImage {
        if Int(degree) % 90 != 0 {
            return self
        }
        let w = self.size.width
        let h = self.size.height

        //写し先を準備
        let s = Int(degree) % 180 != 0 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
        UIGraphicsBeginImageContext(s)
        let context = UIGraphicsGetCurrentContext()!
        //中心点
        if Int(degree) % 180 != 0 {
            context.translateBy(x: h / 2, y: w / 2)
        } else {
            context.translateBy(x: w / 2, y: h / 2)
        }
        if Int(degree) % 180 != 0 {
            //Y軸を反転させる
            context.scaleBy(x: 1.0, y: -1.0)
        } else {
            //Y軸を反転させる
            context.scaleBy(x: 1.0, y: -1.0)
        }

        //回転させる
        let radian = -degree * CGFloat.pi / 180
        context.rotate(by: radian)

        //書き込み
        let rect = CGRect(x: -(w / 2), y: -(h / 2), width: w, height: h)
        context.draw(self.cgImage!, in: rect)

        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return rotatedImage
    }

    func cropImage(rect: CGRect, scale: CGFloat) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(
            CGSize(width: rect.size.width / scale, height: rect.size.height / scale), true, 0.0)
        draw(at: CGPoint(x: -rect.origin.x / scale, y: -rect.origin.y / scale))
        let croppedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return croppedImage
    }
}
