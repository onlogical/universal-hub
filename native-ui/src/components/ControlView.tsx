import React from "@rbxts/react";
import { Box, Button, KeybindInput, SegmentedControl, Slider, Stack, Switch, Text } from "@prism";
import { theme } from "@prism/theme";
import type { MenuControl, UniversalHubMenuModel } from "../contracts";

function valueText(value: number, unit?: string): string {
	return `${math.round(value)}${unit === undefined ? "" : ` ${unit}`}`;
}

function intentColor(intent: "primary" | "success" | "warning" | "error" | "info") {
	switch (intent) {
		case "success":
			return theme.success.main;
		case "warning":
			return theme.warning.main;
		case "error":
			return theme.error.main;
		case "info":
			return theme.info.main;
		default:
			return theme.primary.main;
	}
}

function keycapLabel(value: Enum.KeyCode | Enum.UserInputType): string {
	if (value === Enum.KeyCode.LeftShift || value === Enum.KeyCode.RightShift) return "↑  Shift";
	if (value === Enum.KeyCode.LeftControl || value === Enum.KeyCode.RightControl) return "⌃  Ctrl";
	if (value === Enum.KeyCode.LeftAlt || value === Enum.KeyCode.RightAlt) return "⌥  Alt";
	if (value === Enum.KeyCode.Return || value === Enum.KeyCode.KeypadEnter) return "↵  Enter";
	if (value === Enum.KeyCode.Backspace) return "⌫  Backspace";
	if (value === Enum.KeyCode.Tab) return "⇥  Tab";
	if (value === Enum.KeyCode.Space) return "Space";
	return value.Name;
}

function keycapWidth(value: Enum.KeyCode | Enum.UserInputType, capturing: boolean): number {
	if (capturing) return 112;
	if (value === Enum.KeyCode.Space) return 132;
	if (
		value === Enum.KeyCode.LeftShift ||
		value === Enum.KeyCode.RightShift ||
		value === Enum.KeyCode.LeftControl ||
		value === Enum.KeyCode.RightControl ||
		value === Enum.KeyCode.LeftAlt ||
		value === Enum.KeyCode.RightAlt ||
		value === Enum.KeyCode.Return ||
		value === Enum.KeyCode.KeypadEnter ||
		value === Enum.KeyCode.Backspace
	)
		return 104;
	const label = keycapLabel(value);
	return label.size() <= 2 ? 46 : math.clamp(label.size() * 8 + 22, 62, 118);
}

function EditableKeycap({
	value,
	onChange,
	disabled,
}: {
	readonly value: Enum.KeyCode | Enum.UserInputType;
	readonly onChange: (value: Enum.KeyCode | Enum.UserInputType) => void;
	readonly disabled: boolean;
}): React.ReactElement {
	const [capturing, setCapturing] = React.useState(false);
	const [hovered, setHovered] = React.useState(false);
	const width = keycapWidth(value, capturing);
	const topY = hovered && !capturing ? 6 : 7;
	const face = hovered && !capturing ? Color3.fromRGB(52, 49, 51) : Color3.fromRGB(44, 42, 44);
	const faceEdge = capturing
		? Color3.fromRGB(255, 118, 87)
		: hovered
			? Color3.fromRGB(105, 99, 102)
			: Color3.fromRGB(82, 77, 80);
	return (
		<frame BackgroundTransparency={1} BorderSizePixel={0} Size={UDim2.fromOffset(width, 48)}>
			{/* Wide lower shell: this is the visible keycap skirt, not a button shadow. */}
			<frame
				BackgroundColor3={Color3.fromRGB(9, 9, 10)}
				BorderSizePixel={0}
				Position={UDim2.fromOffset(0, 7)}
				Size={UDim2.fromOffset(width, 40)}
			>
				<uicorner CornerRadius={new UDim(0, 8)} />
				<uistroke Color={Color3.fromRGB(55, 52, 54)} Transparency={0.24} Thickness={1} />
			</frame>
			{/* Mid-layer exposes the side ledges and creates the sculpted slope. */}
			<frame
				BackgroundColor3={Color3.fromRGB(25, 24, 26)}
				BorderSizePixel={0}
				Position={UDim2.fromOffset(2, 4)}
				Size={UDim2.fromOffset(width - 4, 38)}
			>
				<uicorner CornerRadius={new UDim(0, 7)} />
				<frame
					BackgroundColor3={Color3.fromRGB(6, 6, 7)}
					BackgroundTransparency={0.15}
					BorderSizePixel={0}
					Position={new UDim2(0, 5, 1, -5)}
					Size={new UDim2(1, -10, 0, 5)}
				>
					<uicorner CornerRadius={new UDim(0, 3)} />
				</frame>
			</frame>
			{/* Full-width top face; the lower shell alone provides physical depth. */}
			<frame
				BackgroundColor3={face}
				BorderSizePixel={0}
				Position={UDim2.fromOffset(2, topY)}
				Size={UDim2.fromOffset(width - 4, 33)}
			>
				<uicorner CornerRadius={new UDim(0, 6)} />
				<uistroke Color={faceEdge} Transparency={0.03} Thickness={capturing ? 1.5 : 1} />
				<frame
					BackgroundColor3={Color3.fromRGB(255, 255, 255)}
					BackgroundTransparency={capturing ? 0.84 : 0.9}
					BorderSizePixel={0}
					Position={UDim2.fromOffset(8, 2)}
					Size={new UDim2(1, -16, 0, 1)}
				/>
				<Text
					text={capturing ? "Press a key…" : keycapLabel(value)}
					size="md"
					weight={800}
					color={theme.text.primary}
					width="100%"
					height={33}
				/>
			</frame>
			<KeybindInput
				value={value}
				onChange={onChange}
				onCapturingChange={setCapturing}
				captureDevice="keyboard"
				clearable={false}
				disabled={disabled}
				width={width}
				height={48}
				position={UDim2.fromOffset(0, 0)}
				Event={{ MouseEnter: () => setHovered(true), MouseLeave: () => setHovered(false) }}
				slotProps={{
					trigger: { BackgroundTransparency: 1, ZIndex: 10 },
					triggerStroke: { Transparency: 1 },
					content: { Visible: false },
				}}
			/>
		</frame>
	);
}

