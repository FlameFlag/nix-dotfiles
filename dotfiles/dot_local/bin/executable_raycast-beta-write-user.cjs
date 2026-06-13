#!/usr/bin/env node
// Usage: killall "Raycast Beta" && raycast-beta-write-user.cjs

const fs = require("node:fs/promises");
const https = require("node:https");
const { execFile } = require("node:child_process");
const { homedir, tmpdir } = require("node:os");
const { join } = require("node:path");
const { setTimeout: delay } = require("node:timers/promises");
const { format, promisify } = require("node:util");

const execFileAsync = promisify(execFile);
const APP_SUPPORT = join(
	homedir(),
	"Library/Application Support/com.raycast-x.macos",
);
const RAYCAST_APP = "/Applications/Raycast Beta.app";
const BUNDLE = join(
	RAYCAST_APP,
	"Contents/Resources/macos-app_RaycastDesktopApp.bundle/Contents/Resources",
);
const ADDON = join(BUNDLE, "backend/data.darwin-arm64.node");
const RUNTIME_ROOT = join(APP_SUPPORT, "node/runtime");
const AVATAR_PATH = join(APP_SUPPORT, "avatar.png");
const AVATAR_URL = `file://${AVATAR_PATH}`;
const DEFAULT_AVATAR_URL =
	"https://cdn.donmai.us/original/af/7d/__mori_calliope_hololive_and_1_more_drawn_by_adammaarr__af7da65013b64818bf2fcf573aeb67ea.png";
const KEY_CAPTURE_RETRIES = 30;
const KEY_CAPTURE_INTERVAL_MS = 1000;

const USER = {
	id: "e0vi",
	name: "Evie",
	username: "e0vi",
	handle: "e0vi",
	email: "raycast@ps1.sh",
	image: AVATAR_URL,
	avatar: AVATAR_URL,
	organizations: [],
	has_pro_features: true,
	can_apply_for_free_trial: false,
	subscription: {
		id: "eu0vi",
		status: "active",
		plan_name: "Pro",
		billing_cycle: "yearly",
		renewal_date: "2099-12-31T23:59:59Z",
	},
};

const TOKEN = {
	access_token: "dHJhbnMgcmlnaHRzIGFyZSBodW1hbiByaWdodHM",
	refresh_token: "dHJhbnMgd29tZW4gYXJlIHdvbWVu",
	token_type: "Bearer",
	expires_in: 999999999,
	scope: "read write",
};

async function ensureAvatar() {
	if (await exists(AVATAR_PATH)) {
		console.log("Avatar exists (%d bytes)", (await fs.stat(AVATAR_PATH)).size);
		return;
	}

	if (
		process.env.RAYCAST_AVATAR_SRC &&
		(await exists(process.env.RAYCAST_AVATAR_SRC)) &&
		(await resizeAvatar(process.env.RAYCAST_AVATAR_SRC, "Avatar resized from:"))
	) {
		return;
	}

	await downloadBuffer(DEFAULT_AVATAR_URL)
		.then(async (avatar) => {
			const tempAvatar = join(tmpdir(), "raycast-beta-avatar-source.png");

			await fs.writeFile(tempAvatar, avatar);
			await resizeAvatar(
				tempAvatar,
				"Avatar downloaded and resized from:",
			);
		})
		.catch(() => {});
}

async function restoreOriginalNode(paths) {
	if (!(await exists(paths.nodeReal))) return;

	await fs.rm(paths.nodePath, { force: true });
	await fs.rename(paths.nodeReal, paths.nodePath);
	await fs.rm(paths.hookFile, { force: true });
}

