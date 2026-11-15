/// Shell of `ForEach`: one view per element. The row closure is kept and not called, because nothing renders yet.
public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {
    public var data: Data
    public var content: (Data.Element) -> Content
    let id: KeyPath<Data.Element, ID>

    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.id = id
        self.content = content
        ShellCoverage.record("ForEach")
    }

    public typealias Body = Never
    public var body: Never { fatalError("ForEach is a primitive view") }
}

extension ForEach where ID == Data.Element.ID, Content: View, Data.Element: Identifiable {
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data, id: \.id, content: content)
    }
}

extension ForEach where Data == Range<Int>, ID == Int {
    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {
        self.init(data, id: \.self, content: content)
    }
}
