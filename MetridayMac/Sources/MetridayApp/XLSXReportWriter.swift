import Foundation

/// Writes a small, dependency-free XLSX workbook. The ZIP members are stored
/// without compression, which keeps report delivery reliable on a fresh Mac
/// while remaining readable by Excel, Numbers, and LibreOffice.
enum XLSXReportWriter {
    static func write(to url: URL, rows: [[String]]) throws {
        try makeWorkbook(rows: rows).write(to: url, options: .atomic)
    }

    private static func makeWorkbook(rows: [[String]]) -> Data {
        let worksheet = worksheetXML(rows: rows)
        let entries: [(String, Data)] = [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(rootRelationshipsXML.utf8)),
            ("xl/workbook.xml", Data(workbookXML.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(workbookRelationshipsXML.utf8)),
            ("xl/worksheets/sheet1.xml", Data(worksheet.utf8))
        ]

        var archive = Data()
        var centralDirectory = Data()
        var offset = 0

        for (name, payload) in entries {
            let nameData = Data(name.utf8)
            let crc = crc32(payload)
            archive.appendLE(UInt32(0x04034b50))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(0x0800))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(crc)
            archive.appendLE(UInt32(payload.count))
            archive.appendLE(UInt32(payload.count))
            archive.appendLE(UInt16(nameData.count))
            archive.appendLE(UInt16(0))
            archive.append(nameData)
            archive.append(payload)

            centralDirectory.appendLE(UInt32(0x02014b50))
            centralDirectory.appendLE(UInt16(20))
            centralDirectory.appendLE(UInt16(20))
            centralDirectory.appendLE(UInt16(0x0800))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(crc)
            centralDirectory.appendLE(UInt32(payload.count))
            centralDirectory.appendLE(UInt32(payload.count))
            centralDirectory.appendLE(UInt16(nameData.count))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt32(0))
            centralDirectory.appendLE(UInt32(offset))
            centralDirectory.append(nameData)

            offset += 30 + nameData.count + payload.count
        }

        let centralOffset = archive.count
        archive.append(centralDirectory)
        archive.appendLE(UInt32(0x06054b50))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt32(centralDirectory.count))
        archive.appendLE(UInt32(centralOffset))
        archive.appendLE(UInt16(0))
        return archive
    }

    private static func worksheetXML(rows: [[String]]) -> String {
        let rowXML = rows.enumerated().map { rowIndex, row in
            let cells = row.enumerated().map { columnIndex, value in
                let reference = "\(columnName(columnIndex + 1))\(rowIndex + 1)"
                let safeValue = xmlEscape(value)
                return "<c r=\"\(reference)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(safeValue)</t></is></c>"
            }.joined()
            return "<row r=\"\(rowIndex + 1)\">\(cells)</row>"
        }.joined()
        let lastColumn = columnName(max(1, rows.map(\.count).max() ?? 1))
        let lastRow = max(1, rows.count)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1:\(lastColumn)\(lastRow)"/><sheetData>\(rowXML)</sheetData></worksheet>
        """
    }

    private static func columnName(_ number: Int) -> String {
        var value = max(1, number)
        var result = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            result = String(UnicodeScalar(65 + remainder)!) + result
            value = (value - 1) / 26
        }
        return result
    }

    private static func xmlEscape(_ value: String) -> String {
        value.unicodeScalars.compactMap { scalar in
            switch scalar.value {
            case 0x9, 0xA, 0xD, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF:
                return String(scalar)
            default:
                return nil
            }
        }.joined()
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            var value = (crc ^ UInt32(byte)) & 0xFF
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (value >> 1) ^ 0xEDB88320 : value >> 1
            }
            crc = (crc >> 8) ^ value
        }
        return crc ^ 0xFFFFFFFF
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>
    """

    private static let rootRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
    """

    private static let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Metriday Report" sheetId="1" r:id="rId1"/></sheets></workbook>
    """

    private static let workbookRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>
    """
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
