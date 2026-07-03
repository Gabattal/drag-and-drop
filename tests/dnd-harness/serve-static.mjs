import { createReadStream, existsSync, statSync } from "node:fs";
import { createServer } from "node:http";
import { extname, join, normalize, resolve, sep } from "node:path";

const root = resolve(process.argv[2] ?? "dist-dnd-harness");
const port = Number(process.argv[3] ?? 5185);

const types = new Map([
    [".css", "text/css; charset=utf-8"],
    [".html", "text/html; charset=utf-8"],
    [".js", "text/javascript; charset=utf-8"],
    [".json", "application/json; charset=utf-8"],
    [".svg", "image/svg+xml"]
]);

function filePath(urlPath) {
    const decoded = decodeURIComponent(urlPath.split("?")[0] ?? "/");
    const relative = decoded === "/" ? "index.html" : decoded.replace(/^\/+/, "");
    const candidate = normalize(join(root, relative));
    if (candidate !== root && !candidate.startsWith(root + sep)) return null;
    return candidate;
}

const server = createServer((request, response) => {
    const candidate = filePath(request.url ?? "/");
    if (!candidate || !existsSync(candidate) || !statSync(candidate).isFile()) {
        response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
        response.end("Not found");
        return;
    }

    response.writeHead(200, {
        "content-type": types.get(extname(candidate)) ?? "application/octet-stream"
    });
    createReadStream(candidate).pipe(response);
});

server.listen(port, "127.0.0.1", () => {
    console.log(`Serving ${ root } on http://127.0.0.1:${ port }/`);
});
