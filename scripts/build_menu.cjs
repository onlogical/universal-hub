#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const repoRoot = path.resolve(__dirname, "..");
const uiRoot = path.join(repoRoot, "ui");
const distLua = path.join(uiRoot, "dist", "Menu.lua");
const provenancePath = path.join(uiRoot, "dist", "Menu.provenance");
const generatedRoot = path.join(uiRoot, ".generated");

function fail(message) {
	console.error(message);
	process.exit(1);
}

function run(command, args, cwd) {
	const result = spawnSync(command, args, {
		cwd,
		stdio: "inherit",
		shell: process.platform === "win32",
	});
	if (result.status !== 0) {
		fail(`${command} ${args.join(" ")} failed`);
	}
}

function posixRelative(from, to) {
	return path.relative(from, to).split(path.sep).join("/");
}

function resolvePrismRoot() {
	const candidates = [
		process.env.PRISM_ROOT,
		path.join(generatedRoot, "prism"),
		path.resolve(repoRoot, "../prism"),
		path.resolve(repoRoot, "../../prism"),
		"C:/git/prism",
	].filter(Boolean);
	const rejected = [];
	for (const candidate of candidates) {
		const indexPath = path.join(candidate, "src", "lib", "index.ts");
		if (!fs.existsSync(indexPath)) continue;
		const tabsTypes = path.join(candidate, "src", "lib", "components", "Tabs", "types.ts");
		const keybindTypes = path.join(candidate, "src", "lib", "components", "KeybindInput", "types.ts");
		const segmentedTypes = path.join(candidate, "src", "lib", "components", "SegmentedControl", "types.ts");
		const compatible =
			fs.existsSync(tabsTypes) &&
			fs.readFileSync(tabsTypes, "utf8").includes("tabIndicator") &&
			fs.existsSync(keybindTypes) &&
			fs.readFileSync(keybindTypes, "utf8").includes("Enum.UserInputType") &&
			fs.existsSync(segmentedTypes) &&
			fs.readFileSync(segmentedTypes, "utf8").includes("styleOverrides");
		if (compatible) return path.resolve(candidate);
		rejected.push(path.resolve(candidate));
	}
	fail(
		"Set PRISM_ROOT to a compatible Prism checkout containing Tabs.tabIndicator, mouse keybinds, and styleOverrides. Tried: " +
			candidates.join(", ") +
			(rejected.length > 0 ? `. Incompatible: ${rejected.join(", ")}` : ""),
	);
}

function gitHead(directory) {
	const result = spawnSync("git", ["-C", directory, "rev-parse", "HEAD"], {
		encoding: "utf8",
	});
	return result.status === 0 ? result.stdout.trim() : "unknown";
}

function writeJson(filePath, value) {
	fs.mkdirSync(path.dirname(filePath), { recursive: true });
	fs.writeFileSync(filePath, `${JSON.stringify(value, null, "\t")}\n`);
}

function ensureNpmPackage(directory, binaryName) {
	const binary = path.join(
		directory,
		"node_modules",
		".bin",
		process.platform === "win32" ? `${binaryName}.cmd` : binaryName,
	);
	if (!fs.existsSync(binary)) {
		run("npm", ["install"], directory);
	}
	if (!fs.existsSync(binary)) {
		fail(`npm install in ${directory} did not produce ${binaryName}`);
	}
	return binary;
}

function downloadWax(destination) {
	if (fs.existsSync(destination)) {
		return destination;
	}
	const url = "https://github.com/latte-soft/wax/releases/download/0.4.2/wax.luau";
	const result = spawnSync(
		"curl",
		["-fsSL", url, "-o", destination],
		{ stdio: "inherit", shell: process.platform === "win32" },
	);
	if (result.status !== 0 || !fs.existsSync(destination)) {
		fail(`Failed to download Wax 0.4.2 from ${url}. Set WAX_PATH to a local wax.luau.`);
	}
	return destination;
}

