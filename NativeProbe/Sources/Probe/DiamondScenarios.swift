final class DiamondCounts {
    var left = 0
    var right = 0
    var join = 0
    var tail = 0
    var snapshots: [[Int]] = []
}

func sharedSourceDiamond(reverse: Bool) {
    let d = Driver()
    defer { d.close() }
    let source = d.input(1)
    let c = DiamondCounts()
    let left = d.rule { c.left += 1; return d.read(source) + 1 }
    let right = d.rule { c.right += 1; return d.read(source) * 2 }
    let join = d.rule {
        c.join += 1
        let a: Int, b: Int
        if reverse { b = d.read(right); a = d.read(left) }
        else { a = d.read(left); b = d.read(right) }
        c.snapshots.append([a, b])
        return a + b
    }
    precondition(c.left == 0 && c.right == 0 && c.join == 0)
    var values: [Int] = [], leftRuns: [Int] = [], rightRuns: [Int] = [], joinRuns: [Int] = []
    for step in 0..<7 {
        switch step {
        case 1:
            d.write(2, to: source); d.write(3, to: source)
            precondition(c.left == 1 && c.right == 1 && c.join == 1)
        case 2: d.write(3, to: source)
        case 3:
            d.write(4, to: source)
            precondition(d.read(left) == 5)
            precondition(c.left == 3 && c.right == 2 && c.join == 2)
        case 4: d.write(0, to: source)
        case 5: d.write(1, to: source); d.write(0, to: source)
        default: break
        }
        values.append(d.read(join))
        leftRuns.append(c.left); rightRuns.append(c.right); joinRuns.append(c.join)
    }
    precondition(values == [4, 10, 10, 13, 1, 1, 1])
    precondition(leftRuns == [1, 2, 2, 3, 4, 5, 5])
    precondition(rightRuns == leftRuns)
    precondition(joinRuns == [1, 2, 2, 3, 4, 4, 4])
    precondition(c.snapshots == [[2, 2], [4, 6], [5, 8], [1, 0]])
    print("diamond-source-\(reverse ? "reverse" : "forward")|values=\(values)|left=\(leftRuns)|right=\(rightRuns)|join=\(joinRuns)|snapshots=\(c.snapshots)")
}

func multipleInputDiamond(reverse: Bool) {
    let d = Driver()
    defer { d.close() }
    let x = d.input(2), y = d.input(10)
    let c = DiamondCounts()
    let left = d.rule { c.left += 1; return d.read(x) + d.read(y) }
    let right = d.rule { c.right += 1; return d.read(x) - d.read(y) }
    let join = d.rule {
        c.join += 1
        let a: Int, b: Int
        if reverse { b = d.read(right); a = d.read(left) }
        else { a = d.read(left); b = d.read(right) }
        c.snapshots.append([a, b])
        return a + b
    }
    let tail = d.rule { c.tail += 1; return d.read(join) * 10 }
    precondition(c.left == 0 && c.right == 0 && c.join == 0 && c.tail == 0)
    var values: [Int] = [], leftRuns: [Int] = [], rightRuns: [Int] = [], joinRuns: [Int] = [], tailRuns: [Int] = []
    for step in 0..<6 {
        let before = [c.left, c.right, c.join, c.tail]
        switch step {
        case 1: d.write(3, to: x); d.write(20, to: y); d.write(4, to: x)
        case 2: d.write(21, to: y)
        case 3: d.write(22, to: y); d.write(21, to: y)
        case 4: d.write(5, to: x); d.write(30, to: y)
        case 5: d.write(5, to: x); d.write(30, to: y)
        default: break
        }
        precondition([c.left, c.right, c.join, c.tail] == before)
        values.append(d.read(tail))
        leftRuns.append(c.left); rightRuns.append(c.right); joinRuns.append(c.join); tailRuns.append(c.tail)
    }
    precondition(values == [40, 80, 80, 80, 100, 100])
    precondition(leftRuns == [1, 2, 3, 4, 5, 5] && rightRuns == leftRuns)
    precondition(joinRuns == [1, 2, 3, 3, 4, 4])
    precondition(tailRuns == [1, 2, 2, 2, 3, 3])
    precondition(c.snapshots == [[12, -8], [24, -16], [25, -17], [35, -25]])
    print("diamond-multiple-\(reverse ? "reverse" : "forward")|values=\(values)|left=\(leftRuns)|right=\(rightRuns)|join=\(joinRuns)|tail=\(tailRuns)|snapshots=\(c.snapshots)")
}
