import Foundation

/// `//` comments: a whole line starting with `//`, or the rest of a line after
/// ` //` (with a space or tab before it, so `https://…` is no comment).
/// Comments are ignored by all calculations and shown muted.
enum CommentSyntax {
    /// UTF-16 offset in `content` where the comment starts, or `nil`.
    static func commentStart(in content: String) -> Int? {
        let text = content as NSString
        var leading = 0
        while leading < text.length, text.character(at: leading) == 0x20 || text.character(at: leading) == 0x09 {
            leading += 1
        }
        if text.length - leading >= 2, text.substring(with: NSRange(location: leading, length: 2)) == "//" {
            return leading
        }
        var search = NSRange(location: 0, length: text.length)
        while true {
            let found = text.range(of: "//", range: search)
            guard found.location != NSNotFound else { return nil }
            if found.location > 0 {
                let before = text.character(at: found.location - 1)
                if before == 0x20 || before == 0x09 { return found.location }
            }
            search = NSRange(location: found.location + 2, length: text.length - found.location - 2)
        }
    }

    /// The content without its comment (trailing spaces removed); empty for comment lines.
    static func code(of content: String) -> String {
        guard let start = commentStart(in: content) else { return content }
        return (content as NSString).substring(to: start).trimmingCharacters(in: .whitespaces)
    }
}