async function extractKey() {
	if (!(await exists(ADDON))) {
		fail("Raycast Beta not found at: %s", BUNDLE);
	}

	const nodeDir = await getRaycastNodeDir();
	if (!nodeDir) {
		fail("Raycast node runtime not found");
	}

	const paths = {
		hookFile: join(nodeDir, ".keydump.cjs"),
		keyFile: join(nodeDir, ".raycast-key-cache"),
		nodePath: join(nodeDir, "node"),
		nodeReal: join(nodeDir, "node.real"),
	};

	if ((await exists(paths.nodeReal)) && (await exists(paths.keyFile))) {
		return (await fs.readFile(paths.keyFile, "utf8")).trim();
	}

	if ((await exists(paths.nodeReal)) && !(await exists(paths.keyFile))) {
		await restoreOriginalNode(paths);
	}

	try {
		await fs.writeFile(paths.hookFile, keyDumpHookSource(paths.keyFile));
		await fs.rename(paths.nodePath, paths.nodeReal);
		await fs.writeFile(
			paths.nodePath,
			[
				"#!/bin/bash",
				`exec ${shellQuote(paths.nodeReal)} --require ${shellQuote(paths.hookFile)} "$@"`,
				"",
			].join("\n"),
			{ mode: 0o755 },
		);

		console.log("Extracting DB key (launching Raycast briefly)...");
		await execFileAsync("open", ["-a", RAYCAST_APP]);

		const captured = await waitForFile(paths.keyFile);

		await execFileAsync("killall", ["Raycast Beta"]).catch(() => {});
		await delay(2000);

		if (!captured) {
			fail("Failed to capture DB key - Raycast may not have started");
		}

		const key = (await fs.readFile(paths.keyFile, "utf8")).trim();
		console.log(
			"Key extracted: %s (%d chars)",
			`${key.slice(0, 16)}...`,
			key.length,
		);
		return key;
	} finally {
		await restoreOriginalNode(paths);
	}
}

async function writeUser(key) {
	const db = new (require(ADDON).DatabaseClient)(APP_SUPPORT, key, () => {});

	if (!db.initReport.overallSuccess) {
		fail("Failed to open database with extracted key");
	}

	await db.userDefaults.set("CurrentUser", JSON.stringify(USER));
	await db.userDefaults.set("OAuthTokenResponse", JSON.stringify(TOKEN));

	const currentUser = JSON.parse(await db.userDefaults.get("CurrentUser"));
	console.log(
		"OK - %s | pro:%s | sub:%s",
		currentUser.name,
		currentUser.has_pro_features,
		currentUser.subscription?.status,
	);
}

async function main() {
	const key = await extractKey();

	await ensureAvatar();
	await writeUser(key);
	console.log("Done. Start Raycast Beta to load the user.");
}

main().catch((error) => {
	console.error(error);
	process.exit(1);
});

async function exists(path) {
	return fs
		.access(path)
		.then(() => true)
		.catch(() => false);
}

function fail(message, ...args) {
	throw new Error(format(message, ...args));
}

async function getRaycastNodeDir() {
	if (!(await exists(RUNTIME_ROOT))) return null;

	return (
		(await fs.readdir(RUNTIME_ROOT))
			.filter((dir) => dir.startsWith("node-v"))
			.sort()
			.map((dir) => join(RUNTIME_ROOT, dir, "bin"))
			.at(-1) ?? null
	);
}

async function resizeAvatar(source, successMessage) {
	return execFileAsync("sips", ["-Z", "256", source, "--out", AVATAR_PATH])
		.then(() => {
			console.log(successMessage, source);
			return true;
		})
		.catch(() => false);
}

async function downloadBuffer(url) {
	return new Promise((resolve, reject) => {
		https
			.get(url, (response) => {
				if (response.statusCode !== 200) {
					response.resume();
					reject(new Error(`HTTP ${response.statusCode}`));
					return;
				}

				const chunks = [];
				response.on("data", (chunk) => chunks.push(chunk));
				response.on("end", () => resolve(Buffer.concat(chunks)));
				response.on("error", reject);
			})
			.on("error", reject);
	});
}

function keyDumpHookSource(keyFile) {
	return [
		`const Module = require("module");`,
		`const originalRequire = Module.prototype.require;`,
		`Module.prototype.require = function requireWithKeyDump(id) {`,
		`  const result = originalRequire.apply(this, arguments);`,
		`  if (id && id.includes("data.darwin-arm64") && result.DatabaseClient) {`,
		`    const OriginalDatabaseClient = result.DatabaseClient;`,
		`    result.DatabaseClient = class DatabaseClientWithKeyDump extends OriginalDatabaseClient {`,
		`      constructor(...args) {`,
		`        require("fs").writeFileSync(${JSON.stringify(keyFile)}, args[1]);`,
		`        super(...args);`,
		`      }`,
		`    };`,
		`  }`,
		`  return result;`,
		`};`,
		"",
	].join("\n");
}

function shellQuote(value) {
	return `'${String(value).replaceAll("'", "'\\''")}'`;
}

async function waitForFile(path) {
	for (const _ of Array.from({ length: KEY_CAPTURE_RETRIES })) {
		if (await exists(path)) return true;
		await delay(KEY_CAPTURE_INTERVAL_MS);
	}

	return false;
}
