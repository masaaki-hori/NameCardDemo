//
//  ContentView.swift
//  NameCardDemo
//
//  Created by 堀正明 on 2025/07/15.
//

import SwiftUI

struct Card: Identifiable {
    let id = UUID()
    var name: String
    var value: String
}

//Protocol
protocol MyDataReceiverDelegate {
    func imageReceived(data: UIImage) //any type of data as your need, I choose String
    func mapReceived(data: [Card]/*Dictionary<String, String>*/)
}

class CardViewModel: ObservableObject, MyDataReceiverDelegate {
    @Published var cards: [Card] = [
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
    @Published var image: Image = Image("Download")

    func imageReceived(data: UIImage) {
        DispatchQueue.main.async {
            self.image = Image(uiImage: data)
        }
    }
    func mapReceived(data: [Card]) {
        DispatchQueue.main.async {
            for i in 0...data.count-1 {
                self.cards[i].value = data[i].value
            }
        }
    }
}

struct ContentView: View { // implementer struct
    @StateObject private var viewModel = CardViewModel()
    @State private var isPresentVC = false
    @State var selectionData : Card.ID? = nil
    @State private var sorting = [KeyPathComparator(\Card.name)]

    var body: some View {
        VStack {
            viewModel.image
                .resizable()
                .scaledToFit()
            List(viewModel.cards) { card in
                Text("\(card.name)：\(card.value)")
            }
            Button("名刺読み取り") {
                isPresentVC = true
            }
        }.fullScreenCover(isPresented: $isPresentVC, content: {
             NameCardViewControllerWrapper(delegate: viewModel)
        })
    }
}
/**
 SwiftUIでviewControllerを表示する際に必要なコード
 */
struct NameCardViewControllerWrapper: UIViewControllerRepresentable {
    var delegate: MyDataReceiverDelegate

    func makeUIViewController(context: Context) -> MedicalCardScannerViewController {
        return MedicalCardScannerViewController(delegate: delegate)
    }

    func updateUIViewController(_ uiViewController: MedicalCardScannerViewController, context: Context) {}
}

#Preview {
    ContentView()
}
