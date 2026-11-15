/// Shell of `List`. Selection is not written: `SelectionValue` is `Never` in every initializer here.
public struct List<SelectionValue: Hashable, Content: View>: View {
    private let content: Content

    fileprivate init(content: Content) {
        self.content = content
        ShellCoverage.record("List")
    }

    public typealias Body = Never
    public var body: Never { fatalError("List is a primitive view") }
}

extension List where SelectionValue == Never {
    public init(@ViewBuilder content: () -> Content) { self.init(content: content()) }
}

extension List {
    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where SelectionValue == Never, Content == ForEach<Data, Data.Element.ID, RowContent>, Data.Element: Identifiable {
        self.init(content: ForEach(data, content: rowContent))
    }

    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
        _ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where SelectionValue == Never, Content == ForEach<Data, ID, RowContent> {
        self.init(content: ForEach(data, id: id, content: rowContent))
    }

    public init<RowContent: View>(
        _ data: Range<Int>, @ViewBuilder rowContent: @escaping (Int) -> RowContent
    ) where SelectionValue == Never, Content == ForEach<Range<Int>, Int, RowContent> {
        self.init(content: ForEach(data, content: rowContent))
    }
}
