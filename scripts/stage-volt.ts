#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync, readdirSync, rmSync, statSync, watch } from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";

const source = resolve(git(process.cwd(), "rev-parse", "--show-toplevel"));
const destination = resolve(
	process.env.VOLT_WORKSPACE ??
		join(process.env.LOCALAPPDATA ?? join(homedir(), "AppData", "Local"), "Volt", "workspace"),
	"universal-hub",
	"local",
);
const watchMode = process.argv.includes("--watch");

if (process.argv.slice(2).some((argument) => argument !== "--watch")) {
	throw new Error("Usage: node scripts/stage-volt.ts [--watch]");
}

const relativeDestination = relative(source, destination);
if (relativeDestination === "" || (!relativeDestination.startsWith("..") && !isAbsolute(relativeDestination))) {
	throw new Error("Volt staging destination must not be inside the git working tree.");
}

function git(cwd: string, ...arguments_: string[]): string {
	return execFileSync("git", ["-C", cwd, ...arguments_], { encoding: "utf8" }).trim();
}

function sourceFiles(): Set<string> {
	const output = execFileSync(
		"git",
		[
			"-C",
			source,
			"ls-files",
			"-z",
			"--cached",
			"--others",
			"--exclude-standard",
			"--",
			".",
			":(exclude)dumps/**",
		],
		{ encoding: "utf8" },
	);
	return new Set(output.split("\0").filter(Boolean));
}

function destinationFiles(directory = destination): string[] {
	try {
		statSync(directory);
	} catch {
		return [];
	}

	const files: string[] = [];
	for (const entry of readdirSync(directory, { withFileTypes: true })) {
		const path = join(directory, entry.name);
		if (entry.isDirectory()) {
			files.push(...destinationFiles(path));
		} else if (entry.isFile()) {
			files.push(relative(destination, path));
		}
	}
	return files;
}

function stage(): void {
	const files = sourceFiles();
	mkdirSync(destination, { recursive: true });

	for (const file of destinationFiles()) {
		if (!files.has(file)) rmSync(join(destination, file), { force: true });
	}
	for (const file of files) {
		const target = join(destination, file);
		mkdirSync(dirname(target), { recursive: true });
		copyFileSync(join(source, file), target);
	}

	console.log(
		`Staged ${git(source, "branch", "--show-current")}@${git(source, "rev-parse", "--short", "HEAD")} ` +
			`(${files.size} files) -> ${destination}`,
	);
}

stage();
if (watchMode) {
	let timer: NodeJS.Timeout | undefined;
	watch(source, { recursive: true }, (_event, file) => {
		if (file?.startsWith(".git")) return;
		clearTimeout(timer);
		timer = setTimeout(stage, 150);
	});
	console.log("Watching the current checkout; press Ctrl+C to stop.");
}
