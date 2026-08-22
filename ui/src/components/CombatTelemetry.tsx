import React from "@rbxts/react";
import { Button, ScrollArea, Stack, Text } from "@prism";
import { theme } from "@prism/theme";
import type { CombatReplay, CombatTelemetryModel } from "../contracts";

const UserInputService = game.GetService("UserInputService");

type Interaction = {
	readonly kind: "drag" | "resize";
	readonly inputKind: "mouse" | "touch";
	readonly touch?: InputObject;
	readonly pointer: Vector2;
	readonly position: Vector2;
	readonly size: Vector2;
};

function viewportSize(): Vector2 {
	return game.GetService("Workspace").CurrentCamera?.ViewportSize ?? new Vector2(1920, 1080);
}

function beginInputKind(input: InputObject): "mouse" | "touch" | undefined {
	if (input.UserInputType === Enum.UserInputType.MouseButton1) return "mouse";
	if (input.UserInputType === Enum.UserInputType.Touch) return "touch";
	return undefined;
}

function ReplayPanel({ replay }: { readonly replay?: CombatReplay }): React.ReactElement {
	const counts = replay?.counts ?? {};
	const initialViewport = viewportSize();
	const [position, setPosition] = React.useState(new Vector2(math.max(8, initialViewport.X - 390), math.max(8, initialViewport.Y / 2 - 230)));
	const [size, setSize] = React.useState(new Vector2(370, 460));
	const [locked, setLocked] = React.useState(false);
	const interaction = React.useRef<Interaction>();

	React.useEffect(() => {
		const changed = UserInputService.InputChanged.Connect((input) => {
			const active = interaction.current;
			if (active === undefined || locked) return;
			if (active.inputKind === "mouse" && input.UserInputType !== Enum.UserInputType.MouseMovement) return;
			if (active.inputKind === "touch" && input !== active.touch) return;
			const delta = new Vector2(input.Position.X, input.Position.Y).sub(active.pointer);
			const viewport = viewportSize();
			if (active.kind === "drag") {
				setPosition(new Vector2(
					math.clamp(active.position.X + delta.X, 8, math.max(8, viewport.X - active.size.X - 8)),
					math.clamp(active.position.Y + delta.Y, 8, math.max(8, viewport.Y - active.size.Y - 8)),
				));
			} else {
				setSize(new Vector2(
					math.clamp(active.size.X + delta.X, 300, math.max(300, viewport.X - active.position.X - 8)),
					math.clamp(active.size.Y + delta.Y, 260, math.max(260, viewport.Y - active.position.Y - 8)),
				));
			}
		});
		const ended = UserInputService.InputEnded.Connect((input) => {
			const active = interaction.current;
			if (active !== undefined && ((active.inputKind === "mouse" && input.UserInputType === Enum.UserInputType.MouseButton1) || (active.inputKind === "touch" && input === active.touch))) interaction.current = undefined;
		});
		return () => {
			changed.Disconnect();
			ended.Disconnect();
		};
	}, [locked]);

	const begin = (kind: "drag" | "resize", input: InputObject) => {
		if (locked) return;
		const inputKind = beginInputKind(input);
		if (inputKind === undefined) return;
		interaction.current = {
			kind,
			inputKind,
			touch: inputKind === "touch" ? input : undefined,
			pointer: new Vector2(input.Position.X, input.Position.Y),
			position,
			size,
		};
	};

	return (
		<frame Position={UDim2.fromOffset(position.X, position.Y)} Size={UDim2.fromOffset(size.X, size.Y)} BackgroundColor3={Color3.fromRGB(18, 18, 19)} BackgroundTransparency={0.02} BorderSizePixel={0} ClipsDescendants>
			<uicorner CornerRadius={new UDim(0, 10)} />
			<uistroke Color={Color3.fromRGB(68, 68, 73)} Transparency={0.2} Thickness={1} />
			<frame Active BackgroundTransparency={1} Size={new UDim2(1, -92, 0, 42)} Event={{ InputBegan: (_frame, input) => begin("drag", input) }} />
			<Stack width={new UDim(1, -24)} height={new UDim(1, -24)} position={UDim2.fromOffset(12, 12)} gap="sm">
				<Text text={replay === undefined ? "FIGHT REPLAY" : `FIGHT REPLAY · ${replay.target}`} size="md" weight={800} color={theme.info.main} width={new UDim(1, -82)} />
				<Text text={replay === undefined ? "No completed fight recorded in this session." : `${string.format("%.1f", replay.duration)}s · ${counts.hit ?? 0} hits · ${counts.miss ?? 0} misses · ${counts.missedPunish ?? 0} missed punishes`} size="xs" weight={600} color={theme.text.secondary} width="100%" />
				<ScrollArea width="100%" height={new UDim(1, -70)} direction="vertical" scrollbarSize={3}>
					<Stack width="100%" gap="xs">
						{(replay?.entries ?? []).map((entry, index) => (
							<frame key={`${index}:${entry.t}`} Size={new UDim2(1, -4, 0, 46)} BackgroundColor3={Color3.fromRGB(24, 24, 26)} BorderSizePixel={0}>
								<uicorner CornerRadius={new UDim(0, 6)} />
								<Text text={`${string.format("%06.2f", entry.t)}  ${entry.title}\n${entry.detail}`} size="xs" weight={600} color={entry.kind === "hit" ? theme.success.main : entry.kind === "missedPunish" ? theme.warning.main : entry.kind === "miss" ? theme.error.main : theme.info.main} width="100%" height="100%" slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left, TextWrapped: true } }} />
							</frame>
						))}
					</Stack>
				</ScrollArea>
			</Stack>
			<Button label={locked ? "Unlock" : "Lock"} variant={locked ? "filled" : "outline"} size="xs" width={70} height={28} position={new UDim2(1, -82, 0, 8)} onPress={() => { interaction.current = undefined; setLocked(!locked); }} />
			<textbutton Active={!locked} AutoButtonColor={false} BackgroundColor3={locked ? Color3.fromRGB(68, 68, 73) : Color3.fromRGB(77, 163, 255)} BackgroundTransparency={locked ? 0.65 : 0.15} BorderSizePixel={0} Position={new UDim2(1, -18, 1, -18)} Size={UDim2.fromOffset(12, 12)} Text="" Event={{ InputBegan: (_button, input) => begin("resize", input) }}>
				<uicorner CornerRadius={new UDim(0, 3)} />
			</textbutton>
		</frame>
	);
}

export function CombatTelemetry({ telemetry }: { readonly telemetry?: CombatTelemetryModel }): React.ReactElement {
	return telemetry?.replayVisible === true ? <ReplayPanel replay={telemetry.replay} /> : <></>;
}
