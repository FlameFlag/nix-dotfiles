#!/usr/bin/env bun

import { buildApplication, buildCommand, run } from "@stricli/core";
import { consola } from "consola";
import ky, { HTTPError, type KyInstance } from "ky";
import * as v from "valibot";

const REASONS = [
  "OUTDATED",
  "DUPLICATE",
  "OFF_TOPIC",
  "RESOLVED",
  "SPAM",
  "ABUSE",
] as const;

type Reason = (typeof REASONS)[number];
type Comment = {
  id: number;
  kind: "discussion_r" | "issuecomment";
  owner: string;
  repo: string;
};

const CommentResponse = v.object({ node_id: v.string() });
const MinimizeResponse = v.object({
  data: v.object({
    minimizeComment: v.object({
      minimizedComment: v.object({
        isMinimized: v.boolean(),
        minimizedReason: v.string(),
      }),
    }),
  }),
});

const mutation = `mutation HideComment($id: ID!, $reason: ReportedContentClassifiers!) {
  minimizeComment(input: { subjectId: $id, classifier: $reason }) {
    minimizedComment {
      isMinimized
      minimizedReason
    }
  }
}`;

function fail(message: string): never {
  throw new Error(message);
}

function parseReason(input: string): Reason {
  const reason = input.toUpperCase();
  return REASONS.includes(reason as Reason)
    ? (reason as Reason)
    : fail(
        `Invalid --reason '${input}'. Must be one of: ${REASONS.join(", ")}`,
      );
}

export function parseCommentUrl(input: string): Comment {
  const url = githubUrl(input);
  return { ...repoPath(url, input), ...commentAnchor(url, input) };
}

function githubUrl(input: string) {
  const url = URL.parse(input) ?? fail(`Not a valid URL: ${input}`);
  if (url.hostname !== "github.com") fail(`Not a github.com URL: ${input}`);
  return url;
}

function repoPath(url: URL, input: string) {
  const match = /^\/([^/]+)\/([^/]+)\/(?:pull|issues)\//.exec(url.pathname);
  if (!match) fail(`URL is not a pull/issues link: ${input}`);
  return { owner: match[1], repo: match[2] };
}

function commentAnchor(url: URL, input: string) {
  const anchor = /^(issuecomment|discussion_r)-?(\d+)$/.exec(url.hash.slice(1));
  if (!anchor) fail(`URL fragment is not a comment anchor: ${input}`);

  return {
    id: Number(anchor[2]),
    kind: anchor[1] as Comment["kind"],
  };
}

async function ghAuthToken() {
  const envToken = process.env.GH_TOKEN ?? process.env.GITHUB_TOKEN;
  if (envToken) return envToken;

  return await ghAuthTokenFromCli();
}

async function ghAuthTokenFromCli() {
  const proc = Bun.spawn(["gh", "auth", "token"], {
    stderr: "pipe",
    stdout: "pipe",
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  if (exitCode !== 0) fail(stderr.trim() || "gh auth token failed");
  return stdout.trim();
}

async function githubApi() {
  return ky.create({
    headers: {
      accept: "application/vnd.github+json",
      authorization: `Bearer ${await ghAuthToken()}`,
      "x-github-api-version": "2022-11-28",
    },
    prefix: "https://api.github.com",
  });
}

function commentPath({ id, kind, owner, repo }: Comment) {
  return kind === "issuecomment"
    ? `repos/${owner}/${repo}/issues/comments/${id}`
    : `repos/${owner}/${repo}/pulls/comments/${id}`;
}

async function nodeId(api: KyInstance, comment: Comment) {
  return v.parse(CommentResponse, await api.get(commentPath(comment)).json())
    .node_id;
}

async function minimize(api: KyInstance, id: string, reason: Reason) {
  const response = v.parse(
    MinimizeResponse,
    await api
      .post("graphql", { json: { query: mutation, variables: { id, reason } } })
      .json(),
  ).data.minimizeComment.minimizedComment;

  if (!response.isMinimized) fail("unexpected minimize response");
  return response.minimizedReason;
}

async function hide(api: KyInstance, url: string, reason: Reason) {
  consola.info(`Processing ${url}`);

  try {
    const id = await nodeId(api, parseCommentUrl(url));
    consola.success(`${url}: hidden as ${await minimize(api, id, reason)}`);
    return true;
  } catch (error) {
    consola.error(`${url}: ${await errorMessage(error)}`);
    return false;
  }
}

async function errorMessage(error: unknown) {
  if (error instanceof HTTPError) return await error.response.text();
  return error instanceof Error ? error.message : String(error);
}

async function readUrls() {
  const { createInterface } = await import("node:readline/promises");
  const rl = createInterface({ input: process.stdin, output: process.stderr });
  const urls: string[] = [];

  consola.info("Interactive mode. Paste comment URLs, blank line to quit.");
  try {
    for (;;) {
      const url = (await rl.question("url> ")).trim();
      if (!url) return urls;
      urls.push(url);
    }
  } finally {
    rl.close();
  }
}

async function hideAll(reason: Reason, urls: readonly string[]) {
  const api = await githubApi();
  const inputs = await inputUrls(urls);
  assertHiddenCount(await hideCount(api, inputs, reason), inputs.length);
}

async function inputUrls(urls: readonly string[]) {
  return urls.length > 0 ? urls : await readUrls();
}

async function hideCount(
  api: KyInstance,
  inputs: readonly string[],
  reason: Reason,
) {
  let hidden = 0;

  for (const url of inputs) {
    if (await hide(api, url, reason)) hidden += 1;
  }

  return hidden;
}

function assertHiddenCount(hidden: number, total: number) {
  consola.info(`Done. ${hidden}/${total} hidden.`);
  if (hidden < total) fail(`${total - hidden} of ${total} failed`);
}

const command = buildCommand<{ reason: Reason }, readonly string[]>({
  docs: {
    brief: "Hide GitHub comments via the GraphQL minimizeComment mutation",
    customUsage: [
      "[--reason REASON] [url...]",
      "https://github.com/owner/repo/pull/1#issuecomment-123",
      '--reason DUPLICATE "$url1" "$url2"',
    ],
    fullDescription: `Supported reasons: ${REASONS.join(", ")}`,
  },
  func: async ({ reason }, ...urls) => {
    await hideAll(reason, urls);
  },
  parameters: {
    flags: {
      reason: {
        brief: "Classifier for why the comment is being hidden",
        default: "OUTDATED",
        kind: "parsed",
        parse: parseReason,
        placeholder: "reason",
        proposeCompletions: (partial) =>
          REASONS.filter((reason) => reason.startsWith(partial.toUpperCase())),
      },
    },
    positional: {
      kind: "array",
      parameter: {
        brief: "GitHub comment URL",
        parse: String,
        placeholder: "url",
      },
    },
  },
});

if (import.meta.main) {
  await run(
    buildApplication(command, { name: "gh-hide-comment" }),
    Bun.argv.slice(2),
    {
      process,
    },
  );
}
