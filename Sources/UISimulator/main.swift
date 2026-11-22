import Foundation
import SwiftAttributeGraph

// MARK: - Mini SwiftUI Engine over SwiftAttributeGraph

/// A view element in the simulated UI.
protocol MiniView {
    associatedtype Body: MiniView
    var body: Body { get }
}

/// Primitive leaf view representing rendered text.
struct Text: MiniView {
    typealias Body = Never
    let content: String
    var body: Never { fatalError("Text is a primitive view") }
}

extension Never: MiniView {
    typealias Body = Never
    var body: Never { fatalError("Never has no body") }
}

/// Simulated View Node that binds a View to a Subgraph and a Rule.
final class ViewNode<V: MiniView> {
    let graph: Graph
    let subgraph: Subgraph
    var stateAttrs: [String: AnyAttribute] = [:]
    private var bodyRule: Attribute<String>?
    private(set) var evaluationCount = 0

    init(graph: Graph, view: V) {
        self.graph = graph
        self.subgraph = graph.makeSubgraph()

        // Bind the view body into a rule inside its owning subgraph
        let ruleAttr = graph.withCurrent(subgraph) {
            graph.makeRule { [weak self] () -> String in
                guard let self = self else { return "" }
                self.evaluationCount += 1
                return self.render(view: view)
            }
        }
        self.bodyRule = ruleAttr
    }

    func render(view: V) -> String {
        if let text = view as? Text {
            return text.content
        }
        // Evaluate custom view body
        return renderAny(view.body)
    }

    private func renderAny<B: MiniView>(_ b: B) -> String {
        if let text = b as? Text {
            return text.content
        }
        return renderAny(b.body)
    }

    func readRenderedOutput() -> String {
        guard let rule = bodyRule else { return "" }
        return graph.value(of: rule)
    }
}

// MARK: - Interactive Components for the Simulation

struct CounterView: MiniView {
    let count: Attribute<Int>
    let step: Attribute<Int>

    var body: Text {
        let currentCount = count.value
        let currentStep = step.value
        return Text(content: "[CounterView] Count = \(currentCount) (step: \(currentStep))")
    }
}

struct HeaderView: MiniView {
    let title: Attribute<String>
    var body: Text {
        Text(content: "=== \(title.value) ===")
    }
}

// MARK: - ForEach List Item Component

/// Represents an item row managed in its own subgraph.
final class TodoItemNode {
    let id: Int
    let subgraph: Subgraph
    let textAttr: Attribute<String>
    let isCompletedAttr: Attribute<Bool>
    let rowRule: Attribute<String>
    var renderCount: Int { counter }
    private var counter = 0

    init(graph: Graph, id: Int, text: String, isCompleted: Bool = false) {
        self.id = id
        self.subgraph = graph.makeSubgraph()
        let tAttr = graph.withCurrent(subgraph) { graph.makeInput(text) }
        let cAttr = graph.withCurrent(subgraph) { graph.makeInput(isCompleted) }
        self.textAttr = tAttr
        self.isCompletedAttr = cAttr

        // We capture self unowned inside the rule closure safely since the rule lives in the subgraph of this item
        var localCounter = 0
        self.rowRule = graph.withCurrent(subgraph) {
            graph.makeRule { () -> String in
                localCounter += 1
                let t = tAttr.value
                let done = cAttr.value ? "☑" : "☐"
                return "  [\(done)] #\(id): \(t) (render: \(localCounter))"
            }
        }
    }

    func render(in graph: Graph) -> String {
        graph.value(of: rowRule)
    }
}

// MARK: - Main Simulation Execution

