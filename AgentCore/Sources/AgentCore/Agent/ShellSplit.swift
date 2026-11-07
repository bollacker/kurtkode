import Foundation

/// The simple commands a shell command line runs, for permission rules and the danger check. Not a full shell parser:
/// it follows quotes (also `$'…'`), backslashes, comments, heredocs, `;` `&` `|` newlines and parentheses, and looks
/// inside `$( )`, backticks, `(( ))`, `sh -c '…'` / `eval` scripts, scripts a shell reads from a here-string or a
/// heredoc, `find -exec` commands, and git aliases and config that run commands, so a command can't slip past a rule by
/// how it's spelled. What it can't read (a computed command name, a shell reading piped input, nesting deeper than it
/// follows) comes back as an `opaque` command, which the danger check asks about and deny/ask rules match.
enum ShellSplit {
    /// Each simple command as its words, quotes removed. Commands inside substitutions and scripts are listed too.
    static func commands(_ line: String) -> [[String]] { commands(line, depth: 0) }

    /// The first word of a command that stands for something unreadable; the second word says what.
    static let opaque = "\u{1}opaque"

    /// Why `words` (one of `commands`'s results) can't be read, or nil for an ordinary command.
    static func opaqueReason(_ words: [String]) -> String? {
        words.first == opaque ? (words.count > 1 ? words[1] : "it can't be read") : nil
    }

    static let maxDepth = 4

    /// Words that run the command after them: dropped (with their options) to find the real command, whose path is
    /// dropped too (`env X=1 nice -n 5 /bin/rm -rf x` → `rm -rf x`). zsh's `=rm` (the path of rm) counts as `rm`;
    /// `env -S 'a b'` splits its string into words.
    static func unwrap(_ words: [String]) -> [String] { unwrapping(words).words }

    /// Why a wrapper's arguments can't be read (an option kurtkode doesn't know, which may or may not take the next
    /// word, or a `timeout` without a duration), or nil. The command found after it could be the wrong one.
    static func unreadableWrapper(_ words: [String]) -> String? { unwrapping(words).problem }

