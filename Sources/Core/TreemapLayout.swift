import Foundation
import CoreGraphics

/// Squarified treemap yerleşimi (Bruls ve ark.).
/// Verilen ağırlıkları, en-boy oranı 1'e yakın dikdörtgenler olacak şekilde `rect` içine yerleştirir.
/// Çıktı, girdiyle aynı sırada ve aynı uzunluktadır. En iyi sonuç için ağırlıklar azalan sıralı verilmeli.
public func squarifiedTreemap(weights: [Double], in rect: CGRect) -> [CGRect] {
    let positive = weights.map { max(0, $0) }
    let total = positive.reduce(0, +)
    guard total > 0, rect.width > 0, rect.height > 0 else {
        return Array(repeating: .zero, count: weights.count)
    }

    // Ağırlıkları dikdörtgen alanına ölçekle.
    let scale = Double(rect.width * rect.height) / total
    let areas = positive.map { $0 * scale }

    var result = [CGRect](repeating: .zero, count: weights.count)
    var remaining = rect
    var i = 0
    let n = areas.count

    while i < n {
        // Kalan dikdörtgen küçülünce kayan-nokta bozulmasını önle: kalanları .zero bırak.
        if remaining.width <= 0.5 || remaining.height <= 0.5 { break }
        let side = Double(min(remaining.width, remaining.height))
        var rowCount = 0
        var rowSum = 0.0
        var bestWorst = Double.infinity

        // Satırı, en-boy oranı kötüleşene kadar büyüt.
        var j = i
        while j < n {
            let candidateSum = rowSum + areas[j]
            let mn = rowCount == 0 ? areas[j] : min(rowMin(areas, i, j), areas[j])
            let mx = rowCount == 0 ? areas[j] : max(rowMax(areas, i, j), areas[j])
            let worst = worstAspect(min: mn, max: mx, sum: candidateSum, side: side)
            if worst <= bestWorst {
                rowSum = candidateSum
                bestWorst = worst
                rowCount += 1
                j += 1
            } else {
                break
            }
        }

        // Satırı yerleştir (kalınlığı kalan alana sıkıştır).
        if remaining.width <= remaining.height {
            // Yatay şerit (üstte), kalınlık dikey.
            let thickness = min(CGFloat(rowSum / side), remaining.height)
            var x = remaining.minX
            for k in i..<(i + rowCount) {
                let w = min(CGFloat(areas[k]) / max(thickness, 0.0001), remaining.maxX - x)
                result[k] = CGRect(x: x, y: remaining.minY, width: max(w, 0), height: thickness)
                x += w
            }
            remaining = CGRect(x: remaining.minX, y: remaining.minY + thickness,
                               width: remaining.width, height: remaining.height - thickness)
        } else {
            // Dikey şerit (solda), kalınlık yatay.
            let thickness = min(CGFloat(rowSum / side), remaining.width)
            var y = remaining.minY
            for k in i..<(i + rowCount) {
                let h = min(CGFloat(areas[k]) / max(thickness, 0.0001), remaining.maxY - y)
                result[k] = CGRect(x: remaining.minX, y: y, width: thickness, height: max(h, 0))
                y += h
            }
            remaining = CGRect(x: remaining.minX + thickness, y: remaining.minY,
                               width: remaining.width - thickness, height: remaining.height)
        }
        i += max(rowCount, 1)
    }
    return result
}

private func rowMin(_ areas: [Double], _ from: Int, _ to: Int) -> Double {
    var m = Double.infinity
    for k in from..<to { m = min(m, areas[k]) }
    return m
}
private func rowMax(_ areas: [Double], _ from: Int, _ to: Int) -> Double {
    var m = 0.0
    for k in from..<to { m = max(m, areas[k]) }
    return m
}
private func worstAspect(min mn: Double, max mx: Double, sum: Double, side: Double) -> Double {
    guard mn > 0, sum > 0, side > 0 else { return .infinity }
    let s2 = side * side
    let sum2 = sum * sum
    return Swift.max(s2 * mx / sum2, sum2 / (s2 * mn))
}