function main() {
	const prismRoot = resolvePrismRoot();
	fs.mkdirSync(generatedRoot, { recursive: true });
	fs.mkdirSync(path.join(uiRoot, "dist"), { recursive: true });

	const prismSourceRoot = path.join(generatedRoot, "prism-src");
	fs.rmSync(prismSourceRoot, { recursive: true, force: true });
	fs.cpSync(path.join(prismRoot, "src"), prismSourceRoot, { recursive: true });
	const prismLib = posixRelative(path.join(uiRoot, "src"), path.join(prismSourceRoot, "lib"));
	writeJson(path.join(uiRoot, "tsconfig.prism.json"), {
		compilerOptions: {
			rootDirs: ["src", posixRelative(uiRoot, prismSourceRoot)],
			paths: {
				"@prism": ["prismCompat"],
				"@prism/*": [`${prismLib}/*`],
			},
		},
	});

	const rbxtsc = ensureNpmPackage(uiRoot, "rbxtsc");
	ensureNpmPackage(prismRoot, "rbxtsc");
	if (!fs.existsSync(path.join(prismRoot, "out", "lib"))) {
		run("npm", ["run", "build"], prismRoot);
	}
	run(rbxtsc, ["-p", uiRoot], uiRoot);

	const initPath = path.join(generatedRoot, "init.lua");
	fs.writeFileSync(initPath, "return require(script.ReplicatedStorage.UniversalHubMenu)\n");

	const includePath = path.join(uiRoot, "include");
	const rbxtsPath = path.join(uiRoot, "node_modules", "@rbxts");
	const rbxtsJsPath = path.join(uiRoot, "node_modules", "@rbxts-js");
	if (!fs.existsSync(includePath) || !fs.existsSync(rbxtsPath)) {
		fail("rbxtsc did not emit ui/include and node_modules/@rbxts");
	}

	writeJson(path.join(generatedRoot, "menu.project.json"), {
		name: "UniversalHubNativeBundle",
		tree: {
			$className: "ModuleScript",
			$path: "init.lua",
			ReplicatedStorage: {
				$className: "Folder",
				UniversalHubMenu: {
					$path: posixRelative(generatedRoot, path.join(uiRoot, "out")),
				},
				Prism: {
					$path: posixRelative(generatedRoot, path.join(prismRoot, "out", "lib")),
				},
				rbxts_include: {
					$path: posixRelative(generatedRoot, includePath),
					node_modules: {
						$className: "Folder",
						"@rbxts": {
							$path: posixRelative(generatedRoot, rbxtsPath),
						},
						"@rbxts-js": {
							$path: posixRelative(generatedRoot, rbxtsJsPath),
						},
					},
				},
			},
		},
	});

	const waxPath =
		process.env.WAX_PATH ||
		downloadWax(path.join(generatedRoot, "wax.luau"));
	if (fs.existsSync(path.join(prismRoot, "rokit.toml"))) {
		run("rokit", ["install"], prismRoot);
	}
	run(
		"lune",
		[
			"run",
			waxPath,
			"bundle",
			`input=${path.join(generatedRoot, "menu.project.json")}`,
			`output=${distLua}`,
			"env-name=UniversalHubNativeBundle",
		],
		prismRoot,
	);

	const bundled = fs.readFileSync(distLua, "utf8");
	const entrypoint = "return require(script.ReplicatedStorage.UniversalHubMenu)";
	const entrypointPatched = bundled.includes(entrypoint)
		? bundled
		: bundled.replace(
				/(local ClosureBindings = \{\r?\n\s*function\(\)local wax,script,require=ImportGlobals\(1\)local ImportGlobals return \(function\(\.\.\.\))\r?\n(end\)\(\) end,)/,
				`$1${entrypoint}\n$2`,
			);
	if (!entrypointPatched.includes(entrypoint)) {
		fail("Wax bundle root closure is missing the UniversalHubMenu entrypoint");
	}
	const schedulerPatched = entrypointPatched.replace(
		/local function wrapPerformWorkWithCoroutine\(performWork\)[\s\S]*?\nend\r?\nperformWorkUntilDeadline = wrapPerformWorkWithCoroutine/,
		"local function wrapPerformWorkWithCoroutine(performWork)\n\treturn performWork\nend\nperformWorkUntilDeadline = wrapPerformWorkWithCoroutine",
	);
	if (schedulerPatched === entrypointPatched) {
		fail("Wax bundle is missing wrapPerformWorkWithCoroutine; cannot keep Instance work on the executor thread");
	}
	fs.writeFileSync(distLua, schedulerPatched);

	const sha256 = crypto.createHash("sha256").update(fs.readFileSync(distLua)).digest("hex");
	fs.writeFileSync(
		provenancePath,
		[
			"artifact=ui/dist/Menu.lua",
			`sha256=${sha256}`,
			"prism_repository=https://github.com/3xjn/prism",
			`prism_commit=${gitHead(prismRoot)}`,
			"bundler=https://github.com/latte-soft/wax",
			"bundler_version=0.4.2",
			"mount_parent=gethui()",
			"source=ui/src",
			"",
		].join("\n"),
	);
	console.log(`wrote ${posixRelative(repoRoot, distLua)}`);
}

main();