    private static func unwrapping(_ words: [String]) -> (words: [String], problem: String?) {
        var w = words[...]
        var problem: String?
        func unreadable(_ name: String, _ what: String) {
            if problem == nil { problem = "its \(name) arguments can't be read (\(what))" }
        }
        while let first = w.first {
            if isAssignment(first) { w = w.dropFirst(); continue }
            let name = basename(first)
            guard let valued = wrappers[name] else { break }
            let flags = wrapperFlags[name]
            w = w.dropFirst()
            while let opt = w.first, opt.hasPrefix("-"), opt != "-" {
                w = w.dropFirst()
                if opt == "--" { break }
                if name == "env", opt == "-S" || opt == "--split-string" || opt.hasPrefix("--split-string=")
                    || (opt.hasPrefix("-S") && opt.count > 2) {
                    let attached = opt.hasPrefix("--split-string=") ? String(opt.dropFirst("--split-string=".count))
                        : opt.count > 2 && opt.hasPrefix("-S") ? String(opt.dropFirst(2)) : nil
                    let text = attached ?? (w.first ?? "")
                    if attached == nil { w = w.dropFirst() }
                    w = (text.split(whereSeparator: \.isWhitespace).map(String.init) + Array(w))[...]
                    break
                }
                if valued.contains(opt) { w = w.dropFirst(); continue }
                // A wrapper whose options are all known: anything else can't be read, since it may take the next word.
                guard let flags else { continue }
                if opt.hasPrefix("--") {
                    let key = opt.firstIndex(of: "=").map { String(opt[..<$0]) } ?? opt
                    if !(flags.contains(key) || valued.contains(key) && key != opt) { unreadable(name, opt) }
                    continue
                }
                if opt.dropFirst().allSatisfy(\.isNumber) { continue }                   // nice -5, and the like
                for (k, c) in opt.dropFirst().enumerated() {
                    let o = "-\(c)"
                    if valued.contains(o) {
                        if k == opt.count - 2 { w = w.dropFirst() }                      // its value is the next word
                        break                                                         // or the rest of this one
                    }
                    if attachedValue[name]?.contains(o) == true { break }
                    if !flags.contains(o) { unreadable(name, opt); break }
                }
            }
            if name == "env" { while let a = w.first, a.contains("=") { w = w.dropFirst() } }   // env's NAME=value
            if name == "timeout", let d = w.first {                                         // the duration
                if d.range(of: #"^[0-9]*\.?[0-9]+[smhd]?$"#, options: .regularExpression) != nil { w = w.dropFirst() }
                else { unreadable(name, "\(d) isn't a duration") }
            }
            if name == "repeat", let n = w.first, n.allSatisfy(\.isNumber) { w = w.dropFirst() }   // zsh: repeat N cmd
        }
        var out = Array(w)
        if let f = out.first, f.count > 1, f.hasPrefix("="), f.dropFirst().first?.isLetter == true { out[0] = String(f.dropFirst()) }
        if let f = out.first, f.contains("/") { out[0] = basename(f) }
        return (out, problem)
    }

    /// Wrappers, and their options that take a value (short ones as the next word or the rest of the word, long ones
    /// as the next word or after `=`).
    static let wrappers: [String: Set<String>] = [
        "env": ["-u", "-C", "-P", "--unset", "--chdir"], "command": [], "builtin": [], "exec": ["-a"], "nohup": [],
        "time": ["-o", "-f", "--output", "--format"], "nice": ["-n", "--adjustment"],
        "timeout": ["-s", "-k", "--signal", "--kill-after"], "stdbuf": ["-i", "-o", "-e", "--input", "--output", "--error"],
        "xargs": ["-n", "-I", "-J", "-P", "-L", "-R", "-S", "-d", "-s", "-E", "-a", "--max-args", "--max-procs", "--max-chars",
                  "--delimiter", "--arg-file", "--process-slot-var"],
        "sudo": ["-u", "-g", "-h", "-p", "-C", "-U", "-r", "-t", "-D", "-R", "-T", "--user", "--group", "--host", "--prompt",
                 "--close-from", "--other-user", "--role", "--type", "--chdir", "--chroot", "--command-timeout"],
        "doas": ["-u", "-C"], "caffeinate": ["-t", "-w"],
        "noglob": [], "nocorrect": [], "-": [], "repeat": [],                                    // zsh precommands
        "then": [], "do": [], "else": [], "elif": [], "if": [], "while": [], "until": [], "!": [], "{": [], "}": [],
    ]

    /// The options that take no value, for the wrappers whose options are all listed: any other option of theirs
    /// makes the line unreadable (`unreadableWrapper`). Long ones may still be given an optional `=value`.
    static let wrapperFlags: [String: Set<String>] = [
        "env": ["-i", "-0", "-v", "--ignore-environment", "--null", "--debug"],
        "command": ["-p", "-v", "-V"], "exec": ["-c", "-l"],
        "time": ["-p", "-l", "-h", "-a", "-v", "-q", "--append", "--verbose", "--portability", "--quiet"],
        "nice": [], "timeout": ["-v", "-f", "-p", "--verbose", "--foreground", "--preserve-status"], "stdbuf": [],
        "xargs": ["-0", "-r", "-t", "-p", "-o", "-x", "--null", "--no-run-if-empty", "--verbose", "--interactive",
                  "--open-tty", "--exit", "--show-limits", "--replace", "--eof", "--max-lines"],
        "sudo": ["-A", "-b", "-E", "-e", "-H", "-i", "-K", "-k", "-l", "-n", "-P", "-S", "-s", "-V", "-v", "-B", "-N",
                 "--askpass", "--background", "--bell", "--preserve-env", "--edit", "--set-home", "--login",
                 "--remove-timestamp", "--reset-timestamp", "--list", "--non-interactive", "--preserve-groups", "--stdin",
                 "--shell", "--version", "--validate", "--help"],
        "doas": ["-n", "-s", "-L"], "caffeinate": ["-d", "-i", "-m", "-s", "-u"],
    ]

    /// Short options whose value, optional, can only be the rest of the word (GNU xargs's `-i{}`, `-l1`, `-eEOF`).
    private static let attachedValue: [String: Set<String>] = ["xargs": ["-i", "-l", "-e"]]

    static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "ksh", "fish"]

    static func basename(_ word: String) -> String { word.split(separator: "/").last.map(String.init) ?? word }