export function ControlView({
	control,
	model,
	hideLabel = false,
	compact = false,
}: {
	readonly control: MenuControl;
	readonly model: UniversalHubMenuModel;
	readonly hideLabel?: boolean;
	readonly compact?: boolean;
}): React.ReactElement {
	const disabled = control.disabled === true || control.status === "unavailable" || control.status === "standby";
	if (control.kind === "segmented") {
		const prominent = control.emphasis === "prominent";
		return (
			<Stack
				width="100%"
				direction={prominent ? "vertical" : "horizontal"}
				align="center"
				justify="spaceBetween"
				gap={prominent ? "sm" : "md"}
			>
				{!hideLabel && (
					<Text
						text={control.label}
						size="md"
						weight={600}
						color={theme.text.primary}
						width={prominent ? "100%" : 120}
						slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left } }}
					/>
				)}
				<SegmentedControl
					options={control.options}
					value={control.value}
					onChange={(value) => model.onValueChange(control.id, value, true)}
					variant="subtle"
					color="primary"
					size="md"
					styleOverrides={{
						frame: (_styles, context) => ({
							backgroundColor: context.theme.colors.background.default,
							strokeColor: context.theme.colors.border.subtle,
							strokeTransparency: 0.35,
						}),
						segment: (_styles, context) => ({
							backgroundColor: context.theme.colors.background.surface,
							backgroundTransparency: 1,
							strokeColor: context.theme.colors.border.subtle,
							strokeTransparency: 1,
							textColor:
								context.state === "selected" ? context.theme.colors.primary.main : context.theme.colors.text.secondary,
							textTransparency: context.state === "disabled" ? 0.45 : 0,
						}),
						indicator: (_styles, context) => ({
							backgroundColor: context.theme.colors.primary.dark,
							backgroundTransparency: 0,
							strokeColor: context.theme.colors.primary.main,
							strokeTransparency: 1,
						}),
					}}
					disabled={disabled}
					width={prominent ? "100%" : 250}
				/>
			</Stack>
		);
	}
	if (control.kind === "slider") {
		const hero = control.emphasis === "hero";
		const intent = control.intent ?? "primary";
		const slider = (
			<Slider
				value={control.value}
				color={intent}
				min={control.min}
				max={control.max}
				step={control.step}
				disabled={disabled}
				fullWidth={hero}
				width={hero ? "100%" : 220}
				size={hero ? "lg" : "md"}
				tooltip={(value) => valueText(value, control.unit)}
				onChange={(value) => model.onValueChange(control.id, value, false)}
				onChangeEnd={(value) => model.onValueChange(control.id, value, true)}
				slotProps={{
					track: { Size: new UDim2(1, 0, 0, hero ? 4 : 3) },
					thumb: { Size: UDim2.fromOffset(hero ? 14 : 10, hero ? 14 : 10) },
					tooltip: { BackgroundColor3: Color3.fromRGB(42, 40, 41), BackgroundTransparency: 0 },
					tooltipStroke: { Color: Color3.fromRGB(67, 64, 65), Transparency: 0.2 },
					tooltipLabel: { TextColor3: Color3.fromRGB(244, 241, 240), TextTransparency: 0 },
					tooltipTail: { ImageColor3: Color3.fromRGB(42, 40, 41), ImageTransparency: 0 },
					tooltipTailBorder: { ImageColor3: Color3.fromRGB(67, 64, 65), ImageTransparency: 0.2 },
				}}
			/>
		);
		if (!hero) {
			return (
				<Stack width="100%" direction="horizontal" align="center" justify="spaceBetween" gap="sm">
					{!hideLabel && (
						<Text
							text={control.label}
							size="sm"
							weight={600}
							color={theme.text.primary}
							width={130}
							slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left } }}
						/>
					)}
					{slider}
					<Text
						text={valueText(control.value, control.unit)}
						size="sm"
						weight={700}
						color={intentColor(intent)}
						width={64}
						slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Right } }}
					/>
				</Stack>
			);
		}
		return (
			<Stack width="100%" gap="md">
				<Stack width="100%" direction="horizontal" align="center" justify="spaceBetween">
					{!hideLabel && <Text text={control.label} size="lg" weight={700} color={theme.text.primary} />}
					<Text text={valueText(control.value, control.unit)} size="xl" weight={700} color={intentColor(intent)} />
				</Stack>
				{slider}
				<Stack width="100%" direction="horizontal" justify="spaceBetween">
					<Text text={valueText(control.min, control.unit)} size="xs" color={theme.text.disabled} />
					<Text text={valueText(control.max, control.unit)} size="xs" color={theme.text.disabled} />
				</Stack>
			</Stack>
		);
	}

	if (control.kind === "toggle") {
		return (
			<Stack width="100%" direction="horizontal" align="center" justify="spaceBetween" gap="md">
				<Text
					text={control.label}
					size="md"
					weight={600}
					color={disabled ? theme.text.disabled : theme.text.primary}
					width={compact ? 142 : 230}
					slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left } }}
				/>
				<Stack direction="horizontal" align="center" justify="end" gap="sm" width={compact ? 44 : 190}>
					{control.keybind !== undefined && (
						<KeybindInput
							value={control.keybind}
							onChange={(value) => model.onValueChange(`${control.id}:keybind`, value, true)}
							disabled={disabled}
							clearable={false}
							size="sm"
							width={132}
						/>
					)}
					<Switch
						checked={control.value}
						onChange={(value) => model.onValueChange(control.id, value, true)}
						disabled={disabled}
						color="primary"
						size="md"
					/>
				</Stack>
			</Stack>
		);
	}

	if (control.kind === "keybind") {
		return (
			<Stack width="100%" direction="horizontal" align="center" justify="spaceBetween" gap="md">
				<Stack gap="xs">
					<Text
						text={control.label}
						size="md"
						weight={600}
						color={disabled ? theme.text.disabled : theme.text.primary}
					/>
					<Text text="Click the keycap, then press a key" size="xs" color={theme.text.disabled} />
				</Stack>
				<EditableKeycap
					value={control.value}
					onChange={(value) => model.onValueChange(control.id, value, true)}
					disabled={disabled || control.readOnly === true}
				/>
			</Stack>
		);
	}

	if (control.kind === "info") {
		const tone = control.tone ?? "info";
		return (
			<Stack width="100%" direction="horizontal" align="center" justify="spaceBetween" gap="md">
				<Text
					text={control.label}
					size="sm"
					weight={600}
					color={theme.text.secondary}
					width={130}
					slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Left } }}
				/>
				<Text
					text={control.value}
					size="sm"
					weight={700}
					color={intentColor(tone)}
					width={290}
					slotProps={{ root: { TextXAlignment: Enum.TextXAlignment.Right } }}
				/>
			</Stack>
		);
	}

	if (control.kind === "model-viewer") return <frame BackgroundTransparency={1} BorderSizePixel={0} />;

	return (
		<Button
			label={control.label}
			variant={control.variant === "primary" ? "filled" : "outline"}
			color={control.variant === "danger" ? "error" : "primary"}
			disabled={disabled}
			fullWidth
			width="100%"
			onPress={() => model.onAction?.(control.action)}
		/>
	);
}
