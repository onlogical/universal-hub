#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, renameSync, rmSync, watch } from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";

const source = resolve(
	execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim(),
);
const workspace = resolve(
	process.env.VOLT_WORKSPACE ??
		join(process.env.LOCALAPPDATA ?? join(homedir(), "AppData", "Local"), "Volt", "workspace"),
);
const destination = join(workspace, "universal-hub", "local");
const relativeDestination = relative(source, destination);

if (
	relativeDestination === "" ||
	(!relativeDestination.startsWith("..") && !isAbsolute(relativeDestination))
) {
	throw new Error(`Volt destination must be outside the source tree: ${destination}`);
}

function trackedAndUntrackedFiles(): string[] {
	return execFileSync(
		"git",
		["-C", source, "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
	)
		.toString("utf8")
		.split("\0")
		.filter(
			(file) =>
				file !== "" &&
				file !== "dumps" &&
				!file.startsWith("dumps/") &&
				existsSync(join(source, file)),
		);
}

function stage(): void {
	const files = trackedAndUntrackedFiles();
	const temporary = `${destination}.staging-${process.pid}`;

	rmSync(temporary, { recursive: true, force: true });
	for (const file of files) {
		const target = join(temporary, file);
		mkdirSync(dirname(target), { recursive: true });
		copyFileSync(join(source, file), target);
	}

	rmSync(destination, { recursive: true, force: true });
	mkdirSync(dirname(destination), { recursive: true });
	renameSync(temporary, destination);
	console.log(`Staged ${files.length} files -> ${destination}`);
}

stage();

if (process.argv.includes("--watch")) {
	let timer: NodeJS.Timeout | undefined;
	console.log(`Watching ${source}`);
	watch(source, { recursive: true }, (_event, filename) => {
		const file = String(filename ?? "").replaceAll("\\", "/");
		if (file === ".git" || file.startsWith(".git/") || file === "dumps" || file.startsWith("dumps/")) {
			return;
		}
		clearTimeout(timer);
		timer = setTimeout(stage, 100);
	});
}
