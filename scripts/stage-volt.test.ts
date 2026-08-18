import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = mkdtempSync(join(tmpdir(), "stage-volt-"));
const repository = join(root, "repo");
const workspace = join(root, "workspace");

execFileSync("git", ["init", repository]);
writeFileSync(join(repository, "tracked.txt"), "tracked");
writeFileSync(join(repository, "untracked.txt"), "untracked");
execFileSync("git", ["-C", repository, "add", "tracked.txt"]);
execFileSync(
	"git",
	[
		"-C",
		repository,
		"-c",
		"user.name=Stage Volt Test",
		"-c",
		"user.email=stage-volt@example.invalid",
		"commit",
		"-m",
		"fixture",
	],
);
execFileSync("node", [join(process.cwd(), "scripts", "stage-volt.ts")], {
	cwd: repository,
	env: { ...process.env, VOLT_WORKSPACE: workspace },
});

const destination = join(workspace, "universal-hub", "local");
assert.equal(readFileSync(join(destination, "tracked.txt"), "utf8"), "tracked");
assert.equal(readFileSync(join(destination, "untracked.txt"), "utf8"), "untracked");
assert.equal(existsSync(join(destination, ".git")), false);

console.log("stage-volt-tests-ok");