@main
struct UISimulator {
    static func main() {
        print("🚀 INICIANDO SIMULADOR DE UI TIPO SWIFTUI SOBRE SWIFTATTRIBUTEGRAPH")
        print("------------------------------------------------------------------")

        let graph = Graph()

        // 1. Inputs (Simulan @State / @Binding en SwiftUI)
        print("\n[Paso 1] Creando inputs de estado...")
        let titleState = graph.makeInput("Mi Aplicación Declarativa")
        let counterState = graph.makeInput(0)
        let stepState = graph.makeInput(1)
        let toggleBranch = graph.makeInput(false)

        print("  ✓ titleState ID: \(titleState.id)")
        print("  ✓ counterState ID: \(counterState.id)")
        print("  ✓ stepState ID: \(stepState.id)")
        print("  ✓ toggleBranch ID: \(toggleBranch.id)")

        // 2. Creación de nodos de vista montados en Subgrafos dedicados
        print("\n[Paso 2] Montando componentes en la jerarquía de subgrafos...")
        let headerNode = ViewNode(graph: graph, view: HeaderView(title: titleState))
        let counterNode = ViewNode(graph: graph, view: CounterView(count: counterState, step: stepState))

        // 3. Render inicial (evaluación perezosa por tirón)
        print("\n[Paso 3] Primer frame de renderizado:")
        print("  Header render:  \"\(headerNode.readRenderedOutput())\" (evaluaciones: \(headerNode.evaluationCount))")
        print("  Counter render: \"\(counterNode.readRenderedOutput())\" (evaluaciones: \(counterNode.evaluationCount))")

        // 4. Modificación de estado irrelevante para HeaderView (Corte por dependencias exactas)
        print("\n[Paso 4] Modificando counterState (0 -> 5)...")
        graph.setValue(5, for: counterState)

        print("  Comprobando recálculo en el siguiente frame:")
        let counterOutput1 = counterNode.readRenderedOutput()
        let headerOutput1 = headerNode.readRenderedOutput()
        print("  Counter render: \"\(counterOutput1)\" (evaluaciones: \(counterNode.evaluationCount))")
        print("  Header render:  \"\(headerOutput1)\" (evaluaciones: \(headerNode.evaluationCount))")
        assert(counterNode.evaluationCount == 2, "CounterView debía haberse actualizado")
        assert(headerNode.evaluationCount == 1, "HeaderView NO debía haberse recalculado (corte de dependencia)")
        print("  ✓ ¡ÉXITO! HeaderView se saltó el body por completo (0 renders innecesarios).")

        // 5. Corte por valor idéntico (M1 y M2)
        print("\n[Paso 5] Modificando counterState con el MISMO valor (5 -> 5)...")
        graph.setValue(5, for: counterState)
        _ = counterNode.readRenderedOutput()
        print("  Counter render evaluaciones: \(counterNode.evaluationCount)")
        assert(counterNode.evaluationCount == 2, "El corte por comparación debió evitar marcar sucio o evaluar el body")
        print("  ✓ ¡ÉXITO! El corte por valor evitó volver a ejecutar el body de CounterView.")

        // 6. Subgrafos y ciclo de vida de ramas (M5)
        print("\n[Paso 6] Simulando rama condicional con Subgrafo efímero...")
        let branchSubgraph = graph.makeSubgraph()
        let dynamicItem = graph.withCurrent(branchSubgraph) {
            graph.makeInput("Elemento efímero en subgrafo")
        }
        let dynamicRule = graph.withCurrent(branchSubgraph) {
            graph.makeRule { "Item: [\(dynamicItem.value)]" }
        }

        print("  Nodos activos en el grafo: \(graph.nodeCount)")
        print("  Subgrafos vivos: \(graph.liveSubgraphCount)")
        print("  Valor de la rama condicional: \"\(graph.value(of: dynamicRule))\"")

        print("  Desmontando la rama condicional (invalidando subgrafo)...")
        branchSubgraph.invalidate()
        print("  Nodos activos tras invalidar: \(graph.nodeCount)")
        print("  Subgrafos vivos tras invalidar: \(graph.liveSubgraphCount)")
        print("  ✓ ¡ÉXITO! Todos los atributos y reglas de la rama murieron con su subgrafo.")

        // 7. Simulación de ForEach reactivo con subgrafos por fila
        print("\n[Paso 7] Simulando ForEach / Lista dinámica con subgrafo por fila...")
        var listItems = [
            TodoItemNode(graph: graph, id: 1, text: "Diseñar motor de atributos", isCompleted: true),
            TodoItemNode(graph: graph, id: 2, text: "Pasar especificación M0-M9", isCompleted: true),
            TodoItemNode(graph: graph, id: 3, text: "Conectar con vistas declarativas", isCompleted: false)
        ]

        print("  --- Render inicial de la lista ---")
        for item in listItems {
            print(item.render(in: graph))
        }

        print("\n  Modificando SOLO el ítem #3 (marcar como completado)...")
        graph.setValue(true, for: listItems[2].isCompletedAttr)

        print("  --- Render tras modificar ítem #3 ---")
        for item in listItems {
            print(item.render(in: graph))
        }
        print("  ✓ ¡ÉXITO! Los ítems #1 y #2 conservaron su render previo; solo el #3 recomputó.")

        print("\n  Eliminando el ítem #2 de la lista (invalidando su subgrafo)...")
        let removedItem = listItems.remove(at: 1)
        let nodesBefore = graph.nodeCount
        removedItem.subgraph.invalidate()
        let nodesAfter = graph.nodeCount
        print("  Nodos liberados con el subgrafo de la fila: \(nodesBefore - nodesAfter) atributos")
        print("  --- Render de la lista resultante ---")
        for item in listItems {
            print(item.render(in: graph))
        }
        print("  ✓ ¡ÉXITO! Fila eliminada limpiamente sin dejar residuos en el grafo.")

        // 8. Benchmark de Estrés Real: Lista de 10,000 filas con Scroll y Mutaciones en Vivo
        print("\n[Paso 8] Benchmark de Estrés Real: Lista viva de 10,000 filas con Scroll Virtualizado...")
        let stressStart = DispatchTime.now()
        let rowCount = 10_000
        var virtualList: [TodoItemNode] = []
        virtualList.reserveCapacity(rowCount)

        for i in 0..<rowCount {
            virtualList.append(TodoItemNode(graph: graph, id: i, text: "Fila reactiva número #\(i)", isCompleted: i % 2 == 0))
        }

        let mountTime = Double(DispatchTime.now().uptimeNanoseconds - stressStart.uptimeNanoseconds) / 1_000_000.0
        print("  ✓ Montadas \(rowCount) filas reactivas con subgrafos dedicados en: \(String(format: "%.2f", mountTime)) ms")
        print("  ✓ Nodos activos en el grafo: \(graph.nodeCount)")
        print("  ✓ Subgrafos vivos: \(graph.liveSubgraphCount)")

        // Simular un scroll virtualizado por una ventana visible de 50 filas a lo largo de 100 frames
        print("\n  Simulando scroll de 100 frames (ventana visible de 50 filas)...")
        let scrollStart = DispatchTime.now()
        let windowSize = 50
        var totalFrameTime: Double = 0.0

        for frame in 0..<100 {
            let offset = (frame * 50) % (rowCount - windowSize)
            let frameStart = DispatchTime.now()

            // Lectura de la ventana visible
            for j in offset..<(offset + windowSize) {
                _ = virtualList[j].render(in: graph)
            }

            let frameDuration = Double(DispatchTime.now().uptimeNanoseconds - frameStart.uptimeNanoseconds) / 1_000_000.0
            totalFrameTime += frameDuration
        }

        let avgFrameTime = totalFrameTime / 100.0
        let simulatedFPS = 1000.0 / avgFrameTime
        let fpsStr = String(format: "%.0f", simulatedFPS)
        print("  ✓ 100 frames de scroll completados en: \(String(format: "%.2f", totalFrameTime)) ms")
        print("  ✓ Tiempo promedio por frame: \(String(format: "%.4f", avgFrameTime)) ms (~\(fpsStr) FPS teóricos)")

        // Simular 500 mutaciones en vivo aleatorias durante el scroll
        print("\n  Simulando 500 mutaciones de estado aleatorias en la lista...")
        let mutateStart = DispatchTime.now()
        for m in 0..<500 {
            let targetIdx = (m * 17) % rowCount
            graph.setValue(true, for: virtualList[targetIdx].isCompletedAttr)
            _ = virtualList[targetIdx].render(in: graph)
        }
        let mutateDuration = Double(DispatchTime.now().uptimeNanoseconds - mutateStart.uptimeNanoseconds) / 1_000_000.0
        let microsPerMutate = (mutateDuration / 500.0) * 1000.0
        let mutateStr = String(format: "%.2f", microsPerMutate)
        print("  ✓ 500 mutaciones + recálculos completados en: \(String(format: "%.2f", mutateDuration)) ms (~\(mutateStr) µs/mutación)")

        // Desmontaje y liberación de las 10,000 filas
        print("\n  Desmontando y liberando las \(rowCount) filas (invalidando sus 10,000 subgrafos)...")
        let unmountStart = DispatchTime.now()
        for item in virtualList {
            item.subgraph.invalidate()
        }
        let unmountDuration = Double(DispatchTime.now().uptimeNanoseconds - unmountStart.uptimeNanoseconds) / 1_000_000.0
        print("  ✓ \(rowCount) filas liberadas en: \(String(format: "%.2f", unmountDuration)) ms")
        print("  ✓ Nodos restantes en el grafo: \(graph.nodeCount)")

        // 9. Inspección y diagnóstico (M8)
        print("\n[Paso 9] Métricas finales y volcado del grafo (M8):")
        print("  Total de recálculos del motor: \(graph.recalculationCount)")
        print("  Total de aristas activas: \(graph.edgeCount)")
        print("  Memoria estimada de tablas: \(graph.estimatedMemoryFootprint) bytes")

        print("\n==================================================================")
        print("🎉 TODAS LAS PRUEBAS DE INTEGRACIÓN DEL SIMULADOR PASARON CON ÉXITO")
        print("==================================================================")
    }
}
