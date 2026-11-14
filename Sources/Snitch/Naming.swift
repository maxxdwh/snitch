import Foundation

/// Turns raw process info into something a non-developer can read
/// ("Next.js · my-app" instead of "node  PID 4821").
enum Naming {
    // Matched against the base name of each command-line argument.
    private static let frameworks: [String: String] = [
        "next": "Next.js", "next-server": "Next.js", "vite": "Vite", "astro": "Astro",
        "nuxt": "Nuxt", "nuxi": "Nuxt", "remix": "Remix", "remix-serve": "Remix",
        "svelte-kit": "SvelteKit", "webpack-dev-server": "Webpack", "webpack": "Webpack",
        "react-scripts": "Create React App", "expo": "Expo", "storybook": "Storybook",
        "parcel": "Parcel", "gatsby": "Gatsby", "eleventy": "Eleventy", "wrangler": "Cloudflare Wrangler",
        "vercel": "Vercel Dev", "netlify": "Netlify Dev", "live-server": "Live Server",
        "http-server": "Static server", "http.server": "Python web server", "serve": "Static server",
        "uvicorn": "FastAPI / Uvicorn", "gunicorn": "Gunicorn", "flask": "Flask", "runserver": "Django",
        "streamlit": "Streamlit", "gradio": "Gradio", "jupyter-lab": "Jupyter", "jupyter-notebook": "Jupyter",
        "jupyter": "Jupyter", "rails": "Rails", "puma": "Rails (Puma)", "php": "PHP server",
        "hugo": "Hugo", "jekyll": "Jekyll", "ollama": "Ollama", "supabase": "Supabase",
        "convex": "Convex", "claude": "Claude Code", "claude-science": "Claude Science",
        "figma-console-mcp": "Figma MCP helper"
    ]

    private static let databases: [String: String] = [
        "postgres": "PostgreSQL", "mysqld": "MySQL", "mongod": "MongoDB", "redis-server": "Redis",
        "redis-stack-server": "Redis", "memcached": "Memcached", "clickhouse": "ClickHouse"
    ]

    // Background tools that happen to listen on a port; not "your" servers.
    private static let helperFrameworks: Set<String> = ["Claude Code", "Figma MCP helper", "Claude Science"]
    private static let databasePorts: Set<Int> = [5432, 3306, 6379, 27017, 11211, 9000]
    private static let systemPrefixes = ["/System", "/usr", "/Library", "/Applications", "/private", "/opt/homebrew/var"]

    static func describe(name: String, args: [String], cwd: String?, ports: [Int]) -> (title: String, framework: String?, folder: String?, kind: ServerKind, isProject: Bool) {
        var tokens = Set<String>()
        for arg in args.prefix(8) {
            let first = arg.split(separator: " ").first.map(String.init) ?? arg
            let base = (first as NSString).lastPathComponent.lowercased()
            tokens.insert(base)
            tokens.insert((base as NSString).deletingPathExtension)   // astro.mjs -> astro
        }
        tokens.insert(name.lowercased())

        var framework: String?
        var kind: ServerKind = .other
        for t in tokens {
            if let db = databases[t] { framework = db; kind = .database; break }
        }
        if framework == nil {
            // Prefer the most specific match deterministically.
            for key in frameworks.keys.sorted() where tokens.contains(key) { framework = frameworks[key]; break }
        }
        if framework == nil, ports.contains(where: { databasePorts.contains($0) && $0 != 9000 }) && !ports.contains(where: { [3000, 5173, 8000, 8080].contains($0) }) {
            kind = .database
        }
        if kind != .database { kind = .web }

        let home = NSHomeDirectory()
        var folder: String?
        if let cwd, cwd != "/", cwd != home {
            folder = (cwd as NSString).lastPathComponent
        }
        let underSystem = cwd.map { c in systemPrefixes.contains(where: { c.hasPrefix($0) }) || c.contains("/Library/") } ?? true
        let hasRealFolder = folder != nil && !underSystem
        // Ephemeral-port-only helpers (editors, MCP servers, agents) aren't "your servers".
        let onlyEphemeral = !ports.isEmpty && ports.allSatisfy { $0 >= 49152 }
        let isHelper = framework.map { helperFrameworks.contains($0) } ?? false
        let isProject = hasRealFolder && !isHelper && (!onlyEphemeral || framework != nil)

        // "dev" vs "preview" etc., so two servers in one folder can be told apart.
        let modes = ["dev", "preview", "start", "serve", "storybook"]
        let mode = args.dropFirst().prefix(6).first { modes.contains($0.lowercased()) }
        if let f = framework, let mode, kind == .web, !["Static server", "Python web server"].contains(f) {
            framework = (mode.lowercased() == "dev") ? f : "\(f) \(mode.lowercased())"
        }

        let title: String
        if name == "ControlCenter" {
            // The classic "why is port 5000/7000 taken?" culprit on modern macOS.
            return ("AirPlay Receiver (macOS)", nil, nil, .other, false)
        }
        switch (framework, hasRealFolder ? folder : nil) {
        case let (f?, d?): title = "\(f) · \(d)"
        case let (f?, nil): title = f
        case let (nil, d?): title = d
        default: title = prettyName(name)
        }
        return (title, framework, hasRealFolder ? folder : nil, kind, isProject)
    }

    private static func prettyName(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return cleaned.isEmpty ? "Unknown process" : cleaned
    }
}
