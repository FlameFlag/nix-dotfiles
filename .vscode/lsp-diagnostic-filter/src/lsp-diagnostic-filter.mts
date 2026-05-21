import process from "node:process";
import type { ChildProcess } from "node:child_process";

export type LspMessage = Record<string, unknown> & {
  jsonrpc?: string;
  id?: string | number | null;
  method?: string;
  params?: Record<string, unknown>;
  result?: unknown;
  error?: unknown;
};

export type LspTransform = (message: LspMessage) => LspMessage;
export type UriPredicate = (uri: string) => boolean;
export type ChunkHandler = (chunk: Buffer) => void;

const defaultTemplateUriPatterns = ["/.chezmoitemplates/"];
const forwardedSignals: NodeJS.Signals[] = ["SIGINT", "SIGTERM"];

export function createLspFilter(transform: LspTransform): ChunkHandler {
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
        const message = JSON.parse(body) as unknown;
        if (
          typeof message !== "object" ||
          message === null ||
          Array.isArray(message)
        ) {
          throw new Error("LSP message body must be a JSON object");
        }

        process.stdout.write(
          formatLspMessage(JSON.stringify(transform(message as LspMessage))),
        );
      } catch {
        process.stdout.write(formatLspMessage(body));
      }
    }
  };
}

export function createDiagnosticFilter(
  shouldSuppressDiagnostics: UriPredicate,
): LspTransform {
  return (message) => {
    const uri = message.params?.uri;
    if (
      message.method === "textDocument/publishDiagnostics" &&
      typeof uri === "string" &&
      shouldSuppressDiagnostics(uri)
    ) {
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

export function isTemplateUri(
  uri: string,
  directoryPatterns: string[] = defaultTemplateUriPatterns,
): boolean {
  return (
    uri.endsWith(".tmpl") ||
    directoryPatterns.some((pattern) => uri.includes(pattern))
  );
}

export function relayChildProcess(
  child: ChildProcess,
  commandName: string,
): void {
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

function formatLspMessage(body: string): string {
  return `Content-Length: ${Buffer.byteLength(body, "utf8")}\r\n\r\n${body}`;
}
