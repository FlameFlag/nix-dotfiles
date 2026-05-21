import process from "node:process";
const defaultTemplateUriPatterns = ["/.chezmoitemplates/"];
const forwardedSignals = ["SIGINT", "SIGTERM"];
export function createLspFilter(transform) {
    let buffer = Buffer.alloc(0);
    return (chunk) => {
        buffer = Buffer.concat([buffer, chunk]);
        while (true) {
            const headerEnd = buffer.indexOf("\r\n\r\n");
            if (headerEnd === -1) {
                return;
            }
            const header = buffer.subarray(0, headerEnd).toString("ascii");
            const match = /^Content-Length: (\d+)$/im.exec(header);
            if (!match) {
                process.stdout.write(buffer);
                buffer = Buffer.alloc(0);
                return;
            }
            const length = Number(match[1]);
            const bodyStart = headerEnd + 4;
            const messageEnd = bodyStart + length;
            if (buffer.length < messageEnd) {
                return;
            }
            const body = buffer.subarray(bodyStart, messageEnd).toString("utf8");
            buffer = buffer.subarray(messageEnd);
            try {
                const message = JSON.parse(body);
                if (typeof message !== "object" || message === null || Array.isArray(message)) {
                    throw new Error("LSP message body must be a JSON object");
                }
                process.stdout.write(formatLspMessage(JSON.stringify(transform(message))));
            }
            catch {
                process.stdout.write(formatLspMessage(body));
            }
        }
    };
}
export function createDiagnosticFilter(shouldSuppressDiagnostics) {
    return (message) => {
        const uri = message.params?.uri;
        if (message.method === "textDocument/publishDiagnostics" &&
            typeof uri === "string" &&
            shouldSuppressDiagnostics(uri)) {
            return {
                ...message,
                params: {
                    ...message.params,
                    diagnostics: [],
                },
            };
        }
        return message;
    };
}
export function isTemplateUri(uri, directoryPatterns = defaultTemplateUriPatterns) {
    return uri.endsWith(".tmpl") || directoryPatterns.some((pattern) => uri.includes(pattern));
}
export function relayChildProcess(child, commandName) {
    child.on("error", (error) => {
        console.error(`failed to start ${commandName}: ${error.message}`);
        process.exit(1);
    });
    forwardedSignals.forEach((signal) => {
        process.on(signal, () => {
            if (!child.killed) {
                child.kill(signal);
            }
        });
    });
    child.on("exit", (code, signal) => {
        if (signal) {
            process.kill(process.pid, signal);
            return;
        }
        process.exit(code ?? 0);
    });
}
function formatLspMessage(body) {
    return `Content-Length: ${Buffer.byteLength(body, "utf8")}\r\n\r\n${body}`;
}