    static func isAssignment(_ word: String) -> Bool {
        guard let eq = word.firstIndex(of: "="), eq != word.startIndex else { return false }
        let name = word[..<eq]
        return (name.first!.isLetter || name.first == "_") && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Shell options that take a value (`bash -o pipefail -c …`).
    private static let shellValued: Set<String> = ["-o", "+o", "-O", "+O", "--rcfile", "--init-file"]

    /// The script a shell or `eval` runs: `bash -c 'script'`, `sh -lc "…"`, `zsh -o errexit -c …`, `bash <<< '…'`,
    /// `eval …`.
    static func script(of words: [String]) -> String? {
        guard let first = words.first else { return nil }
        if first == "eval" { return words.dropFirst().joined(separator: " ") }
        guard shells.contains(first) else { return nil }
        var i = 1
        while i < words.count, words[i].hasPrefix("-") || words[i].hasPrefix("+"), words[i] != "--", words[i] != "-" {
            let w = words[i]
            if shellValued.contains(w) { i += 2; continue }
            if w.hasPrefix("-"), !w.hasPrefix("--"), w.dropFirst().contains("c") {
                var j = i + 1
                while j < words.count, shellValued.contains(words[j]) || (words[j].hasPrefix("-") && words[j].count > 1) {
                    j += shellValued.contains(words[j]) ? 2 : 1
                }
                return j < words.count ? words[j] : nil
            }
            i += 1
        }
        if let k = words.firstIndex(of: "<<<"), k + 1 < words.count { return words[k + 1] }
        if let w = words.first(where: { $0.hasPrefix("<<<") && $0.count > 3 }) { return String(w.dropFirst(3)) }
        return nil
    }

    /// Whether `words` (unwrapped) run a shell on its standard input: no `-c` script and no script file.
    static func shellReadsInput(_ words: [String]) -> Bool {
        guard let first = words.first, shells.contains(first), script(of: words) == nil else { return false }
        var i = 1
        while i < words.count {
            let w = words[i]
            if shellValued.contains(w) { i += 2; continue }
            if ["<", ">", ">>", "2>", "2>>", "&>", "<<"].contains(w) { i += 2; continue }            // a redirection and its target
            if w.hasPrefix("-") && w != "-" && w != "--" || w.hasPrefix("+") || w.hasPrefix("<") || w.hasPrefix(">")
                || w.first?.isNumber == true && (w.dropFirst().hasPrefix(">") || w.dropFirst().hasPrefix("<")) {
                i += 1
                continue
            }
            if w == "-" || w == "--" { return w == "-" || i + 1 >= words.count }
            return false                                                                    // a script file
        }
        return true
    }

    /// The commands `find -exec`, `-execdir`, `-ok` and `-okdir` run (`{}` left as is).
    static func findCommands(_ words: [String]) -> [[String]] {
        guard words.first == "find" else { return [] }
        var out: [[String]] = []
        var i = 1
        while i < words.count {
            if ["-exec", "-execdir", "-ok", "-okdir"].contains(words[i]) {
                var cmd: [String] = []
                i += 1
                while i < words.count, words[i] != ";", words[i] != "+" { cmd.append(words[i]); i += 1 }
                if !cmd.isEmpty { out.append(cmd) }
            }
            i += 1
        }
        return out
    }

    /// Git config given on the command line that runs commands: an alias to a shell command (`-c alias.x='!rm …'`),
    /// an alias to git subcommands (as a `git …` command), and the keys whose value is a command.
    static func gitCommands(_ words: [String]) -> (scripts: [String], commands: [[String]]) {
        guard words.first == "git" else { return ([], []) }
        let runKeys = ["core.pager", "core.sshcommand", "core.fsmonitor", "core.editor", "core.hookspath", "sequence.editor",
                       "diff.external", "credential.helper", "gpg.program", "pager."]
        var scripts: [String] = [], commands: [[String]] = []
        var i = 1
        while i < words.count, words[i].hasPrefix("-") {
            var setting: String?
            if words[i] == "-c", i + 1 < words.count { setting = words[i + 1]; i += 1 }
            if let s = setting, let eq = s.firstIndex(of: "=") {
                let key = s[..<eq].lowercased(), value = String(s[s.index(after: eq)...])
                if key.hasPrefix("alias.") {
                    if value.hasPrefix("!") { scripts.append(String(value.dropFirst())) }
                    else { commands.append(["git"] + value.split(whereSeparator: \.isWhitespace).map(String.init)) }
                } else if runKeys.contains(where: { key == $0 || $0.hasSuffix(".") && key.hasPrefix($0) }) {
                    scripts.append(value.hasPrefix("!") ? String(value.dropFirst()) : value)
                }
            }
            if ["-C", "--git-dir", "--work-tree", "--namespace"].contains(words[i]) { i += 1 }
            i += 1
        }
        return (scripts, commands)
    }

    /// Why a command's name can't be known before it runs (`$x`, `$(…)`, a glob or brace expansion), or nil.
    static func computedName(_ words: [String]) -> String? {
        guard let first = unwrap(words).first else { return nil }
        if first.contains("$") || first.contains("`") { return "its command name is computed when it runs (\(first))" }
        if first.contains(where: { "*?[".contains($0) }) { return "its command name is a pattern (\(first))" }
        if first.contains("{"), first.contains(",") || first.contains("..") { return "its command name is a brace expansion (\(first))" }
        return nil
    }

    private static func commands(_ line: String, depth: Int) -> [[String]] {
        // Unicode scalars, not Characters: "\r\n" is one Character, and so is a quote followed by a combining mark,
        // but the shell sees each byte.
        let chars = line.unicodeScalars.map(Character.init)
        var out: [[String]] = []
        var inner: [[String]] = []
        var words: [String] = []
        var word: String?
        var heredocs: [(delimiter: String, tabs: Bool, command: Int)] = []
        var bodies: [Int: String] = [:]                // heredoc bodies by the index of the command they feed
        var i = 0

        func endWord() { if let w = word { words.append(w); word = nil } }
        func endCommand() { endWord(); if !words.isEmpty { out.append(words); words = [] } }
        func add(_ s: String) { if word == nil { word = s } else { word!.append(s) } }
        func add(_ c: Character) { if word == nil { word = String(c) } else { word!.append(c) } }
        /// A substitution's commands; its place in the word is kept as a marker.
        func substitute(_ body: String) -> String {
            if depth < maxDepth { inner += commands(body, depth: depth + 1) }
            else { inner.append([opaque, "commands nested more than \(maxDepth) deep"]) }
            return "$(…)"
        }
        /// After a line that started heredocs, skips their bodies (kept for a shell that reads them as its script).
        func skipHeredocs() {
            for h in heredocs {
                var body = ""
                while i + 1 < chars.count {
                    var j = i + 1
                    var text = ""
                    while j < chars.count, chars[j] != "\n" { text.append(chars[j]); j += 1 }
                    i = j
                    if (h.tabs ? text.drop(while: { $0 == "\t" }) : text[...]) == h.delimiter[...] { break }
                    body += text + "\n"
                }
                bodies[h.command, default: ""] += body
            }
            heredocs = []
        }

        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            switch c {
            case " ", "\t":
                endWord()
            case "\\":
                if let next, next != "\n" { add(next) }
                i += 1
            case "#" where word == nil:
                while i + 1 < chars.count, chars[i + 1] != "\n" { i += 1 }
            case "'":
                var w = word ?? ""
                i += 1
                while i < chars.count, chars[i] != "'" { w.append(chars[i]); i += 1 }
                word = w
            case "$" where next == "'":
                // ANSI-C quoting: backslash escapes inside, `\'` doesn't end it.
                var w = word ?? ""
                i += 2
                while i < chars.count, chars[i] != "'" {
                    if chars[i] == "\\", i + 1 < chars.count {
                        let e = chars[i + 1]
                        i += 2
                        switch e {
                        case "n": w.append("\n")
                        case "t": w.append("\t")
                        case "r": w.append("\r")
                        case "x":
                            var hex = ""
                            while hex.count < 2, i < chars.count, chars[i].isHexDigit { hex.append(chars[i]); i += 1 }
                            if let v = UInt32(hex, radix: 16), let u = Unicode.Scalar(v) { w.append(Character(u)) }
                        case "0"..."7":
                            var oct = String(e)
                            while oct.count < 3, i < chars.count, ("0"..."7").contains(chars[i]) { oct.append(chars[i]); i += 1 }
                            if let v = UInt32(oct, radix: 8), let u = Unicode.Scalar(v) { w.append(Character(u)) }
                        default: w.append(e)
                        }
                        continue
                    }
                    w.append(chars[i])
                    i += 1
                }
                word = w
            case "\"":
                var w = word ?? ""
                i += 1
                while i < chars.count, chars[i] != "\"" {
                    let d = chars[i]
                    if d == "\\", i + 1 < chars.count, "\"\\$`\n".contains(chars[i + 1]) {
                        if chars[i + 1] != "\n" { w.append(chars[i + 1]) }
                        i += 2
                        continue
                    }
                    if d == "$", i + 1 < chars.count, chars[i + 1] == "(" {
                        let (body, end) = balanced(chars, from: i + 2)
                        w += substitute(body)
                        i = end + 1
                        continue
                    }
                    if d == "`" {
                        let (body, end) = backticked(chars, from: i + 1)
                        w += substitute(body)
                        i = end + 1
                        continue
                    }
                    w.append(d)
                    i += 1
                }
                word = w
            case "$" where next == "(":
                let (body, end) = balanced(chars, from: i + 2)
                add(substitute(body))
                i = end
            case "`":
                let (body, end) = backticked(chars, from: i + 1)
                add(substitute(body))
                i = end
            case "(" where next == "(" && word == nil:
                // An arithmetic command, `(( y = 1 << 2 ))`: its `<<` is a shift, not a heredoc.
                endCommand()
                let (body, end) = balanced(chars, from: i + 1)
                _ = substitute(body)
                words.append("((…))")
                endCommand()
                i = end
            case "<" where next == "<" && i + 2 < chars.count && chars[i + 2] == "<":
                endWord()
                words.append("<<<")                                  // a here-string, not a heredoc
                i += 2
            case "<" where next == "<":
                // A heredoc: its delimiter, then its body after this line ends.
                endWord()
                i += 2
                var tabs = false
                if i < chars.count, chars[i] == "-" { tabs = true; i += 1 }
                while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
                var delimiter = ""
                while i < chars.count, !" \t\n;&|<>()".contains(chars[i]) {
                    if chars[i] == "'" || chars[i] == "\"" {
                        let q = chars[i]
                        i += 1
                        while i < chars.count, chars[i] != q { delimiter.append(chars[i]); i += 1 }
                    } else if chars[i] != "\\" {
                        delimiter.append(chars[i])
                    }
                    i += 1
                }
                if !delimiter.isEmpty { heredocs.append((delimiter, tabs, out.count)) }
                words.append("<<")
                i -= 1
            case "&" where next == ">" || (i > 0 && (chars[i - 1] == ">" || chars[i - 1] == "<")):
                add("&")                                             // a redirection (&>, 2>&1), not a separator
            case "\n":
                endCommand()
                if !heredocs.isEmpty { skipHeredocs() }
            case ";", "&", "|", "(", ")":
                endCommand()
            default:
                add(c)
            }
            i += 1
        }
        endCommand()

        var result: [[String]] = []
        for (index, words) in out.enumerated() {
            result.append(words)
            let real = unwrap(words)
            var scripts: [String] = []
            var nested: [[String]] = findCommands(real)
            if let script = script(of: real) { scripts.append(script) }
            else if shells.contains(real.first ?? ""), let body = bodies[index] { scripts.append(body) }
            else if shellReadsInput(real) { result.append([opaque, "\(real[0]) runs whatever it reads from its input"]) }
            let git = gitCommands(real)
            scripts += git.scripts
            nested += git.commands
            if let why = computedName(words) { result.append([opaque, why]) }
            if let why = unreadableWrapper(words) { result.append([opaque, why]) }
            for cmd in nested {
                result.append(cmd)
                if let why = computedName(cmd) { result.append([opaque, why]) }
                if let why = unreadableWrapper(cmd) { result.append([opaque, why]) }
            }
            for s in scripts {
                if depth < maxDepth { result += commands(s, depth: depth + 1) }
                else { result.append([opaque, "commands nested more than \(maxDepth) deep"]) }
            }
        }
        return result + inner
    }

    /// The text up to the `)` that closes a `$(` (nested parentheses and quotes followed), and that `)`'s index.
    private static func balanced(_ chars: [Character], from start: Int) -> (String, Int) {
        var depth = 1
        var quote: Character?
        var i = start
        while i < chars.count {
            let c = chars[i]
            if let q = quote {
                if c == "\\" && q == "\"" { i += 1 } else if c == q { quote = nil }
            } else if c == "\\" {
                i += 1
            } else if c == "'" || c == "\"" {
                quote = c
            } else if c == "(" {
                depth += 1
            } else if c == ")" {
                depth -= 1
                if depth == 0 { return (String(chars[start..<i]), i) }
            }
            i += 1
        }
        return (String(chars[min(start, chars.count)...]), chars.count)
    }

    /// The text up to the closing backtick, and its index.
    private static func backticked(_ chars: [Character], from start: Int) -> (String, Int) {
        var i = start
        var body = ""
        while i < chars.count, chars[i] != "`" {
            if chars[i] == "\\", i + 1 < chars.count { body.append(chars[i + 1]); i += 2; continue }
            body.append(chars[i])
            i += 1
        }
        return (body, i)
    }
}
