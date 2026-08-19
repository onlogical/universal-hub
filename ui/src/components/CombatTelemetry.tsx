import React from "@rbxts/react";
import { ScrollArea, Stack, Text } from "@prism";
import { theme } from "@prism/theme";
import type { CombatFrameData, CombatReplay, CombatTelemetryModel } from "../contracts";

function milliseconds(value?: number): string {
	return value === undefined ? "—" : `${math.max(math.floor(value * 1000 + 0.5), 0)}ms`;
}

function frameLine(side: string, data?: CombatFrameData): string {
	if (data === undefined) return `${side}  idle`;
	return `${side}  ${data.attack ?? "Attack"} · ${data.phase ?? "active"}\nStartup ${milliseconds(data.startup)}   Recovery ${milliseconds(data.recovery)}   Gap ${milliseconds(data.comboGap)}`;
}

function panel(position: UDim2, size: UDim2, children: React.ReactNode): React.ReactElement {
	return (
		<frame Position={position} Size={size} BackgroundColor3={Color3.fromRGB(18, 18, 19)} BackgroundTransparency={0.02} BorderSizePixel={0}>
			<uicorner CornerRadius={new UDim(0, 10)} />
			<uistroke Color={Color3.fromRGB(68, 68, 73)} Transparency={0.2} Thickness={1} />
			{children}
		</frame>
	);
}

function ReplayPanel({ replay }: { readonly replay?: CombatReplay }): React.ReactElement {
	const counts = replay?.counts ?? {};
	return panel(
		new UDim2(1, -390, 0.5, -230),
		UDim2.fromOffset(370, 460),
		<Stack width={new UDim(1, -24)} height={new UDim(1, -24)} position={UDim2.fromOffset(12, 12)} gap="sm">
			<Text text={replay === undefined ? "FIGHT REPLAY" : `FIGHT REPLAY · ${replay.target}`} size="md" weight={800} color={theme.info.main} width="100%" />
			<Text
				text={replay === undefined ? "No completed fight recorded in this session." : `${string.format("%.1f", replay.duration)}s · ${counts.hit ?? 0} hits · ${counts.miss ?? 0} misses · ${counts.missedPunish ?? 0} missed punishes`}
				size="xs"
				weight={600}
				color={theme.text.secondary}
				width="100%"
			/>
			<ScrollArea width="100%" height={370} direction="vertical" scrollbarSize={3}>
				<Stack width="100%" gap="xs">
					{(replay?.entries ?? []).map((entry, index) => (
						<frame key={`${index}:${entry.t}`} Size={new UDim2(1, -4, 0, 46)} BackgroundColor3={Color3.fromRGB(24, 24, 26)} BorderSizePixel={0}>
							<uicorner CornerRadius={new UDim(0, 6)} />
							<Text
								text={`${string.format("%06.2f", entry.t)}  ${entry.title}\n${entry.detail}`}
								size="xs"
								weight={600}
								color={entry.kind === "hit" ? theme.success.main : entry.kind === "missedPunish" ? theme.warning.main : entry.kind === "miss" ? theme.error.main : theme.info.main}
								width="100%"
								height="100%"
								slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left, TextWrapped: true } }}
							/>
						</frame>
					))}
				</Stack>
			</ScrollArea>
		</Stack>,
	);
}

export function CombatTelemetry({ telemetry }: { readonly telemetry?: CombatTelemetryModel }): React.ReactElement {
	if (telemetry === undefined) return <></>;
	return (
		<>
			{telemetry.frameDataVisible && panel(
				new UDim2(0.5, -220, 0, 18),
				UDim2.fromOffset(440, 126),
				<Stack width={new UDim(1, -24)} height={new UDim(1, -24)} position={UDim2.fromOffset(12, 12)} gap="xs">
					<Text text="LIVE FRAME DATA" size="sm" weight={800} color={theme.info.main} width="100%" />
					<Text text={frameLine("SELF", telemetry.frameData?.self)} size="xs" weight={600} color={theme.text.primary} width="100%" />
					<Text text={frameLine("TARGET", telemetry.frameData?.target)} size="xs" weight={600} color={theme.text.primary} width="100%" />
					<Text text={`PUNISH WINDOW  ${milliseconds(telemetry.frameData?.punishWindow)}`} size="xs" weight={800} color={theme.warning.main} width="100%" />
				</Stack>,
			)}
			{telemetry.replayVisible && <ReplayPanel replay={telemetry.replay} />}
		</>
	);
}
